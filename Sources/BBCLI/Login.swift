//
//  Login.swift
//  BBCLI
//
//  Authentication: establishing this account's device identity, logging
//  in (reusing a saved session where one is still valid), and walking the
//  MFA challenge when the backend asks for one.
//
//  Split out of `main.swift` so that file stays under SwiftLint's
//  1000-line cap; these functions share no state with the interactive
//  loop beyond `CLIState`.
//

import BetterBlueKit
import Foundation

// MARK: - Login Flow

/// Returns a client carrying this account's stable device identity,
/// registering one on the first run.
///
/// The registration must go through `registerDevice()` rather than
/// minting a UUID locally, because the two European clients OVERRIDE it
/// to POST `notifications/register` and adopt the id the SERVER issues.
/// That id is then sent as `ccsp-device-id` on every request and inside
/// every command body, so a locally-invented one fails there (resCode
/// 4002, "Invalid deviceId"). Everywhere else the default implementation
/// just mints a UUID, which is what Kia US wants anyway.
@MainActor
private func establishedClient(
    state: CLIState,
    makeClient: (String?) -> any APIClientProtocol
) async throws -> any APIClientProtocol {
    let client = makeClient(state.session.deviceId)
    guard state.session.deviceId == nil else { return client }

    let registered = try await client.registerDevice() ?? UUID().uuidString.uppercased()
    state.updateSession { $0.deviceId = registered }
    print("Registered a device id for this account (saved to \(SessionStore.displayPath)).")

    // Rebuild with the id in hand. `KiaUSAAPIClient` copies
    // `configuration.deviceId` into a `let` in its initializer, so the
    // instance above is still carrying the throwaway UUID it made for
    // itself — registering afterwards updates the configuration but not
    // that stored copy, and the mismatch is what made every launch look
    // like a new device.
    return makeClient(registered)
}

/// Prints every HTTP exchange to the console, the CLI's whole reason for
/// existing. Bodies are pretty-printed and truncated at 4 000 characters
/// so a surround-view response doesn't bury the exchange that follows it.
func consoleHTTPLogSink() -> HTTPLogSink {
    { log in
        printSubheader("HTTP \(log.requestType.displayName)")
        print("[\(log.preciseTimestamp)] \(log.method) \(log.url)")
        print("Duration: \(log.formattedDuration)")
        if let status = log.responseStatus {
            print("Status: \(status)")
        }
        if let error = log.error {
            print("Error: \(error)")
        }
        if let apiError = log.apiError {
            print("API Error: \(apiError)")
        }
        if let body = log.requestBody {
            print("Request Body:\n\(prettyPrintJSON(body))")
        }
        if let body = log.responseBody {
            let formatted = prettyPrintJSON(body)
            let truncated = formatted.count > 4000
                ? String(formatted.prefix(4000)) + "\n... (truncated)"
                : formatted
            print("Response Body:\n\(truncated)")
        }
    }
}

@MainActor
func performLogin(state: CLIState) async throws {
    let brand = state.brand
    let region = state.region
    let username = state.username
    let password = state.password
    let refreshToken = state.refreshToken
    let pin = state.pin

    printHeader("Login")
    print("Brand: \(brand.displayName)")
    print("Region: \(region.rawValue)")
    print("Username: \(username)")
    if brand == .genesis {
        print("Genesis Canada beta: sign-in, vehicle discovery, vehicle status, and lock/unlock. Other operations remain unverified.")
    }
    if state.redactPII == false {
        print("⚠️  PII redaction disabled - sensitive data will be visible in logs")
    }
    print("")

    let logSink = consoleHTTPLogSink()

    // Reuse this account's saved device identity and tokens.
    let session = SessionStore.load(brand: brand, region: region, username: username)
    state.session = session

    func makeConfiguration(deviceId: String?) -> APIClientConfiguration {
        APIClientConfiguration(
            region: region,
            brand: brand,
            username: username,
            password: password,
            refreshToken: refreshToken.isEmpty ? nil : refreshToken,
            pin: pin,
            accountId: UUID(),
            logSink: logSink,
            rememberMeToken: session.rememberMeToken,
            redactPII: state.redactPII,
            deviceId: deviceId,
            onRememberMeTokenRotated: { rotated in
                // The backend rotates this periodically; persisting the new
                // value is what keeps the next launch from re-challenging.
                state.updateSession { $0.rememberMeToken = rotated }
            }
        )
    }

    func makeClient(deviceId: String?) -> any APIClientProtocol {
        do {
            return try createBetterBlueKitAPIClient(configuration: makeConfiguration(deviceId: deviceId))
        } catch let error as APIError {
            printError("\(error.errorType): \(error.message)")
            exit(1)
        } catch {
            printError(error.localizedDescription)
            exit(1)
        }
    }

    let client = try await establishedClient(state: state, makeClient: makeClient)
    state.client = client

    // A session that is still good means no login call at all — Kia's last
    // 23 hours, so most runs land inside the window.
    if let saved = state.session.authToken, saved.isValid {
        state.authToken = saved
        printSuccess("Reusing saved session (expires: \(saved.expiresAt))")
        print("Run `bbcli --forget` to discard it and log in fresh.")
        return
    }

    do {
        print("Attempting login...")
        // Deliberately NOT calling `registerDevice()`: the device id is
        // supplied through the configuration above and is already stable.
        let token = try await client.login()
        state.authToken = token
        state.updateSession { $0.authToken = token }
        printSuccess("Login successful!")
        print("Auth token received (expires: \(token.expiresAt))")
    } catch let error as APIError {
        if error.errorType == .requiresMFA, client.supportsMFA() {
            try await handleMFA(client: client, error: error, state: state)
        } else {
            throw error
        }
    }
}

@MainActor
func handleMFA(client: any APIClientProtocol, error: APIError, state: CLIState) async throws {
    printSubheader("MFA Required")

    guard let userInfo = error.userInfo else {
        throw APIError(message: "MFA required but no user info provided")
    }

    let xid = userInfo["xid"] ?? ""
    let otpKey = userInfo["otpKey"] ?? ""
    let email = userInfo["email"]
    let phone = userInfo["phone"]

    print("Available MFA methods:")
    if let email = email {
        print("  1. Email: \(email)")
    }
    if let phone = phone {
        print("  2. Phone: \(phone)")
    }

    let methodChoice = prompt("Select method (1 for email, 2 for phone): ")
    let method: MFAMethod = methodChoice == "2" ? .sms : .email

    print("Sending MFA code via \(method)...")
    try await client.sendMFACode(xid: xid, otpKey: otpKey, method: method)
    printSuccess("MFA code sent!")

    let rawCode = prompt("Enter verification code: ")
    // Filter to digits only - OTP codes are always numeric, and terminal escape sequences
    // can sometimes be captured by readLine()
    let code = rawCode.filter { $0.isNumber }

    if code.isEmpty {
        throw APIError(message: "No verification code entered")
    }

    if code != rawCode {
        print("Note: Cleaned input from '\\(rawCode)' to '\\(code)'")
    }

    print("Verifying MFA code...")
    let (rmToken, sid) = try await client.verifyMFACode(xid: xid, otpKey: otpKey, code: code)
    printSuccess("MFA verification successful!")

    // Save the remember-me token before completing login. This is the
    // credential that makes the NEXT run skip MFA, and it only ever
    // arrives here — the rotation callback fires on later logins, not on
    // this first issue.
    state.updateSession { $0.rememberMeToken = rmToken }

    print("Completing login...")
    let token = try await client.completeMFALogin(sid: sid, rmToken: rmToken)
    state.authToken = token
    state.updateSession { $0.authToken = token }
    printSuccess("Login completed!")
    print("Auth token received (expires: \(token.expiresAt))")
    print("Saved to \(SessionStore.displayPath). The CLI can reuse this session until it expires.")
}
