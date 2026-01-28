//
//  APIClient+KiaMFA.swift
//  BetterBlueKit
//
//  Created by Mark Schmidt on 12/26/25.
//

import Foundation

extension APIClient where Provider == KiaAPIEndpointProvider {
    public func sendOTP(otpKey: String, xid: String, notifyType: String = "SMS") async throws {
        BBLogger.info(.mfa, "sendOTP called - otpKey: \(otpKey), xid: \(xid), type: \(notifyType)")
        let endpoint = endpointProvider.sendOTPEndpoint(otpKey: otpKey, xid: xid, notifyType: notifyType)
        let request = try createRequest(from: endpoint)
        let (data, _) = try await performLoggedRequest(request, requestType: .sendMFA)
        // Check for errors in body
        try endpointProvider.parseCommandResponse(data)
    }

    public func verifyOTP(
        otpKey: String, xid: String, otp: String) async throws -> (rememberMeToken: String, sid: String) {
        BBLogger.info(.mfa, "verifyOTP called - otpKey: \(otpKey), xid: \(xid), otp: \(otp)")
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

    /// Complete authentication after MFA verification
    /// Call this after verifyOTP returns rmToken and sid to get the final auth token
    public func completeLoginWithMFA(sid: String, rmToken: String) async throws -> AuthToken {
        BBLogger.info(.mfa, "completeLoginWithMFA called with sid: \(sid), rmToken: \(rmToken.prefix(10))...")
        // Call authUser again with rmtoken and sid headers
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
