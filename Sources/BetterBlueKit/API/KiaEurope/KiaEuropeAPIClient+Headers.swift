//
//  KiaEuropeAPIClient+Headers.swift
//  BetterBlueKit
//
//  Header builders, the stamp signature helper, and the small chunk of
//  RSA / encoding plumbing the headless signin flow needs. Lifted into
//  a sibling extension so the main client file stays under SwiftLint's
//  250-line type-body cap.
//

import CryptoKit
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
            // Fresh HMAC per request — Stamp is an `<appId>:<ISO8601>` signature
            // and the server appears to validate the timestamp window.
            "Stamp": generateStamp()
        ]
    }

    func commandHeaders(authToken: AuthToken, ccs2: Bool = false) -> [String: String] {
        var result = authorizedHeaders(authToken: authToken, ccs2: ccs2)
        result["Authorization"] = "Bearer \(commandToken)"
        result["AuthorizationCCSP"] = "Bearer \(commandToken)"
        return result
    }

    /// HMAC-SHA256 of `<appId>:<ISO8601 timestamp>` keyed by the first
    /// 32 bytes of the base64-decoded `authCfb`, base64-encoded.
    func generateStamp() -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let message = "\(Self.appId):\(timestamp)"
        guard let cfbData = Data(base64Encoded: Self.authCfb) else { return message }
        let key = SymmetricKey(data: cfbData.prefix(32))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(signature).base64EncodedString()
    }

    // MARK: - RSA / encoding helpers (used by signin)

    /// PKCS#1 v1.5 encrypt `password` with the RSA public key described by
    /// the JWK `(n, e)` pair, returning a lowercase hex string.
    func rsaEncryptPKCS1(password: String, jwkN: String, jwkE: String) throws -> String {
        guard let nData = Self.base64urlDecode(jwkN),
              let eData = Self.base64urlDecode(jwkE) else {
            throw APIError(message: "Invalid base64url in JWK", apiName: apiName)
        }
        let derKey = Self.rsaPublicKeyDER(modulus: nData, exponent: eData)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: nData.count * 8
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(derKey as CFData, attributes as CFDictionary, &error) else {
            throw APIError(
                message: "Failed to construct RSA key: " +
                    "\(error?.takeRetainedValue().localizedDescription ?? "unknown")",
                apiName: apiName
            )
        }
        let plaintext = Data(password.utf8)
        guard let encrypted = SecKeyCreateEncryptedData(
            secKey, .rsaEncryptionPKCS1, plaintext as CFData, &error
        ) else {
            throw APIError(
                message: "RSA encryption failed: " +
                    "\(error?.takeRetainedValue().localizedDescription ?? "unknown")",
                apiName: apiName
            )
        }
        return (encrypted as Data).map { String(format: "%02x", $0) }.joined()
    }

    static func base64urlDecode(_ input: String) -> Data? {
        var padded = input.replacingOccurrences(of: "-", with: "+")
                          .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - padded.count % 4) % 4
        if pad > 0 { padded.append(String(repeating: "=", count: pad)) }
        return Data(base64Encoded: padded)
    }

    /// Build a PKCS#1 RSAPublicKey DER blob (`SEQUENCE { INTEGER n, INTEGER e }`),
    /// which is what `SecKeyCreateWithData` expects for a raw RSA public key.
    static func rsaPublicKeyDER(modulus: Data, exponent: Data) -> Data {
        let nDER = derInteger(modulus)
        let eDER = derInteger(exponent)
        return derTLV(tag: 0x30, value: nDER + eDER)
    }

    private static func derInteger(_ bytes: Data) -> Data {
        // Prepend 0x00 if the high bit is set so the value is interpreted
        // as a positive (unsigned) integer per X.690 DER.
        let value: Data = (bytes.first ?? 0) >= 0x80 ? Data([0x00]) + bytes : bytes
        return derTLV(tag: 0x02, value: value)
    }

    private static func derTLV(tag: UInt8, value: Data) -> Data {
        var out = Data([tag])
        let len = value.count
        if len < 0x80 {
            out.append(UInt8(len))
        } else if len < 0x100 {
            out.append(0x81)
            out.append(UInt8(len))
        } else {
            out.append(0x82)
            out.append(UInt8((len >> 8) & 0xff))
            out.append(UInt8(len & 0xff))
        }
        return out + value
    }

    /// RFC 3986 form-encode a list of key/value pairs (order preserved).
    static func formEncode(_ fields: [(String, String)]) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return fields.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }
}
