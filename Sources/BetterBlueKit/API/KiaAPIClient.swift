//
//  KiaAPIClient.swift
//  BetterBlue
//
//  Created by Mark Schmidt on 7/23/25.
//

import Foundation

@MainActor
public final class KiaAPIEndpointProvider {
    private let region: Region
    private let username: String
    private let password: String
    private let pin: String
    private let accountId: UUID

    public init(configuration: APIClientConfiguration) {
        region = configuration.region
        username = configuration.username
        password = configuration.password
        pin = configuration.pin
        accountId = configuration.accountId
    }

    // Use region-specific base URL
    private var baseURL: String {
        region.apiBaseURL(for: .kia)
    }

    private var apiURL: String {
        "\(baseURL)/apigw/v1/"
    }

    private let deviceId: String = {
        let charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomPart = String((0 ..< 22).map { _ in charset.randomElement()! })
        return "\(randomPart):\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }()

    // MARK: - Helper Methods

    private func apiHeaders() -> [String: String] {
        let offset = TimeZone.current.secondsFromGMT() / 3600
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"

        // Extract host from baseURL (remove https:// prefix)
        let hostName = baseURL.replacingOccurrences(of: "https://", with: "")

        return [
            "content-type": "application/json;charset=UTF-8", "accept": "application/json, text/plain, */*",
            "accept-encoding": "gzip, deflate, br", "accept-language": "en-US,en;q=0.9",
            "apptype": "L", "appversion": "7.15.2", "clientid": "MWAMOBILE", "from": "SPA",
            "host": hostName, "language": "0", "offset": "\(offset)", "ostype": "Android",
            "osversion": "11", "secretkey": "98er-w34rf-ibf3-3f6h", "to": "APIGW",
            "tokentype": "G", "user-agent": "okhttp/4.10.0", "deviceid": deviceId,
            "date": formatter.string(from: Date())
        ]
    }

    private func authedApiHeaders(authToken: AuthToken, vehicleKey: String?) -> [String: String] {
        var headers = apiHeaders()
        headers["sid"] = authToken.accessToken
        if let key = vehicleKey {
            headers["vinkey"] = key
        }
        return headers
    }

    private func getCommandEndpoint(command: VehicleCommand) -> String {
        let path = switch command {
        case .lock:
            "rems/door/lock"
        case .unlock:
            "rems/door/unlock"
        case .startClimate:
            "rems/start"
        case .stopClimate:
            "rems/stop"
        case .startCharge:
            "evc/charge"
        case .stopCharge:
            "evc/cancel"
        }
        return "\(apiURL)\(path)"
    }

    private func checkForKiaSpecificErrors(data: Data) throws {
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
            throw HyundaiKiaAPIError.invalidCredentials("Invalid username or password", apiName: "KiaAPI")
        }

        if errorCode == 1005 || errorCode == 1103 {
            throw HyundaiKiaAPIError.invalidVehicleSession(errorMessage, apiName: "KiaAPI")
        }

        if errorCode == 1003,
           messageLower.contains("session key") || messageLower.contains("invalid") ||
           messageLower.contains("expired") {
            throw HyundaiKiaAPIError.invalidCredentials("Session Key is either invalid or expired", apiName: "KiaAPI")
        }

        throw HyundaiKiaAPIError.logError(
            "Kia API error: \(errorMessage) (Code: \(errorCode), Status: \(statusCode), Type: \(errorType))",
            code: errorCode, apiName: "KiaAPI",
        )
    }
}

extension KiaAPIEndpointProvider: APIEndpointProvider {
    public func loginEndpoint() -> APIEndpoint {
        let loginURL = "\(apiURL)prof/authUser"
        let loginData: [String: Any] = [
            "deviceKey": "",
            "deviceType": 2,
            "userCredential": [
                "userId": username,
                "password": password
            ]
        ]

        return APIEndpoint(
            url: loginURL,
            method: .POST,
            headers: apiHeaders(),
            body: try? JSONSerialization.data(withJSONObject: loginData),
        )
    }

    public func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint {
        let vehiclesURL = "\(apiURL)ownr/gvl"

        return APIEndpoint(
            url: vehiclesURL,
            method: .GET,
            headers: authedApiHeaders(authToken: authToken, vehicleKey: nil),
        )
    }

    public func fetchVehicleStatusEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
        let statusURL = "\(apiURL)cmm/gvi"

        // Log the vehicleKey for debugging
        print("🔧 [KiaAPI] Fetching status for VIN: \(vehicle.vin), vehicleKey: \(vehicle.vehicleKey ?? "nil")")

        let body: [String: Any] = [
            "vehicleConfigReq": [
                "airTempRange": "0",
                "maintenance": "1",
                "seatHeatCoolOption": "0",
                "vehicle": "1",
                "vehicleFeature": "0"
            ],
            "vehicleInfoReq": [
                "drivingActivty": "0",
                "dtc": "1",
                "enrollment": "1",
                "functionalCards": "0",
                "location": "1",
                "vehicleStatus": "1",
                "weather": "0"
            ],
            "vinKey": [vehicle.vehicleKey ?? ""]
        ]

        return APIEndpoint(
            url: statusURL,
            method: .POST,
            headers: authedApiHeaders(authToken: authToken, vehicleKey: vehicle.vehicleKey),
            body: try? JSONSerialization.data(withJSONObject: body),
        )
    }

    public func sendCommandEndpoint(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
    ) -> APIEndpoint {
        let endpoint = getCommandEndpoint(command: command)
        let requestBody = command.getBodyForCommand(
            vin: vehicle.vin,
            isElectric: vehicle.isElectric,
            generation: vehicle.generation,
            username: username,
        )

        return APIEndpoint(
            url: endpoint,
            method: .POST,
            headers: authedApiHeaders(authToken: authToken, vehicleKey: vehicle.vehicleKey),
            body: try? JSONSerialization.data(withJSONObject: requestBody),
        )
    }

    public func parseLoginResponse(_ data: Data, headers: [String: String]) throws -> AuthToken {
        // Check for Kia-specific errors in the response body
        try checkForKiaSpecificErrors(data: data)

        // Extract session ID from response headers - Kia API returns 'sid' header
        guard let sessionId = headers["sid"] ?? headers["Sid"] ?? headers["SID"] else {
            throw HyundaiKiaAPIError.logError("Kia API login response missing session ID header", apiName: "KiaAPI")
        }

        let validUntil = Date().addingTimeInterval(3600) // 1 hour like Python
        print("✅ [KiaAPI] Authentication completed successfully for user \(username), session ID: \(sessionId)")

        return AuthToken(
            accessToken: sessionId,
            refreshToken: sessionId, // Kia uses the same session ID for both
            expiresAt: validUntil,
            pin: pin,
        )
    }

    public func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let vehicleSummary = payload["vehicleSummary"] as? [[String: Any]]
        else {
            throw HyundaiKiaAPIError.logError(
                "Invalid Kia vehicles response " +
                    "\(String(data: data, encoding: .utf8) ?? "<empty>")",
                apiName: "KiaAPI",
            )
        }

        var fetchedVehicles: [Vehicle] = []

        for entry in vehicleSummary {
            if let vin = entry["vin"] as? String,
               let regId = entry["vehicleIdentifier"] as? String,
               let nickname = entry["nickName"] as? String,
               let vehicleKey = entry["vehicleKey"] as? String,
               let generation = entry["genType"] as? String,
               let fuelType: Int = extractNumber(from: entry["fuelType"]) {
                // Parse mileage field (always in miles)
                let odometer = Distance(
                    length: extractNumber(from: entry["mileage"]) ?? 0,
                    units: .miles,
                )

                let vehicle = Vehicle(
                    vin: vin,
                    regId: regId,
                    model: "\(nickname)",
                    accountId: accountId,
                    isElectric: fuelType != 3,
                    generation: Int(generation)!,
                    odometer: odometer,
                    vehicleKey: vehicleKey, // Store vehicle key in the Vehicle model
                )
                fetchedVehicles.append(vehicle)
            }
        }

        return fetchedVehicles
    }

    public func parseVehicleStatusResponse(_ data: Data, for vehicle: Vehicle) throws -> VehicleStatus {
        try checkForKiaSpecificErrors(data: data)
        let lastVehicleInfo = try extractLastVehicleInfo(from: data)
        let vehicleStatus = try extractVehicleStatus(from: lastVehicleInfo)

        return VehicleStatus(
            vin: vehicle.vin,
            gasRange: parseKiaGasRange(from: vehicleStatus),
            evStatus: parseKiaEVStatus(from: vehicleStatus),
            location: parseKiaLocation(from: lastVehicleInfo),
            lockStatus: parseKiaLockStatus(from: vehicleStatus),
            climateStatus: parseKiaClimateStatus(from: vehicleStatus),
            odometer: vehicle.odometer,
            syncDate: parseKiaSyncDate(from: vehicleStatus),
        )
    }

    private func extractLastVehicleInfo(from data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let vehicleInfoList = payload["vehicleInfoList"] as? [[String: Any]],
              let vehicleInfo = vehicleInfoList.first,
              let lastVehicleInfo = vehicleInfo["lastVehicleInfo"] as? [String: Any]
        else {
            throw HyundaiKiaAPIError.logError("Invalid Kia vehicle status response", apiName: "KiaAPI")
        }
        return lastVehicleInfo
    }

    private func extractVehicleStatus(from lastVehicleInfo: [String: Any]) throws -> [String: Any] {
        guard let vehicleStatusRpt = lastVehicleInfo["vehicleStatusRpt"] as? [String: Any],
              let vehicleStatus = vehicleStatusRpt["vehicleStatus"] as? [String: Any]
        else {
            throw HyundaiKiaAPIError.logError("Invalid Kia vehicle status response", apiName: "KiaAPI")
        }
        return vehicleStatus
    }

    private func parseKiaEVStatus(from vehicleStatus: [String: Any]) -> VehicleStatus.EVStatus? {
        let evStatusData = vehicleStatus["evStatus"] as? [String: Any] ?? [:]
        let batteryStatus: Double = extractNumber(from: evStatusData["batteryStatus"]) ?? 0
        guard batteryStatus > 0 else { return nil }

        let drvDistance = evStatusData["drvDistance"] as? [[String: Any]] ?? []
        let rangeInfo = drvDistance.first?["rangeByFuel"] as? [String: Any] ?? [:]
        let evModeRange = rangeInfo["evModeRange"] as? [String: Any] ?? [:]

        let evRange = Distance(
            length: extractNumber(from: evModeRange["value"]) ?? 0,
            units: Distance.Units(extractNumber(from: evModeRange["unit"]) ?? 3)
        )

        return VehicleStatus.EVStatus(
            charging: evStatusData["batteryCharge"] as? Bool ?? false,
            chargeSpeed: max(
                extractNumber(from: evStatusData["batteryStndChrgPower"]) ?? 0,
                extractNumber(from: evStatusData["batteryFstChrgPower"]) ?? 0
            ),
            pluggedIn: (extractNumber(from: evStatusData["batteryPlugin"]) ?? 0) != 0,
            evRange: VehicleStatus.FuelRange(range: evRange, percentage: batteryStatus),
        )
    }

    private func parseKiaGasRange(from vehicleStatus: [String: Any]) -> VehicleStatus.FuelRange? {
        guard let distanceToEmptyData = vehicleStatus["distanceToEmpty"] as? [String: Any],
              let gasRangeValue: Double = extractNumber(from: distanceToEmptyData["value"]),
              let gasRangeUnit: Int = extractNumber(from: distanceToEmptyData["unit"]),
              let fuelLevel: Double = extractNumber(from: vehicleStatus["fuelLevel"]) else { return nil }

        let gasRangeDistance = Distance(length: gasRangeValue, units: Distance.Units(gasRangeUnit))
        return VehicleStatus.FuelRange(range: gasRangeDistance, percentage: fuelLevel)
    }

    private func parseKiaLocation(from lastVehicleInfo: [String: Any]) -> VehicleStatus.Location {
        let location = lastVehicleInfo["location"] as? [String: Any] ?? [:]
        let coord = location["coord"] as? [String: Any] ?? [:]

        return VehicleStatus.Location(
            latitude: extractNumber(from: coord["lat"]) ?? 0,
            longitude: extractNumber(from: coord["lon"]) ?? 0
        )
    }

    private func parseKiaLockStatus(from vehicleStatus: [String: Any]) -> VehicleStatus.LockStatus {
        VehicleStatus.LockStatus(locked: vehicleStatus["doorLock"] as? Bool)
    }

    private func parseKiaClimateStatus(from vehicleStatus: [String: Any]) -> VehicleStatus.ClimateStatus {
        let climate = vehicleStatus["climate"] as? [String: Any] ?? [:]
        let airTemp = climate["airTemp"] as? [String: Any] ?? [:]
        let heatingAccessory = climate["heatingAccessory"] as? [String: Any] ?? [:]

        return VehicleStatus.ClimateStatus(
            defrostOn: climate["defrost"] as? Bool ?? false,
            airControlOn: climate["airCtrl"] as? Bool ?? false,
            steeringWheelHeatingOn: (extractNumber(from: heatingAccessory["steeringWheel"]) ?? 0) != 0,
            temperature: Temperature(units: extractNumber(from: airTemp["unit"]), value: airTemp["value"] as? String)
        )
    }

    private func parseKiaSyncDate(from vehicleStatus: [String: Any]) -> Date? {
        guard let syncDateData = vehicleStatus["syncDate"] as? [String: Any],
              let utcString = syncDateData["utc"] as? String else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: utcString)
    }

    public func parseCommandResponse(_ data: Data) throws {
        // Check for Kia-specific errors in command response
        try checkForKiaSpecificErrors(data: data)
    }
}

// MARK: - Type Alias for Convenience

public typealias KiaAPIClient = APIClient<KiaAPIEndpointProvider>
