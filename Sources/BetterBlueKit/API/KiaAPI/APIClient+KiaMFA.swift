//
//  APIClient+KiaMFA.swift
//  BetterBlueKit
//
//  Created by Mark Schmidt on 12/26/25.
//

import Foundation

extension APIClient where Provider == KiaAPIEndpointProvider {
    public func sendOTP(otpKey: String, xid: String, notifyType: String = "SMS") async throws {
        print("🛠️ [KiaMFA] sendOTP called - otpKey: \(otpKey), xid: \(xid), type: \(notifyType)")
        let endpoint = endpointProvider.sendOTPEndpoint(otpKey: otpKey, xid: xid, notifyType: notifyType)
        let request = try createRequest(from: endpoint)
        let (data, _) = try await performLoggedRequest(request, requestType: .sendMFA)
        // Check for errors in body
        try endpointProvider.parseCommandResponse(data)
    }

    public func verifyOTP(otpKey: String, xid: String, otp: String) async throws -> (rememberMeToken: String, sid: String) {
        print("🛠️ [KiaMFA] verifyOTP called - otpKey: \(otpKey), xid: \(xid), otp: \(otp)")
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
}
