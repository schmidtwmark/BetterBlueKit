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
        let clientId: ObjectIdentifier
        let notifyRotation: @MainActor (String) -> Void
        let adoptRotation: @MainActor (String) -> Void
        var continuation: CheckedContinuation<AuthToken, Error>?
    }

    private struct Flight {
        var waiters: [UUID: Waiter]
        var rotatedToken: String?
        var notifiedClients: Set<ObjectIdentifier> = []
    }

    private static var inFlight: [Key: Flight] = [:]

    static func hasWaiters(for key: Key) -> Bool {
        inFlight[key]?.waiters.values.contains { $0.continuation != nil } == true
    }

    static func run(
        for key: Key,
        clientId: ObjectIdentifier,
        notifyRotation: @escaping @MainActor (String) -> Void,
        adoptRotation: @escaping @MainActor (String) -> Void,
        operation: @escaping @MainActor (_ recordRotation: (String) -> Void) async throws -> AuthToken
    ) async throws -> AuthToken {
        let id = UUID()
        let token = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let waiter = Waiter(
                    clientId: clientId, notifyRotation: notifyRotation,
                    adoptRotation: adoptRotation, continuation: continuation
                )
                if inFlight[key] != nil {
                    inFlight[key]?.waiters[id] = waiter
                    if let rotatedToken = inFlight[key]?.rotatedToken {
                        notify(waiter, of: rotatedToken, for: key)
                    }
                    return
                }

                inFlight[key] = Flight(waiters: [id: waiter])
                Task {
                    let result: Result<AuthToken, Error>
                    do {
                        let authToken = try await operation { rotatedToken in
                            inFlight[key]?.rotatedToken = rotatedToken
                            if let flight = inFlight[key] {
                                for waiter in flight.waiters.values {
                                    notify(waiter, of: rotatedToken, for: key)
                                }
                            }
                        }
                        inFlight[key]?.rotatedToken = authToken.refreshToken
                        result = .success(authToken)
                    } catch {
                        result = .failure(error)
                    }

                    // Update each client before waking callers, even when
                    // the CCS exchange failed. Until then, callers presenting
                    // the original credential share this entire operation.
                    if let flight = inFlight.removeValue(forKey: key) {
                        for waiter in flight.waiters.values {
                            if let rotatedToken = flight.rotatedToken { waiter.adoptRotation(rotatedToken) }
                            waiter.continuation?.resume(with: result)
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                let continuation = inFlight[key]?.waiters[id]?.continuation
                inFlight[key]?.waiters[id]?.continuation = nil
                continuation?.resume(throwing: CancellationError())
            }
        }
        try Task.checkCancellation()
        return token
    }

    private static func notify(_ waiter: Waiter, of token: String, for key: Key) {
        guard inFlight[key]?.notifiedClients.insert(waiter.clientId).inserted == true else { return }
        waiter.notifyRotation(token)
    }
}
