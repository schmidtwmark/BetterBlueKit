import Foundation

/// EU clients using the same refresh credential can share its rotation.
/// Keep the operation alive after cancellation so a spent token can still
/// be replaced in every participating client.
@MainActor
enum EuropeCCIRefresh {
    struct Key: Hashable {
        let accountId: UUID
        let brand: Brand
        let refreshToken: String
    }

    private struct Waiter {
        let adoptRotation: @MainActor (String) -> Void
        var continuation: CheckedContinuation<AuthToken, Error>?
    }

    private static var inFlight: [Key: [UUID: Waiter]] = [:]

    static func hasWaiters(for key: Key) -> Bool {
        inFlight[key]?.values.contains { $0.continuation != nil } == true
    }

    static func run(
        for key: Key,
        adoptRotation: @escaping @MainActor (String) -> Void,
        operation: @escaping @MainActor (_ recordRotation: (String) -> Void) async throws -> AuthToken
    ) async throws -> AuthToken {
        let id = UUID()
        let token = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let waiter = Waiter(adoptRotation: adoptRotation, continuation: continuation)
                if inFlight[key] != nil {
                    inFlight[key]?[id] = waiter
                    return
                }

                inFlight[key] = [id: waiter]
                Task {
                    var rotatedToken: String?
                    let result: Result<AuthToken, Error>
                    do {
                        let authToken = try await operation { rotatedToken = $0 }
                        rotatedToken = authToken.refreshToken
                        result = .success(authToken)
                    } catch {
                        result = .failure(error)
                    }

                    // Publish the rotation before waking callers, even when
                    // the CCS exchange failed. Until then, callers presenting
                    // the original credential share this entire operation.
                    let waiters = inFlight.removeValue(forKey: key) ?? [:]
                    for waiter in waiters.values {
                        if let rotatedToken { waiter.adoptRotation(rotatedToken) }
                        waiter.continuation?.resume(with: result)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                let continuation = inFlight[key]?[id]?.continuation
                inFlight[key]?[id]?.continuation = nil
                continuation?.resume(throwing: CancellationError())
            }
        }
        try Task.checkCancellation()
        return token
    }
}
