//
//  KiaAPI+Parsing.swift
//  BetterBlueKit
//
//  Created by Mark Schmidt on 12/26/25.
//

import Foundation

extension KiaAPIEndpointProvider {
    public func parseLoginResponse(_ data: Data, headers: [String: String]) throws -> AuthToken {
        // Check for Kia-specific errors in the response body
        try checkForKiaSpecificErrors(data: data)

        let sid = headers["sid"] ?? headers["Sid"] ?? headers["SID"]

        // Extract session ID from response headers - Kia API returns 'sid' header
        guard let sessionId = sid else {
            throw APIError.logError("Kia API login response missing session ID header", apiName: "KiaAPI")
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

    public func parseVerifyOTPResponse(
        _ data: Data, headers: [String: String]) throws -> (rememberMeToken: String, sid: String) {
        try checkForKiaSpecificErrors(data: data)

        guard let rememberMeToken = headers["rememberMeToken"]
                ?? headers["rememberMeToken"] ?? headers["rememberMeToken"],
              let sid = headers["sid"] ?? headers["Sid"] ?? headers["SID"]
        else {
            throw APIError.logError("Kia API verify OTP response missing tokens", apiName: "KiaAPI")
        }

        return (rememberMeToken, sid)
    }

    public func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let vehicleSummary = payload["vehicleSummary"] as? [[String: Any]]
        else {
            throw APIError.logError(
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
            throw APIError.logError("Invalid Kia vehicle status response", apiName: "KiaAPI")
        }
        return lastVehicleInfo
    }

    private func extractVehicleStatus(from lastVehicleInfo: [String: Any]) throws -> [String: Any] {
        guard let vehicleStatusRpt = lastVehicleInfo["vehicleStatusRpt"] as? [String: Any],
              let vehicleStatus = vehicleStatusRpt["vehicleStatus"] as? [String: Any]
        else {
            throw APIError.logError("Invalid Kia vehicle status response", apiName: "KiaAPI")
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
        let chargeTimes = evStatusData["remainChargeTime"] as? [[String: Any]] ?? []
        let chargeTime = extractNumber(from: chargeTimes.first?["value"]) ?? 0

        let evRange = Distance(
            length: extractNumber(from: evModeRange["value"]) ?? 0,
            units: Distance.Units(extractNumber(from: evModeRange["unit"]) ?? 3)
        )

        let batteryPlugin: Int = extractNumber(from: evStatusData["batteryPlugin"]) ?? 0

        // Extract target SOC values for AC and DC charging (plugType 0 = AC, plugType 1 = DC)
        let targetSOC = evStatusData["targetSOC"] as? [[String: Any]] ?? []
        var targetSocAC: Double?
        var targetSocDC: Double?

        for target in targetSOC {
            if let plugType = target["plugType"] as? Int, let soc = target["targetSOClevel"] as? Double {
                if plugType == 0 {
                    targetSocAC = soc
                } else if plugType == 1 {
                    targetSocDC = soc
                }
            }
        }

        return VehicleStatus.EVStatus(
            charging: evStatusData["batteryCharge"] as? Bool ?? false,
            chargeSpeed: max(
                extractNumber(from: evStatusData["batteryStndChrgPower"]) ?? 0,
                extractNumber(from: evStatusData["batteryFstChrgPower"]) ?? 0
            ),
            evRange: VehicleStatus.FuelRange(range: evRange, percentage: batteryStatus),
            plugType: VehicleStatus.PlugType(fromBatteryPlugin: batteryPlugin),
            chargeTime: .seconds(60 * chargeTime),
            targetSocAC: targetSocAC,
            targetSocDC: targetSocDC
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
