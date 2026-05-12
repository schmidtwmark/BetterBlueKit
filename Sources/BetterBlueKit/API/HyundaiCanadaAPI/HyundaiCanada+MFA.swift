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
        // The server has been seen returning the email-from-loginId in
        // `userAccount` if `emailList` is empty — fall back to it so
        // the OTP flow has *something* to identify the user with.
        let serverUserAccount = result["userAccount"] as? String
        let phone = result["userPhone"] as? String

        let email = emailList.first ?? serverUserAccount
        // Stash for the subsequent send / verify / complete calls.
        mfaUserInfoUuid = userInfoUuid
        mfaEmail = email ?? username
        mfaPhone = (phone?.isEmpty ?? true) ? nil : phone
        mfaOtpKey = nil
        mfaCompletedAuthToken = nil

        throw APIError.requiresMFA(
            xid: userInfoUuid,
            otpKey: nil,
            hasEmail: email != nil,
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
        let email = mfaEmail ?? username

        let validationKey = try await validateOTP(code: code, otpKey: storedOtpKey, email: email)
        let auth = try await genMFAToken(validationKey: validationKey, email: email)

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
    /// an `otpValidationKey` we can hand to `genmfatkn`.
    private func validateOTP(code: String, otpKey: String, email: String) async throws -> String {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/mfa/validateotp",
            method: .POST,
            headers: mfaHeaders(),
            body: [
                "otpNo": code,
                "userAccount": email,
                "otpKey": otpKey,
                "mfaApiCode": "0107"
            ],
            requestType: .verifyMFA
        )

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
    /// session token.
    private func genMFAToken(validationKey: String, email: String) async throws -> AuthToken {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/mfa/genmfatkn",
            method: .POST,
            headers: mfaHeaders(),
            body: [
                "userAccount": email,
                "otpEmail": email,
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
