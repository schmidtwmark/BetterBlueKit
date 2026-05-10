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
            // The Python reference echoes whatever phone selverifmeth
            // returned back here; we don't have it on hand without
            // refetching, but the server only requires it for SMS
            // delivery. Fall back to empty string and let the API
            // surface a clearer error if SMS isn't available.
            body["userPhone"] = ""
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

        var mfaHeaders = headers()
        if let cookie = cloudFlareCookie {
            mfaHeaders["Cookie"] = cookie
        }

        // Step 4: validate the code the user typed.
        let (validateData, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/mfa/validateotp",
            method: .POST,
            headers: mfaHeaders,
            body: [
                "otpNo": code,
                "userAccount": email,
                "otpKey": storedOtpKey,
                "mfaApiCode": "0107"
            ],
            requestType: .verifyMFA
        )

        let validateJSON = try parseCanadaResponse(validateData, context: "mfa/validateotp")
        guard let validateResult = validateJSON["result"] as? [String: Any] else {
            throw APIError.logError("Invalid Canada validateotp response", apiName: apiName)
        }
        let verified = validateResult["verifiedOtp"] as? Bool ?? false
        guard verified, let validationKey = validateResult["otpValidationKey"] as? String else {
            throw APIError.invalidCredentials(
                "OTP verification failed",
                apiName: apiName
            )
        }

        // Step 5: trade the validation key for a real session.
        let (tokenData, _, _) = try await performJSONRequest(
            url: "\(apiBaseURL)/mfa/genmfatkn",
            method: .POST,
            headers: mfaHeaders,
            body: [
                "userAccount": email,
                "otpEmail": email,
                "mfaApiCode": "0107",
                "otpValidationKey": validationKey,
                "mfaYn": "Y"
            ],
            requestType: .verifyMFA
        )

        let tokenJSON = try parseCanadaResponse(tokenData, context: "mfa/genmfatkn")
        guard let tokenResult = tokenJSON["result"] as? [String: Any],
              let token = tokenResult["token"] as? [String: Any],
              let accessToken = token["accessToken"] as? String else {
            throw APIError.logError("Invalid Canada genmfatkn response", apiName: apiName)
        }
        let expiresIn: Int = extractNumber(from: token["expireIn"]) ?? 3600
        let refreshToken = token["refreshToken"] as? String ?? ""

        let auth = AuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
        // Stash so completeMFALogin (called immediately after by the
        // existing protocol flow) can return the real token.
        mfaCompletedAuthToken = auth
        // Drain the otpKey now that it's been consumed; future MFA
        // attempts must restart from sendMFACode.
        mfaOtpKey = nil

        // Hyundai Canada has no separate "remember me" channel — the
        // refresh token *is* the long-lived credential. Surface it
        // here so the host persists it.
        return (rememberMeToken: refreshToken, sid: accessToken)
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
