//
//  HyundaiEuropeAPIClient+Headers.swift
//  BetterBlueKit
//
//  Header builders + the stamp signature helper for the Hyundai
//  Europe client. Lifted into a sibling extension so the main client
//  file stays under SwiftLint's 250-line type-body cap — these
//  functions are largely literal-table plumbing and have nothing to
//  do with the login / fetch / command state machine that lives in
//  the main file.
//

import CryptoKit
import Foundation

extension HyundaiEuropeAPIClient {

    func authorizedHeaders(authToken: AuthToken, ccs2: Bool = false) -> [String: String] {
        [
            "Authorization": "Bearer \(authToken.accessToken)",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "okhttp/3.14.9",
            "ccsp-service-id": Self.clientId,
            "ccsp-application-id": Self.appId,
            "ccsp-device-id": configuration.deviceId ?? "",
            "Ccuccs2protocolsupport": ccs2 ? "1" : "0",
            "Host": apiHost,
            "Connection": "Keep-Alive",
            "Accept-Encoding": "gzip",
            "Stamp": stamp
        ]
    }

    func loginHeaders() -> [String: String] {
        ["Content-Type": "application/json",
         "Accept-Encoding": "gzip",
         "User-Agent": "okhttp/3.14.9"
        ]
    }

    func commandHeaders(authToken: AuthToken, ccs2: Bool = false) -> [String: String] {
        var result = authorizedHeaders(authToken: authToken, ccs2: ccs2)
        result["Authorization"] = "Bearer \(commandToken)"
        result["AuthorizationCCSP"] = "Bearer \(commandToken)"
        return result
    }

    /// HMAC-SHA256 of `<appId>:<ISO8601 timestamp>` keyed by the
    /// first 32 bytes of the base64-decoded `authCfb` shared secret,
    /// base64-encoded. Sent as the `Stamp` header on every request
    /// and as the `pushRegId` field during device registration.
    func generateStamp() -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let message = "\(Self.appId):\(timestamp)"
        guard let cfbData = Data(base64Encoded: Self.authCfb) else { return message }
        let key = SymmetricKey(data: cfbData.prefix(32))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(signature).base64EncodedString()
    }
}
