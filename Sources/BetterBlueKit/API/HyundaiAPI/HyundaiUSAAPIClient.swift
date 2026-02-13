//
//  HyundaiUSAAPIClient.swift
//  BetterBlueKit
//
//  Hyundai USA API Client
//

import Foundation

// MARK: - Hyundai USA API Client

@MainActor
public final class HyundaiUSAAPIClient: APIClientBase, APIClientProtocol {

    // MARK: - Constants

    private let clientId = "m66129Bb-em93-SPAHYN-bZ91-am4540zp19920"
    private let clientSecret = "v558o935-6nne-423i-baa8"

    private var baseURL: String {
        region.apiBaseURL(for: .hyundai)
    }

    private var apiHost: String {
        "api.telematics.hyundaiusa.com"
    }

    public override var apiName: String { "HyundaiUSA" }

    // MARK: - Headers

    private func headers() -> [String: String] {
        [
            "client_id": clientId,
            "clientSecret": clientSecret,
            "Host": apiHost,
            "User-Agent": "okhttp/3.12.0",
            "Content-Type": "application/json",
            "Accept": "application/json, text/plain, */*",
            "Accept-Encoding": "gzip, deflate, br",
            "Accept-Language": "en-US,en;q=0.9",
            "Connection": "Keep-Alive"
        ]
    }

    private func authorizedHeaders(authToken: AuthToken, vehicle: Vehicle? = nil) -> [String: String] {
        var result = headers()
        result["accessToken"] = authToken.accessToken
        result["language"] = "0"
        result["to"] = "ISS"
        result["encryptFlag"] = "false"
        result["from"] = "SPA"
        result["offset"] = "-5"
        result["brandIndicator"] = "H"
        result["origin"] = "https://\(apiHost)"
        result["referer"] = "https://\(apiHost)/login"
        result["username"] = username
        result["blueLinkServicePin"] = pin
        result["refresh"] = "false"

        if let vehicle {
            result["gen"] = String(vehicle.generation)
            result["registrationId"] = vehicle.regId
            result["vin"] = vehicle.vin
            result["APPCLOUD-VIN"] = vehicle.vin
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        result["payloadGenerated"] = dateFormatter.string(from: Date())
        result["includeNonConnectedVehicles"] = "Y"

        return result
    }

    // MARK: - APIClientProtocol Implementation

    public func login() async throws -> AuthToken {
        BBLogger.info(.auth, "HyundaiUSA: Attempting login for \(username)")

        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/v2/ac/oauth/token",
            method: .POST,
            headers: headers(),
            body: ["username": username, "password": password],
            requestType: .login
        )

        return try parseLoginResponse(data)
    }

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/ac/v2/enrollment/details/\(username)",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken),
            requestType: .fetchVehicles
        )

        return try parseVehiclesResponse(data)
    }

    public func fetchVehicleStatus(for vehicle: Vehicle, authToken: AuthToken) async throws -> VehicleStatus {
        var statusHeaders = authorizedHeaders(authToken: authToken, vehicle: vehicle)

        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/ac/v2/rcs/rvs/vehicleStatus",
            method: .GET,
            headers: statusHeaders,
            requestType: .fetchVehicleStatus
        )

        return try parseVehicleStatusResponse(data, for: vehicle)
    }

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        let url = commandURL(for: command, vehicle: vehicle)
        let body = commandBody(for: command, vehicle: vehicle)

        let (data, _, _) = try await performJSONRequest(
            url: url,
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicle: vehicle),
            body: body,
            requestType: .sendCommand
        )

        try parseCommandResponse(data)
    }

    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        var tripHeaders = authorizedHeaders(authToken: authToken, vehicle: vehicle)
        tripHeaders["userId"] = username
        tripHeaders["access_token"] = authToken.accessToken

        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/ac/v2/ts/alerts/maintenance/evTripDetails",
            method: .GET,
            headers: tripHeaders,
            requestType: .fetchEVTripDetails
        )

        return try parseEVTripDetailsResponse(data)
    }

    // MARK: - Command Helpers

    private func commandURL(for command: VehicleCommand, vehicle: Vehicle) -> String {
        let path: String = switch command {
        case .unlock: "ac/v2/rcs/rdo/on"
        case .lock: "ac/v2/rcs/rdo/off"
        case .startClimate: vehicle.isElectric ? "ac/v2/evc/fatc/start" : "ac/v2/rcs/rsc/start"
        case .stopClimate: vehicle.isElectric ? "ac/v2/evc/fatc/stop" : "ac/v2/rcs/rsc/stop"
        case .startCharge: "ac/v2/evc/charge/start"
        case .stopCharge: "ac/v2/evc/charge/stop"
        case .setTargetSOC: "ac/v2/evc/charge/targetsoc/set"
        }
        return "\(baseURL)/\(path)"
    }

    private func commandBody(for command: VehicleCommand, vehicle: Vehicle) -> [String: Any] {
        switch command {
        case .startClimate(let options):
            if vehicle.isElectric {
                var body: [String: Any] = [
                    "airCtrl": options.climate ? 1 : 0,
                    "airTemp": ["value": String(Int(options.temperature.value)), "unit": options.temperature.units.integer()],
                    "defrost": options.defrost,
                    "heating1": options.heatValue
                ]
                if vehicle.generation >= 3 {
                    body["igniOnDuration"] = options.duration
                    body["seatHeaterVentInfo"] = options.getSeatHeaterVentInfo()
                }
                return body
            } else {
                return [
                    "Ims": 0,
                    "airCtrl": options.climate ? 1 : 0,
                    "airTemp": ["unit": options.temperature.units.integer(), "value": Int(options.temperature.value)],
                    "defrost": options.defrost,
                    "heating1": options.heatValue,
                    "igniOnDuration": options.duration,
                    "seatHeaterVentInfo": options.getSeatHeaterVentInfo(),
                    "username": username,
                    "vin": vehicle.vin
                ]
            }
        case .startCharge:
            return ["chargeRatio": 100]
        case .setTargetSOC(let acLevel, let dcLevel):
            return ["targetSOClist": [
                ["targetSOClevel": acLevel, "plugType": 1],
                ["targetSOClevel": dcLevel, "plugType": 0]
            ]]
        default:
            return [:]
        }
    }
}

// MARK: - Response Parsing

extension HyundaiUSAAPIClient {

    private func parseLoginResponse(_ data: Data) throws -> AuthToken {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresInString = json["expires_in"] as? String,
              let expiresIn = Int(expiresInString) else {
            throw APIError.logError("Invalid login response: \(String(data: data, encoding: .utf8) ?? "")", apiName: apiName)
        }

        BBLogger.info(.auth, "HyundaiUSA: Login successful")
        return AuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            pin: pin
        )
    }

    private func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vehicleArray = json["enrolledVehicleDetails"] as? [[String: Any]] else {
            throw APIError.logError("Invalid vehicles response", apiName: apiName)
        }

        return vehicleArray.compactMap { vehicleData -> Vehicle? in
            guard let details = vehicleData["vehicleDetails"] as? [String: Any],
                  let vin = details["vin"] as? String,
                  let regId = details["regid"] as? String,
                  let nickname = details["nickName"] as? String,
                  let evStatus = details["evStatus"] as? String,
                  let generation = details["vehicleGeneration"] as? String else {
                return nil
            }

            let odometer = Distance(
                length: extractNumber(from: details["odometer"]) ?? 0,
                units: .miles
            )

            return Vehicle(
                vin: vin,
                regId: regId,
                model: nickname,
                accountId: accountId,
                isElectric: evStatus == "E",
                generation: Int(generation) ?? 1,
                odometer: odometer
            )
        }
    }

    private func parseVehicleStatusResponse(_ data: Data, for vehicle: Vehicle) throws -> VehicleStatus {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusData = json["vehicleStatus"] as? [String: Any] else {
            throw APIError.logError("Invalid status response", apiName: apiName)
        }

        let evStatus = parseEVStatus(from: statusData, vehicle: vehicle)
        let gasRange = parseGasRange(from: statusData, vehicle: vehicle)
        let location = parseLocation(from: statusData)
        let lockStatus = VehicleStatus.LockStatus(locked: statusData["doorLock"] as? Bool)

        let airTemp = statusData["airTemp"] as? [String: Any] ?? [:]
        let climateStatus = VehicleStatus.ClimateStatus(
            defrostOn: statusData["defrost"] as? Bool ?? false,
            airControlOn: statusData["airCtrlOn"] as? Bool ?? false,
            steeringWheelHeatingOn: (extractNumber(from: statusData["steerWheelHeat"]) ?? 0) != 0,
            temperature: Temperature(units: extractNumber(from: airTemp["unit"]), value: airTemp["value"] as? String)
        )

        let syncDate = (statusData["dateTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }

        var battery12V: Int?
        if let batteryData = statusData["battery"] as? [String: Any] {
            battery12V = extractNumber(from: batteryData["batSoc"])
        }

        return VehicleStatus(
            vin: vehicle.vin,
            gasRange: gasRange,
            evStatus: evStatus,
            location: location,
            lockStatus: lockStatus,
            climateStatus: climateStatus,
            odometer: vehicle.odometer,
            syncDate: syncDate,
            battery12V: battery12V,
            doorOpen: parseDoorOpen(from: statusData),
            trunkOpen: statusData["trunkOpen"] as? Bool,
            hoodOpen: statusData["hoodOpen"] as? Bool,
            tirePressureWarning: parseTirePressure(from: statusData)
        )
    }

    private func parseCommandResponse(_ data: Data) throws {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let pinValid = json["isBlueLinkServicePinValid"] as? String,
           pinValid == "invalid" {
            let remaining = json["remainingAttemptCount"] as? String ?? "unknown"
            throw APIError.invalidPin("Invalid PIN, \(remaining) attempts remaining", apiName: apiName)
        }
    }

    private func parseEVTripDetailsResponse(_ data: Data) throws -> [EVTripDetail] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tripDetails = json["tripdetails"] as? [[String: Any]] else {
            throw APIError(message: "Failed to parse trip details", apiName: apiName)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.S"

        return tripDetails.compactMap { trip -> EVTripDetail? in
            guard let distance = trip["distance"] as? Int,
                  let odometerDict = trip["odometer"] as? [String: Any],
                  let odometerValue = odometerDict["value"] as? Double,
                  let accessories = trip["accessories"] as? Int,
                  let totalUsed = trip["totalused"] as? Int,
                  let regen = trip["regen"] as? Int,
                  let climate = trip["climate"] as? Int,
                  let drivetrain = trip["drivetrain"] as? Int,
                  let batteryCare = trip["batterycare"] as? Int,
                  let startDateString = trip["startdate"] as? String,
                  let durationDict = trip["duration"] as? [String: Any],
                  let durationValue = durationDict["value"] as? Int,
                  let avgSpeedDict = trip["avgspeed"] as? [String: Any],
                  let avgSpeedValue = avgSpeedDict["value"] as? Double,
                  let maxSpeedDict = trip["maxspeed"] as? [String: Any],
                  let maxSpeedValue = maxSpeedDict["value"] as? Double,
                  let startDate = dateFormatter.date(from: startDateString) else {
                return nil
            }

            return EVTripDetail(
                distance: Double(distance),
                odometer: odometerValue,
                accessoriesEnergy: accessories,
                totalEnergyUsed: totalUsed,
                regenEnergy: regen,
                climateEnergy: climate,
                drivetrainEnergy: drivetrain,
                batteryCareEnergy: batteryCare,
                startDate: startDate,
                durationSeconds: durationValue,
                avgSpeed: avgSpeedValue,
                maxSpeed: maxSpeedValue
            )
        }
    }

    // MARK: - Status Parsing Helpers

    private func parseEVStatus(from statusData: [String: Any], vehicle: Vehicle) -> VehicleStatus.EVStatus? {
        guard vehicle.isElectric,
              let evStatusData = statusData["evStatus"] as? [String: Any] else { return nil }

        let ranges = fuelRanges(from: statusData)
        let evRange: Distance
        if let range = ranges.first, ranges.count == 1 {
            evRange = range.value
        } else {
            guard let range = ranges[.electric] else { return nil }
            evRange = range
        }

        let fuelPercentage: Double = extractNumber(from: evStatusData["batteryStatus"]) ?? 0
        let remainTime2 = evStatusData["remainTime2"] as? [String: Any] ?? [:]
        let atc = remainTime2["atc"] as? [String: Any] ?? [:]
        let chargeTimeMinutes: Int = extractNumber(from: atc["value"]) ?? 0
        let batteryPlugin: Int = extractNumber(from: evStatusData["batteryPlugin"]) ?? 0

        let reserveChargeInfos = evStatusData["reservChargeInfos"] as? [String: Any] ?? [:]
        let targetSocList = reserveChargeInfos["targetSOClist"] as? [[String: Any]] ?? []
        var targetSocAC: Double?, targetSocDC: Double?
        for target in targetSocList {
            if let plugType = target["plugType"] as? Int, let soc = target["targetSOClevel"] as? Double {
                if plugType == 1 { targetSocAC = soc }
                else if plugType == 0 { targetSocDC = soc }
            }
        }

        return VehicleStatus.EVStatus(
            charging: evStatusData["batteryCharge"] as? Bool ?? false,
            chargeSpeed: max(
                extractNumber(from: evStatusData["batteryStndChrgPower"]) ?? 0,
                extractNumber(from: evStatusData["batteryFstChrgPower"]) ?? 0
            ),
            evRange: VehicleStatus.FuelRange(range: evRange, percentage: fuelPercentage),
            plugType: VehicleStatus.PlugType(fromBatteryPlugin: batteryPlugin),
            chargeTime: .seconds(60 * chargeTimeMinutes),
            targetSocAC: targetSocAC,
            targetSocDC: targetSocDC
        )
    }

    private func fuelRanges(from statusData: [String: Any]) -> [FuelType: Distance] {
        guard let evStatusData = statusData["evStatus"] as? [String: Any] else { return [:] }
        let distances = evStatusData["drvDistance"] as? [[String: Any]] ?? []
        return distances.reduce(into: [:]) { dict, distance in
            let type: Int = extractNumber(from: distance["type"]) ?? 0
            let rangeByFuelData = distance["rangeByFuel"] as? [String: Any] ?? [:]
            let totalRange = rangeByFuelData["totalAvailableRange"] as? [String: Any] ?? [:]
            dict[FuelType(number: type)] = Distance(
                length: extractNumber(from: totalRange["value"]) ?? 0,
                units: Distance.Units(extractNumber(from: totalRange["unit"]) ?? 2)
            )
        }
    }

    private func parseGasRange(from statusData: [String: Any], vehicle: Vehicle) -> VehicleStatus.FuelRange? {
        guard !vehicle.isElectric,
              let fuelLevel: Double = extractNumber(from: statusData["fuelLevel"]),
              let gasRange = fuelRanges(from: statusData)[.gas] else { return nil }
        return VehicleStatus.FuelRange(range: gasRange, percentage: fuelLevel)
    }

    private func parseLocation(from statusData: [String: Any]) -> VehicleStatus.Location {
        let vehicleLocation = statusData["vehicleLocation"] as? [String: Any] ?? [:]
        let coord = vehicleLocation["coord"] as? [String: Any] ?? [:]
        return VehicleStatus.Location(
            latitude: extractNumber(from: coord["lat"]) ?? 0,
            longitude: extractNumber(from: coord["lon"]) ?? 0
        )
    }

    private func parseDoorOpen(from statusData: [String: Any]) -> VehicleStatus.DoorStatus? {
        guard let doorData = statusData["doorOpen"] as? [String: Any] else { return nil }
        return VehicleStatus.DoorStatus(
            frontLeft: (extractNumber(from: doorData["frontLeft"]) ?? 0) != 0,
            frontRight: (extractNumber(from: doorData["frontRight"]) ?? 0) != 0,
            backLeft: (extractNumber(from: doorData["backLeft"]) ?? 0) != 0,
            backRight: (extractNumber(from: doorData["backRight"]) ?? 0) != 0
        )
    }

    private func parseTirePressure(from statusData: [String: Any]) -> VehicleStatus.TirePressureWarning? {
        guard let tireData = statusData["tirePressureLamp"] as? [String: Any] else { return nil }
        return VehicleStatus.TirePressureWarning(
            frontLeft: (extractNumber(from: tireData["tirePressureWarningLampFrontLeft"]) ?? 0) != 0,
            frontRight: (extractNumber(from: tireData["tirePressureWarningLampFrontRight"]) ?? 0) != 0,
            rearLeft: (extractNumber(from: tireData["tirePressureWarningLampRearLeft"]) ?? 0) != 0,
            rearRight: (extractNumber(from: tireData["tirePressureWarningLampRearRight"]) ?? 0) != 0,
            all: (extractNumber(from: tireData["tirePressureWarningLampAll"]) ?? 0) != 0
        )
    }
}
