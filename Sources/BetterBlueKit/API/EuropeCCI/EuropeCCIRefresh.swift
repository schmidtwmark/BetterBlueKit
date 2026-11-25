import Foundation

/// EU clients can be recreated independently for the same account. Keep a
/// refresh alive until it settles so cancellation cannot discard a rotation
/// or force another caller to submit the same refresh token.
@MainActor
enum EuropeCCIRefresh {
    struct Account: Hashable {
        let id: UUID
        let brand: Brand
    }

    private typealias Waiter = CheckedContinuation<AuthToken, Error>
    private static var inFlight: [Account: [UUID: Waiter]] = [:]

    static func hasWaiters(for account: Account) -> Bool {
        inFlight[account]?.isEmpty == false
    }

    static func run(
        for account: Account, operation: @escaping @MainActor () async throws -> AuthToken
    ) async throws -> AuthToken {
        let id = UUID()
        let token = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { (waiter: Waiter) in
                if inFlight[account] != nil {
                    inFlight[account]?[id] = waiter
                    return
                }

                inFlight[account] = [id: waiter]
                Task {
                    let result: Result<AuthToken, Error>
                    do {
                        result = .success(try await operation())
                    } catch {
                        result = .failure(error)
                    }
                    let waiters = inFlight.removeValue(forKey: account) ?? [:]
                    for waiter in waiters.values {
                        waiter.resume(with: result)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                inFlight[account]?.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
        try Task.checkCancellation()
        return token
    }
}
