//
//  APIClient+MFA.swift
//  BetterBlueKit
//
//  Created by Mark Schmidt on 1/30/26.
//

// MARK: - MFA Support
extension APIClient {

    public func supportsMFA() -> Bool {
        endpointProvider.supportsMFA()
    }

    public func sendMFACode(otpKey: String, xid: String, notifyType: String = "SMS") async throws {
        guard endpointProvider.supportsMFA() else {
            throw APIError(message: "MFA not supported for this API", apiName: "APIClient")
        }

        BBLogger.info(.mfa, "sendMFACode called - otpKey: \(otpKey), xid: \(xid), type: \(notifyType)")
        let endpoint = endpointProvider.sendOTPEndpoint(otpKey: otpKey, xid: xid, notifyType: notifyType)
        let request = try createRequest(from: endpoint)
        let (data, _) = try await performLoggedRequest(request, requestType: .sendMFA)
        try endpointProvider.parseCommandResponse(data)
    }

    public func verifyMFACode(
        otpKey: String, xid: String, otp: String
    ) async throws -> (rememberMeToken: String, sid: String) {
        guard endpointProvider.supportsMFA() else {
            throw APIError(message: "MFA not supported for this API", apiName: "APIClient")
        }

        BBLogger.info(.mfa, "verifyMFACode called - otpKey: \(otpKey), xid: \(xid), otp: \(otp)")
        let endpoint = endpointProvider.verifyOTPEndpoint(otpKey: otpKey, xid: xid, otp: otp)
        let request = try createRequest(from: endpoint)
        let (data, response) = try await performLoggedRequest(request, requestType: .verifyMFA)

        let headers: [String: String] = response.allHeaderFields.reduce(into: [:]) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }

        return try endpointProvider.parseVerifyOTPResponse(data, headers: headers)
    }

    public func completeMFALogin(sid: String, rmToken: String) async throws -> AuthToken {
        guard endpointProvider.supportsMFA() else {
            throw APIError(message: "MFA not supported for this API", apiName: "APIClient")
        }

        BBLogger.info(.mfa, "completeMFALogin called with sid: \(sid), rmToken: \(rmToken.prefix(10))...")
        let endpoint = endpointProvider.loginEndpoint(sid: sid, rmToken: rmToken)
        let request = try createRequest(from: endpoint)
        let (data, response) = try await performLoggedRequest(request, requestType: .login)

        let headers: [String: String] = response.allHeaderFields.reduce(into: [:]) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }

        return try endpointProvider.parseLoginResponse(data, headers: headers)
    }

}
