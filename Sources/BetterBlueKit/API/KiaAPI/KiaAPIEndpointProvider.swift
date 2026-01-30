//
//  KiaAPIEndpointProvider.swift
//  BetterBlueKit
//
//  Kia API Endpoint Provider Base Class
//

import CryptoKit
import Foundation

// MARK: - Kia API Endpoint Provider Base

/// Base class for Kia API endpoint providers.
/// Subclasses should override endpoint methods for region-specific URLs.
/// Parsing methods are shared across all regions.
@MainActor
open class KiaAPIEndpointProviderBase: APIEndpointProvider {
    public let username: String
    public let password: String
    public let pin: String
    public let accountId: UUID
    public let region: Region
    public let rememberMeToken: String?

    public init(configuration: APIClientConfiguration) {
        username = configuration.username
        password = configuration.password
        pin = configuration.pin
        accountId = configuration.accountId
        region = configuration.region
        rememberMeToken = configuration.rememberMeToken
    }

    // MARK: - Common Constants (can be overridden)

    open var baseURL: String {
        region.apiBaseURL(for: .kia)
    }

    open var apiURL: String {
        "\(baseURL)/apigw/v1/"
    }

    // Device ID is a simple uppercase UUID (matches Python: str(uuid.uuid4()).upper())
    public let deviceId: String = UUID().uuidString.uppercased()

    // Client UUID is a UUID5 hash of device_id using DNS namespace
    // (matches Python: str(uuid.uuid5(uuid.NAMESPACE_DNS, self.device_id)))
    public var clientUUID: String {
        // UUID5 uses SHA-1 hash of namespace + name
        // DNS namespace UUID is 6ba7b810-9dad-11d1-80b4-00c04fd430c8
        let namespaceUUID = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        return generateUUID5(namespace: namespaceUUID, name: deviceId).uuidString.lowercased()
    }

    /// Generate UUID5 (SHA-1 based) from namespace and name
    private func generateUUID5(namespace: UUID, name: String) -> UUID {
        // Get namespace bytes in big-endian order
        let nsUUID = namespace.uuid
        var data = Data([
            nsUUID.0, nsUUID.1, nsUUID.2, nsUUID.3,
            nsUUID.4, nsUUID.5, nsUUID.6, nsUUID.7,
            nsUUID.8, nsUUID.9, nsUUID.10, nsUUID.11,
            nsUUID.12, nsUUID.13, nsUUID.14, nsUUID.15
        ])

        // Append name bytes
        data.append(contentsOf: name.utf8)

        // Compute SHA-1 hash using CryptoKit
        let digest = Insecure.SHA1.hash(data: data)
        var hash = Array(digest)

        // Set version (5) and variant bits
        hash[6] = (hash[6] & 0x0F) | 0x50  // Version 5
        hash[8] = (hash[8] & 0x3F) | 0x80  // Variant

        // Create UUID from first 16 bytes
        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
    }

    // MARK: - Common Header Helpers

    open func apiHeaders() -> [String: String] {
        // Offset as integer (no + sign for positive), matches Python: str(int(offset))
        let offset = TimeZone.current.secondsFromGMT() / 3600

        // Extract host from baseURL (remove https:// prefix)
        let hostName = baseURL.replacingOccurrences(of: "https://", with: "")

        // Format date like: "Fri, 23 Jan 2026 2:37:26 GMT"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "GMT")
        let dateString = dateFormatter.string(from: Date())

        // Headers match Python implementation
        return [
            "content-type": "application/json;charset=utf-8",
            "accept": "application/json",
            "accept-encoding": "gzip, deflate, br",
            "accept-language": "en-US,en;q=0.9",
            "accept-charset": "utf-8",
            "apptype": "L",
            "appversion": "7.22.0",
            "clientid": "SPACL716-APL",
            "clientuuid": clientUUID,
            "from": "SPA",
            "host": hostName,
            "language": "0",
            "offset": String(offset),
            "ostype": "iOS",
            "osversion": "15.8.5",
            "phonebrand": "iPhone",
            "secretkey": "sydnat-9kykci-Kuhtep-h5nK",
            "to": "APIGW",
            "tokentype": "A",
            "user-agent": "KIAPrimo_iOS/37 CFNetwork/1335.0.3.4 Darwin/21.6.0",
            "date": dateString,
            "deviceid": deviceId
        ]
    }

    open func authedApiHeaders(authToken: AuthToken, vehicleKey: String?) -> [String: String] {
        var headers = apiHeaders()
        headers["sid"] = authToken.accessToken
        if let key = vehicleKey {
            headers["vinkey"] = key
        }
        return headers
    }

    // MARK: - Error Handling

    public func checkForKiaSpecificErrors(data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any],
              let errorCode: Int = extractNumber(from: status["errorCode"]),
              errorCode != 0 else { return }

        let errorMessage = status["errorMessage"] as? String ?? "Unknown Kia API error"
        let statusCode: Int = extractNumber(from: status["statusCode"]) ?? -1
        let errorType: Int = extractNumber(from: status["errorType"]) ?? -1
        let messageLower = errorMessage.lowercased()

        // Check specific error patterns
        if statusCode == 1, errorType == 1, errorCode == 1,
           messageLower.contains("valid email") || messageLower.contains("invalid") ||
           messageLower.contains("credential") {
            throw APIError.invalidCredentials("Invalid username or password", apiName: "KiaAPI")
        }

        if errorCode == 1005 || errorCode == 1103 {
            throw APIError.invalidVehicleSession(errorMessage, apiName: "KiaAPI")
        }

        if errorCode == 1003,
           messageLower.contains("session key") || messageLower.contains("invalid") ||
           messageLower.contains("expired") {
            throw APIError.invalidCredentials("Session Key is either invalid or expired", apiName: "KiaAPI")
        }

        if errorCode == 9789 {
            throw APIError.kiaInvalidRequest(
                "Kia API is currently unsupported. " +
                "See https://github.com/schmidtwmark/BetterBlueKit/issues/7 for updates",
                apiName: "KiaAPI"
            )
        }

        if errorCode == 429 {
            throw APIError.serverError("Rate limited", apiName: "KiaAPI")
        }

        if errorCode == 503 {
            throw APIError.serverError("Service unavailable", apiName: "KiaAPI")
        }
    }

    // MARK: - APIEndpointProvider Protocol (Overridable Endpoints)

    /// Kia supports MFA (Multi-Factor Authentication)
    open func supportsMFA() -> Bool {
        true
    }

    /// Subclasses must override to provide region-specific login endpoint
    open func loginEndpoint() -> APIEndpoint {
        fatalError("Subclasses must override loginEndpoint()")
    }

    /// Login endpoint with optional MFA parameters
    open func loginEndpoint(sid: String?, rmToken: String?) -> APIEndpoint {
        fatalError("Subclasses must override loginEndpoint(sid:rmToken:)")
    }

    /// OTP send endpoint for MFA
    open func sendOTPEndpoint(otpKey: String, xid: String, notifyType: String) -> APIEndpoint {
        fatalError("Subclasses must override sendOTPEndpoint(otpKey:xid:notifyType:)")
    }

    /// OTP verify endpoint for MFA
    open func verifyOTPEndpoint(otpKey: String, xid: String, otp: String) -> APIEndpoint {
        fatalError("Subclasses must override verifyOTPEndpoint(otpKey:xid:otp:)")
    }

    /// Subclasses must override to provide region-specific vehicles endpoint
    open func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint {
        fatalError("Subclasses must override fetchVehiclesEndpoint(authToken:)")
    }

    /// Subclasses must override to provide region-specific status endpoint
    open func fetchVehicleStatusEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
        fatalError("Subclasses must override fetchVehicleStatusEndpoint(for:authToken:)")
    }

    /// Subclasses must override to provide region-specific command endpoint
    open func sendCommandEndpoint(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken
    ) -> APIEndpoint {
        fatalError("Subclasses must override sendCommandEndpoint(for:command:authToken:)")
    }

    /// Override to provide region-specific command body if needed
    open func getBodyForCommand(command: VehicleCommand, vehicle: Vehicle) -> [String: Any] {
        var body: [String: Any] = [:]

        switch command {
        case .startClimate(let options):
            let heatingAccessory: [String: Int] = [
                "steeringWheel": options.steeringWheel > 0 ? 1 : 0,
                "rearWindow": options.rearDefrostEnabled ? 1 : 0,
                "sideMirror": options.rearDefrostEnabled ? 1 : 0
            ]

            var remoteClimate: [String: Any] = [
                "airCtrl": options.climate,
                "defrost": options.defrost,
                "airTemp": [
                    "value": String(Int(options.temperature.value)),
                    "unit": options.temperature.units.integer()
                ],
                "ignitionOnDuration": [
                    "unit": 4,
                    "value": options.duration
                ],
                "heatingAccessory": heatingAccessory
            ]

            // Seat configuration
            let seats: [String: Int] = [
                "driverSeat": convertSeatSetting(options.frontLeftSeat, options.frontLeftVentilationEnabled),
                "passengerSeat": convertSeatSetting(options.frontRightSeat, options.frontRightVentilationEnabled),
                "rearLeftSeat": convertSeatSetting(options.rearLeftSeat, options.rearLeftVentilationEnabled),
                "rearRightSeat": convertSeatSetting(options.rearRightSeat, options.rearRightVentilationEnabled)
            ]

            remoteClimate["heatVentSeat"] = seats

            body = ["remoteClimate": remoteClimate]
        case .startCharge:
            body = ["chargeRatio": 100]
        case .setTargetSOC(let acLevel, let dcLevel):
            body["targetSOClist"] = [
                ["targetSOClevel": acLevel, "plugType": 0],
                ["targetSOClevel": dcLevel, "plugType": 1]
            ]
        case .stopCharge, .stopClimate, .lock, .unlock:
            break
        }

        return body
    }

    // MARK: - EV Trip Details (Optional Feature - Override in subclass)

    open func supportsEVTripDetails() -> Bool {
        false
    }

    open func evTripDetailsEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
        fatalError("evTripDetailsEndpoint not implemented for this region")
    }

    open func parseEVTripDetailsResponse(_ data: Data) throws -> [EVTripDetail] {
        fatalError("parseEVTripDetailsResponse not implemented for this region")
    }
}
