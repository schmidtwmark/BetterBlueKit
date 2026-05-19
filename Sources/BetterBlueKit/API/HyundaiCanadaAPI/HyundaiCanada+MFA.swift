//
//  HyundaiCanada+MFA.swift
//  BetterBlueKit
//
//  Hyundai Canada MFA / OTP flow.
//
//  Hyundai Canada gates new-device logins behind a one-time code
//  delivered by email or SMS (errorCode 7110). The flow:
//
//    1. POST /v2/login                        → 7110 ("OTP Required")
//    2. POST /mfa/selverifmeth                → userInfoUuid, emailList, userPhone
//    3. POST /mfa/sendotp     {METHOD}        → otpKey
//    4. POST /mfa/validateotp {otpNo, otpKey} → otpValidationKey
//    5. POST /mfa/genmfatkn   {validationKey} → token (accessToken, refreshToken)
//
//  We map this onto the existing `APIClientProtocol` MFA contract:
//
//    * `login()` performs steps 1–2 and throws `requiresMFA` with the
//      data harvested from `selverifmeth` (steps 3–5 happen below).
//    * `sendMFACode` performs step 3.
//    * `verifyMFACode` performs steps 4 and 5 in sequence and stashes
//      the resulting auth token; the placeholder return values keep
//      the existing UI flow happy.
//    * `completeMFALogin` returns the stashed token from step 5.
//

import Foundation

extension HyundaiCanadaAPIClient {

    public func supportsMFA() -> Bool {
        true
    }

    // MARK: - Login-time challenge detection

    /// Detects the `errorCode == "7110"` (OTP Required) response shape
    /// without invoking the throwing parser. The server marks this as
    /// a *failure* (`responseCode == true` in the modern bool form, `1`
    /// in the older int form) carrying an `error.errorCode` of "7110".
    func isOTPRequiredResponse(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = json["responseHeader"] as? [String: Any],
              !isCanadaResponseSuccess(header["responseCode"]),
              let error = json["error"] as? [String: Any] else {
            return false
        }
        // The Python reference compares as a string ("7110"). The API
        // has been seen sending it as both a string and a number, so
        // accept either form.
        if let codeString = error["errorCode"] as? String, codeString == "7110" { return true }
        if let codeInt: Int = extractNumber(from: error["errorCode"]), codeInt == 7110 { return true }
        return false
    }

    /// Calls `mfa/selverifmeth` to learn which contact methods the
    /// account has on file, stashes the userInfoUuid + email for later
    /// `sendotp` / `genmfatkn` calls, then throws `requiresMFA` so the
    /// existing iOS MFA UI can pick up the challenge.
    func beginMFAFlow(cookie: String) async throws {
        BBLogger.info(.mfa, "HyundaiCanada: OTP required (errorCode 7110), starting MFA flow")

        var loginMfaHeaders = headers()
        loginMfaHeaders["Cookie"] = cookie

        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/mfa/selverifmeth",
            method: .POST,
            headers: loginMfaHeaders,
            body: [
                "mfaApiCode": "0107",
                "userAccount": username
            ],
            requestType: .sendMFA
        )

        let json = try parseCanadaResponse(data, context: "mfa/selverifmeth")
        guard let result = json["result"] as? [String: Any] else {
            throw APIError.logError("Invalid Canada selverifmeth response", apiName: apiName)
        }

        let userInfoUuid = result["userInfoUuid"] as? String ?? ""
        let emailList = result["emailList"] as? [String] ?? []
        let phone = result["userPhone"] as? String

        // Match the Python reference (`hyundai_kia_connect_api`): when
        // `emailList` is empty fall back to the original `username`,
        // NOT the server-normalised `userAccount` field. The server
        // upper-cases its echo (e.g. "gingmar@gmail.com" comes back
        // as "GINGXXX@GMAIL.COM"), and downstream `validateotp`
        // hashes `userAccount` as part of the OTP check — sending the
        // upper-cased form yields errorCode 7999 even with a correct
        // code.
        let email = emailList.first ?? username
        mfaUserInfoUuid = userInfoUuid
        mfaEmail = email
        mfaPhone = (phone?.isEmpty ?? true) ? nil : phone
        mfaOtpKey = nil
        mfaCompletedAuthToken = nil

        throw APIError.requiresMFA(
            xid: userInfoUuid,
            otpKey: nil,
            // Email delivery is always available since we fall back
            // to `username` (the user's email-shaped login) when
            // `selverifmeth` doesn't surface a separate email list.
            hasEmail: true,
            hasPhone: !(phone?.isEmpty ?? true),
            email: email,
            phone: (phone?.isEmpty ?? true) ? nil : phone,
            apiName: apiName
        )
    }

    public func sendMFACode(xid: String, otpKey _: String, method: MFAMethod) async throws {
        // We deliberately ignore the `otpKey` param: Hyundai Canada
        // doesn't issue an otpKey until AFTER `sendotp`. Use the
        // `userInfoUuid` we stashed during login() (passed back to us
        // here as `xid`) instead.
        guard !xid.isEmpty else {
            throw APIError.logError("MFA flow not initialized", apiName: apiName)
        }
        let email = mfaEmail ?? username

        var body: [String: Any] = [
            "mfaApiCode": "0107",
            "userInfoUuid": xid,
            "userAccount": email
        ]
        switch method {
        case .email:
            body["otpMethod"] = "E"
            body["userPhone"] = ""
        case .sms:
            body["otpMethod"] = "S"
            // Echo back whatever phone digits selverifmeth returned —
            // the server uses this to locate the SMS destination.
            body["userPhone"] = mfaPhone ?? ""
        }

        var mfaHeaders = headers()
        if let cookie = cloudFlareCookie {
            mfaHeaders["Cookie"] = cookie
        }

        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/mfa/sendotp",
            method: .POST,
            headers: mfaHeaders,
            body: body,
            requestType: .sendMFA
        )

        let json = try parseCanadaResponse(data, context: "mfa/sendotp")
        guard let result = json["result"] as? [String: Any],
              let otpKey = result["otpKey"] as? String else {
            throw APIError.logError("Invalid Canada sendotp response", apiName: apiName)
        }
        mfaOtpKey = otpKey
    }

    public func verifyMFACode(
        xid: String,
        otpKey _: String,
        code: String
    ) async throws -> (rememberMeToken: String, sid: String) {
        guard !xid.isEmpty else {
            throw APIError.logError("MFA flow not initialized", apiName: apiName)
        }
        guard let storedOtpKey = mfaOtpKey else {
            throw APIError.logError(
                "MFA verify called before sendMFACode established otpKey",
                apiName: apiName
            )
        }
        // `validateotp` and `genmfatkn` need the *original* user-typed
        // username for their `userAccount` field — the Python
        // reference uses `username` directly there, and the server
        // returns errorCode 7999 if we send the server-normalised
        // (often upper-cased) form back. `mfaEmail` is only used as
        // the `otpEmail` payload in `genmfatkn`.
        let validationKey = try await validateOTP(code: code, otpKey: storedOtpKey)
        let auth = try await genMFAToken(validationKey: validationKey, otpEmail: mfaEmail ?? username)

        // Stash so completeMFALogin (called immediately after by the
        // existing protocol flow) can return the real token.
        mfaCompletedAuthToken = auth
        // Drain the otpKey now that it's been consumed; future MFA
        // attempts must restart from sendMFACode.
        mfaOtpKey = nil

        // Hyundai Canada has no separate "remember me" channel — the
        // refresh token *is* the long-lived credential. Surface it
        // here so the host persists it.
        return (rememberMeToken: auth.refreshToken, sid: auth.accessToken)
    }

    /// Step 4 of the OTP flow — exchange the code the user typed for
    /// an `otpValidationKey` we can hand to `genmfatkn`. `userAccount`
    /// is the *original* username the user logged in with — the
    /// server-normalised form returned by `selverifmeth` is rejected
    /// here with errorCode 7999 even when the OTP is correct.
    private func validateOTP(code: String, otpKey: String) async throws -> String {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/mfa/validateotp",
            method: .POST,
            headers: mfaHeaders(),
            body: [
                "otpNo": code,
                "userAccount": username,
                "otpKey": otpKey,
                "mfaApiCode": "0107"
            ],
            requestType: .verifyMFA
        )

        // 7999 = "We apologize, but your request could not be
        // processed." Hyundai's catch-all when the OTP is wrong /
        // expired or any other validation step trips. Surface it as
        // an invalid-credentials error so the iOS UI shows "Try
        // again or request a new code" instead of the cryptic raw
        // server text.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let header = json["responseHeader"] as? [String: Any],
           !isCanadaResponseSuccess(header["responseCode"]),
           let error = json["error"] as? [String: Any],
           (error["errorCode"] as? String) == "7999" {
            throw APIError.invalidCredentials(
                "Verification rejected. Try again or request a new code.",
                apiName: apiName
            )
        }

        let json = try parseCanadaResponse(data, context: "mfa/validateotp")
        guard let result = json["result"] as? [String: Any] else {
            throw APIError.logError("Invalid Canada validateotp response", apiName: apiName)
        }
        let verified = result["verifiedOtp"] as? Bool ?? false
        guard verified, let validationKey = result["otpValidationKey"] as? String else {
            throw APIError.invalidCredentials("OTP verification failed", apiName: apiName)
        }
        return validationKey
    }

    /// Step 5 of the OTP flow — trade the validation key for a real
    /// session token. `userAccount` uses the *original* username (per
    /// Python ref) while `otpEmail` is the email-form returned by
    /// `selverifmeth`.
    private func genMFAToken(validationKey: String, otpEmail: String) async throws -> AuthToken {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/mfa/genmfatkn",
            method: .POST,
            headers: mfaHeaders(),
            body: [
                "userAccount": username,
                "otpEmail": otpEmail,
                "mfaApiCode": "0107",
                "otpValidationKey": validationKey,
                "mfaYn": "Y"
            ],
            requestType: .verifyMFA
        )

        let json = try parseCanadaResponse(data, context: "mfa/genmfatkn")
        guard let result = json["result"] as? [String: Any],
              let token = result["token"] as? [String: Any],
              let accessToken = token["accessToken"] as? String else {
            throw APIError.logError("Invalid Canada genmfatkn response", apiName: apiName)
        }
        let expiresIn: Int = extractNumber(from: token["expireIn"]) ?? 3600
        let refreshToken = token["refreshToken"] as? String ?? ""

        return AuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    /// Default header set for any MFA endpoint — mirrors the standard
    /// `headers()` helper plus the cached cookie when we have one.
    private func mfaHeaders() -> [String: String] {
        var result = headers()
        if let cookie = cloudFlareCookie {
            result["Cookie"] = cookie
        }
        return result
    }

    public func completeMFALogin(sid _: String, rmToken _: String) async throws -> AuthToken {
        guard let token = mfaCompletedAuthToken else {
            throw APIError.logError(
                "completeMFALogin called before successful verifyMFACode",
                apiName: apiName
            )
        }
        // One-shot: clear stashed state so a subsequent MFA flow has to
        // re-run from the top.
        mfaCompletedAuthToken = nil
        mfaUserInfoUuid = nil
        return token
    }
}
