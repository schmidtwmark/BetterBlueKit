//
//  HyundaiAPIClient.swift
//  BetterBlueKit
//
//  Hyundai API Client Implementation
//

import Foundation

// MARK: - Hyundai API Endpoint Provider

@MainActor
public final class HyundaiAPIEndpointProvider {
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

    private var clientId: String {
        switch region {
        case .usa:
            "m66129Bb-em93-SPAHYN-bZ91-am4540zp19920"
        default:
            "m0na2res08hlm125puuhqzpv"
        }
    }

    private var clientSecret: String {
        switch region {
        case .usa:
            "v558o935-6nne-423i-baa8"
        default:
            "PPaX5NpW4Dqono3oNoz9K5mZbK9RG5u2"
        }
    }

    private func getEndpointForCommand(command: VehicleCommand, vehicle: Vehicle) -> URL {
        let baseURL = region.apiBaseURL(for: .hyundai)

        switch command {
        case .unlock:
            return URL(string: "\(baseURL)/ac/v2/rcs/rdo/on")!
        case .lock:
            return URL(string: "\(baseURL)/ac/v2/rcs/rdo/off")!
        case .startClimate:
            if vehicle.isElectric {
                return URL(string: "\(baseURL)/ac/v2/evc/fatc/start")!
            } else {
                return URL(string: "\(baseURL)/ac/v2/rcs/rsc/start")!
            }
        case .stopClimate:
            if vehicle.isElectric {
                return URL(string: "\(baseURL)/ac/v2/evc/fatc/stop")!
            } else {
                return URL(string: "\(baseURL)/ac/v2/rcs/rsc/stop")!
            }
        case .startCharge:
            return URL(string: "\(baseURL)/ac/v2/evc/charge/start")!
        case .stopCharge:
            return URL(string: "\(baseURL)/ac/v2/evc/charge/stop")!
        }
    }

    private func getHeaders() -> [String: String] {
        [
            "client_id": clientId,
            "clientSecret": clientSecret,
            "Host": "api.telematics.hyundaiusa.com",
            "User-Agent": "okhttp/3.12.0",
            "Content-Type": "application/json",
            "Accept": "application/json, text/plain, */*",
            "Accept-Encoding": "gzip, deflate, br",
            "Accept-Language": "en-US,en;q=0.9",
            "Connection": "Keep-Alive"
        ]
    }

    private func getAuthorizedHeaders(authToken: AuthToken, vehicle: Vehicle? = nil) -> [String: String] {
        var headers = getHeaders()
        headers["accessToken"] = authToken.accessToken
        headers["language"] = "0"
        headers["to"] = "ISS"
        headers["encryptFlag"] = "false"
        headers["from"] = "SPA"
        headers["offset"] = "-5"
        if let vehicle {
            headers["gen"] = String(vehicle.generation)
            headers["registrationId"] = vehicle.regId
            headers["vin"] = vehicle.vin
            headers["APPCLOUD-VIN"] = vehicle.vin
        }
        headers["brandIndicator"] = "H"
        headers["origin"] = "https://api.telematics.hyundaiusa.com"
        headers["referer"] = "https://api.telematics.hyundaiusa.com/login"
        headers["sec-fetch-dest"] = "empty"
        headers["sec-fetch-mode"] = "cors"
        headers["sec-fetch-site"] = "same-origin"
        headers["username"] = username
        headers["blueLinkServicePin"] = pin
        headers["refresh"] = "false"

        // Generate current timestamp in the required format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = dateFormatter.string(from: Date())
        headers["payloadGenerated"] = timestamp
        headers["includeNonConnectedVehicles"] = "Y"

        return headers
    }
}

extension HyundaiAPIEndpointProvider: APIEndpointProvider {
    public func loginEndpoint() -> APIEndpoint {
        let loginURL = "\(region.apiBaseURL(for: .hyundai))/v2/ac/oauth/token"
        let loginData = [
            "username": username,
            "password": password
        ]

        return APIEndpoint(
            url: loginURL,
            method: .POST,
            headers: getHeaders(),
            body: try? JSONSerialization.data(withJSONObject: loginData),
        )
    }

    public func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint {
        let vehiclesURL = "\(region.apiBaseURL(for: .hyundai))/ac/v2/enrollment/details/\(username)"

        return APIEndpoint(
            url: vehiclesURL,
            method: .GET,
            headers: getAuthorizedHeaders(authToken: authToken),
        )
    }

    public func fetchVehicleStatusEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
        let statusURL = "\(region.apiBaseURL(for: .hyundai))/ac/v2/rcs/rvs/vehicleStatus"

        return APIEndpoint(
            url: statusURL,
            method: .GET,
            headers: getAuthorizedHeaders(authToken: authToken, vehicle: vehicle),
        )
    }

    public func sendCommandEndpoint(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
    ) -> APIEndpoint {
        let endpoint = getEndpointForCommand(command: command, vehicle: vehicle)
        let requestBody = command.getBodyForCommand(
            vin: vehicle.vin,
            isElectric: vehicle.isElectric,
            generation: vehicle.generation,
            username: username,
        )

        return APIEndpoint(
            url: endpoint.absoluteString,
            method: .POST,
            headers: getAuthorizedHeaders(authToken: authToken, vehicle: vehicle),
            body: try? JSONSerialization.data(withJSONObject: requestBody),
        )
    }

    public func parseLoginResponse(_ data: Data, headers _: [String: String]) throws -> AuthToken {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresInString = json["expires_in"] as? String,
              let expiresIn = Int(expiresInString)
        else {
            throw HyundaiKiaAPIError.logError(
                "Invalid login response for \(username): " +
                    "\(String(data: data, encoding: .utf8) ?? "No data")",
                apiName: "HyundaiAPI",
            )
        }

        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        print("✅ [HyundaiAPI] Authentication completed successfully for user \(username)")
        return AuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            pin: pin,
        )
    }

    public func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vehicleArray = json["enrolledVehicleDetails"] as? [[String: Any]]
        else {
            throw HyundaiKiaAPIError.logError(
                "Invalid vehicles response " +
                    "\(String(data: data, encoding: .utf8) ?? "<empty>")",
                apiName: "HyundaiAPI",
            )
        }

        var fetchedVehicles: [Vehicle] = []

        for vehicleData in vehicleArray {
            if let vehicleDetails = vehicleData["vehicleDetails"] as? [String: Any],
               let vin = vehicleDetails["vin"] as? String,
               let regId = vehicleDetails["regid"] as? String,
               let nickname = vehicleDetails["nickName"] as? String,
               let evStatus = vehicleDetails["evStatus"] as? String,
               let generation = vehicleDetails["vehicleGeneration"] as? String {
                let odometer = Distance(
                    length:
                    extractNumber(from: vehicleDetails["odometer"]) ?? 0, units: .miles
                )
                let vehicle = Vehicle(
                    vin: vin,
                    regId: regId,
                    model: nickname,
                    accountId: accountId,
                    isElectric: evStatus == "E",
                    generation: Int(generation) ?? 1,
                    odometer: odometer,
                )
                fetchedVehicles.append(vehicle)
            }
        }

        return fetchedVehicles
    }

    public func parseVehicleStatusResponse(_ data: Data, for vehicle: Vehicle) throws -> VehicleStatus {
        let statusData = try extractStatusData(from: data)
        let evStatus = parseEVStatus(from: statusData, vehicle: vehicle)
        let gasRange = parseGasRange(from: statusData, vehicle: vehicle)
        let location = parseLocation(from: statusData)
        let lockStatus = parseLockStatus(from: statusData)
        let climateStatus = parseClimateStatus(from: statusData)
        let syncDate = parseSyncDate(from: statusData)

        return VehicleStatus(
            vin: vehicle.vin,
            gasRange: gasRange,
            evStatus: evStatus,
            location: location,
            lockStatus: lockStatus,
            climateStatus: climateStatus,
            odometer: vehicle.odometer,
            syncDate: syncDate,
        )
    }

    private func extractStatusData(from data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusData = json["vehicleStatus"] as? [String: Any]
        else {
            throw HyundaiKiaAPIError.logError(
                "Invalid vehicle status response " +
                    "\(String(data: data, encoding: .utf8) ?? "<empty>")",
                apiName: "HyundaiAPI",
            )
        }
        return statusData
    }

    private func fuelRanges(from statusData: [String: Any]) -> [FuelType: Distance] {
        guard let evStatusData = statusData["evStatus"] as? [String: Any] else { return [:] }

        let distances = evStatusData["drvDistance"] as? [[String: Any]] ?? [[:]]
        return distances.reduce(into: [FuelType: Distance]()) { dict, distance in
            let type: Int = extractNumber(from: distance["type"]) ?? 0

            let rangeByFuelData = distance["rangeByFuel"] as? [String: Any] ?? [:]
            let totalAvailableRangeData = rangeByFuelData["totalAvailableRange"] as? [String: Any] ?? [:]

            dict[FuelType(number: type)] = Distance(
                length: extractNumber(from: totalAvailableRangeData["value"]) ?? 0,
                units: Distance.Units(extractNumber(from: totalAvailableRangeData["unit"]) ?? 2),
            )
        }
    }

    private func parseEVStatus(from statusData: [String: Any], vehicle: Vehicle) -> VehicleStatus.EVStatus? {
        guard vehicle.isElectric,
              let evStatusData = statusData["evStatus"] as? [String: Any] else { return nil }
        let ranges = fuelRanges(from: statusData)

        // Sometimes, Hyundai chooses to not report the correct driving distance fuel type, and it just gets a 0
        // To correct this, if we know this is an EV and there's a single driving distance,
        // let's just use whatever is first. This may cause problems for PHEVs in the future
        // but I just want to get this working for today
        let evRange: Distance
        if let range = ranges.first, ranges.count == 1 {
            evRange = range.value
        } else {
            guard let range = ranges[.electric] else { return nil }
            evRange = range
        }

        let fuelPercentage: Double = extractNumber(from: evStatusData["batteryStatus"]) ?? 0

        return VehicleStatus.EVStatus(
            charging: evStatusData["batteryCharge"] as? Bool ?? false,
            chargeSpeed: max(
                extractNumber(from: evStatusData["batteryStndChrgPower"]) ?? 0,
                extractNumber(from: evStatusData["batteryFstChrgPower"]) ?? 0
            ),
            pluggedIn: (extractNumber(from: evStatusData["batteryPlugin"]) ?? 0) != 0,
            evRange: VehicleStatus.FuelRange(range: evRange, percentage: fuelPercentage),
        )
    }

    private func parseGasRange(from statusData: [String: Any], vehicle: Vehicle) -> VehicleStatus.FuelRange? {
        guard !vehicle.isElectric,
              let fuelLevel: Double = extractNumber(from: statusData["fuelLevel"]),
              let gasRange = fuelRanges(from: statusData)[.gas] else { return nil }

        return VehicleStatus.FuelRange(range: gasRange, percentage: fuelLevel)
    }

    private func parseLocation(from statusData: [String: Any]) -> VehicleStatus.Location {
        let vehicleLocationData = statusData["vehicleLocation"] as? [String: Any] ?? [:]
        let coordData = vehicleLocationData["coord"] as? [String: Any] ?? [:]

        return VehicleStatus.Location(
            latitude: extractNumber(from: coordData["lat"]) ?? 0,
            longitude: extractNumber(from: coordData["lon"]) ?? 0
        )
    }

    private func parseLockStatus(from statusData: [String: Any]) -> VehicleStatus.LockStatus {
        VehicleStatus.LockStatus(locked: statusData["doorLock"] as? Bool)
    }

    private func parseClimateStatus(from statusData: [String: Any]) -> VehicleStatus.ClimateStatus {
        let airTemp = statusData["airTemp"] as? [String: Any] ?? [:]

        return VehicleStatus.ClimateStatus(
            defrostOn: statusData["defrost"] as? Bool ?? false,
            airControlOn: statusData["airCtrlOn"] as? Bool ?? false,
            steeringWheelHeatingOn: (extractNumber(from: statusData["steerWheelHeat"]) ?? 0) != 0,
            temperature: Temperature(units: extractNumber(from: airTemp["unit"]), value: airTemp["value"] as? String)
        )
    }

    private func parseSyncDate(from statusData: [String: Any]) -> Date? {
        guard let dateTimeString = statusData["dateTime"] as? String else { return nil }
        return ISO8601DateFormatter().date(from: dateTimeString)
    }

    public func parseCommandResponse(_ data: Data) throws {
        // Check for PIN validation errors even with 200 status code
        if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check for invalid PIN response
            if let isBlueLinkServicePinValid = jsonResponse["isBlueLinkServicePinValid"] as? String,
               isBlueLinkServicePinValid == "invalid" {
                let remainingAttempts = jsonResponse["remainingAttemptCount"] as? String ?? "unknown"
                let errorMessage = "Invalid PIN, \(remainingAttempts) attempts remaining"
                throw HyundaiKiaAPIError.invalidPin(errorMessage, apiName: "HyundaiAPI")
            }
        }
    }
}

// MARK: - Type Alias for Convenience

public typealias HyundaiAPIClient = APIClient<HyundaiAPIEndpointProvider>
