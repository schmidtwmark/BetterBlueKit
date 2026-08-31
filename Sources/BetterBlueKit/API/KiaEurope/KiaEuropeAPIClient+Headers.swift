//
//  KiaEuropeAPIClient+Headers.swift
//  BetterBlueKit
//
//  Header builders, the stamp signature helper, and the small chunk of
//  RSA / encoding plumbing the headless signin flow needs. Lifted into
//  a sibling extension so the main client file stays under SwiftLint's
//  250-line type-body cap.
//

import Foundation
import Security

extension KiaEuropeAPIClient {

    // MARK: - Header builders

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
            // Fresh stamp per request — the server validates the embedded
            // timestamp window (see `generateStamp()`).
            "Stamp": generateStamp()
        ]
    }

    func commandHeaders(authToken: AuthToken, ccs2: Bool = false) -> [String: String] {
        var result = authorizedHeaders(authToken: authToken, ccs2: ccs2)
        result["Authorization"] = "Bearer \(commandToken)"
        result["AuthorizationCCSP"] = "Bearer \(commandToken)"
        return result
    }

    /// CCSP `Stamp`: base64 of `authCfb ⊕ "<appId>:<unixSeconds>"`, where the
    /// XOR runs over the shorter of the two byte strings (the message here).
    ///
    /// Ports the canonical scheme from Home Assistant's
    /// `hyundai_kia_connect_api` (`_get_stamp`) / bluelinky. The previous
    /// HMAC-SHA256-over-ISO8601 form was accepted on read endpoints but
    /// rejected with HTTP 403 on the control endpoints, so remote actions
    /// failed across Europe.
    func generateStamp() -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let message = Array("\(Self.appId):\(timestamp)".utf8)
        guard let cfbData = Data(base64Encoded: Self.authCfb) else {
            return Data(message).base64EncodedString()
        }
        let cfb = Array(cfbData)
        let count = min(cfb.count, message.count)
        var xored = [UInt8]()
        xored.reserveCapacity(count)
        for index in 0 ..< count {
            xored.append(cfb[index] ^ message[index])
        }
        return Data(xored).base64EncodedString()
    }

    // The RSA / form-encoding helpers the signin flow uses moved to
    // APIClientBase+EuropeCrypto.swift — they're shared with the Hyundai
    // EU client since the OneApp/CCI login landed.
}
