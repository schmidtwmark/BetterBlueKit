//
//  KiaUSAAPIClient+Parsing.swift
//  BetterBlueKit
//
//  Response parsing for Kia USA API
//

import Foundation

// MARK: - Response Parsing

extension KiaUSAAPIClient {

    func parseLoginResponse(_ data: Data, headers: [String: String]) throws -> AuthToken {
        try checkForKiaErrors(data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            BBLogger.error(.auth, "KiaUSA: Failed to parse login response as JSON")
            throw APIError.logError("Failed to parse login response", apiName: apiName)
        }

        // Check for MFA requirement
        if let payload = json["payload"] as? [String: Any],
           let otpKey = payload["otpKey"] as? String {
            let xid = headers["xid"] ?? headers["Xid"] ?? headers["XID"] ?? ""
            let hasEmail = payload["hasEmail"] as? Bool ?? false
            let hasPhone = payload["hasPhone"] as? Bool ?? false
            let email = payload["email"] as? String
            let phone = payload["phone"] as? String
            let rmTokenExpired = payload["rmTokenExpired"] as? Bool ?? false

            var mfaLog = "MFA required - otpKey: \(otpKey), xid: \(xid)"
            mfaLog += " | Contact options - hasEmail: \(hasEmail), hasPhone: \(hasPhone)"
            if let email { mfaLog += " | Email: \(email)" }
            if let phone { mfaLog += " | Phone: \(phone)" }
            if rmTokenExpired { mfaLog += " | rmTokenExpired: true" }
            BBLogger.info(.mfa, mfaLog)

            throw APIError.requiresMFA(
                xid: xid,
                otpKey: otpKey,
                hasEmail: hasEmail,
                hasPhone: hasPhone,
                email: email,
                phone: phone,
                rmTokenExpired: rmTokenExpired,
                apiName: apiName
            )
        }

        let sid = headers["sid"] ?? headers["Sid"] ?? headers["SID"]
        guard let sessionId = sid else {
            throw APIError.logError("Login response missing session ID header", apiName: apiName)
        }

        let validUntil = Date().addingTimeInterval(3600)
        BBLogger.info(.auth, "KiaUSA: Authentication completed successfully for user \(username)")

        return AuthToken(
            accessToken: sessionId,
            refreshToken: sessionId,
            expiresAt: validUntil,
            pin: pin
        )
    }

    func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] {
        try checkForKiaErrors(data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let vehicleSummary = payload["vehicleSummary"] as? [[String: Any]] else {
            throw APIError.logError("Invalid vehicles response", apiName: apiName)
        }

        return vehicleSummary.compactMap { entry -> Vehicle? in
            guard let vin = entry["vin"] as? String,
                  let regId = entry["vehicleIdentifier"] as? String,
                  let nickname = entry["nickName"] as? String,
                  let vehicleKey = entry["vehicleKey"] as? String,
                  let generation = entry["genType"] as? String,
                  let fuelType: Int = extractNumber(from: entry["fuelType"]) else {
                return nil
            }

            let odometer = Distance(
                length: extractNumber(from: entry["mileage"]) ?? 0,
                units: .miles
            )

            return Vehicle(
                vin: vin,
                regId: regId,
                model: nickname,
                accountId: accountId,
                isElectric: fuelType != 3,
                generation: Int(generation) ?? 1,
                odometer: odometer,
                vehicleKey: vehicleKey
            )
        }
    }

    func parseVehicleStatusResponse(_ data: Data, for vehicle: Vehicle) throws -> VehicleStatus {
        try checkForKiaErrors(data: data)
        let lastVehicleInfo = try extractLastVehicleInfo(from: data)
        let vehicleStatus = try extractVehicleStatus(from: lastVehicleInfo)
        let (trunkOpen, hoodOpen) = parseHoodTrunk(from: vehicleStatus)

        return VehicleStatus(
            vin: vehicle.vin,
            gasRange: parseGasRange(from: vehicleStatus),
            evStatus: parseEVStatus(from: vehicleStatus),
            location: parseLocation(from: lastVehicleInfo),
            lockStatus: VehicleStatus.LockStatus(locked: vehicleStatus["doorLock"] as? Bool),
            climateStatus: parseClimateStatus(from: vehicleStatus),
            odometer: vehicle.odometer,
            syncDate: parseSyncDate(from: vehicleStatus),
            battery12V: parseBattery12V(from: vehicleStatus),
            doorOpen: parseDoorOpen(from: vehicleStatus),
            trunkOpen: trunkOpen,
            hoodOpen: hoodOpen,
            tirePressureWarning: parseTirePressure(from: vehicleStatus)
        )
    }

    private func extractLastVehicleInfo(from data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let vehicleInfoList = payload["vehicleInfoList"] as? [[String: Any]],
              let vehicleInfo = vehicleInfoList.first,
              let lastVehicleInfo = vehicleInfo["lastVehicleInfo"] as? [String: Any] else {
            throw APIError.logError("Invalid vehicle status response", apiName: apiName)
        }
        return lastVehicleInfo
    }

    private func extractVehicleStatus(from lastVehicleInfo: [String: Any]) throws -> [String: Any] {
        guard let vehicleStatusRpt = lastVehicleInfo["vehicleStatusRpt"] as? [String: Any],
              let vehicleStatus = vehicleStatusRpt["vehicleStatus"] as? [String: Any] else {
            throw APIError.logError("Invalid vehicle status response", apiName: apiName)
        }
        return vehicleStatus
    }

    private func parseEVStatus(from vehicleStatus: [String: Any]) -> VehicleStatus.EVStatus? {
        let evStatusData = vehicleStatus["evStatus"] as? [String: Any] ?? [:]
        let batteryStatus: Double = extractNumber(from: evStatusData["batteryStatus"]) ?? 0
        guard batteryStatus > 0 else { return nil }

        let drvDistance = evStatusData["drvDistance"] as? [[String: Any]] ?? []
        let rangeInfo = drvDistance.first?["rangeByFuel"] as? [String: Any] ?? [:]
        let evModeRange = rangeInfo["evModeRange"] as? [String: Any] ?? [:]
        let chargeTimes = evStatusData["remainChargeTime"] as? [[String: Any]] ?? []
        let chargeTime: Int = extractNumber(from: chargeTimes.first?["value"]) ?? 0

        let evRange = Distance(
            length: extractNumber(from: evModeRange["value"]) ?? 0,
            units: Distance.Units(extractNumber(from: evModeRange["unit"]) ?? 3)
        )

        let batteryPlugin: Int = extractNumber(from: evStatusData["batteryPlugin"]) ?? 0

        let targetSOC = evStatusData["targetSOC"] as? [[String: Any]] ?? []
        var targetSocAC: Double?, targetSocDC: Double?
        for target in targetSOC {
            if let plugType = target["plugType"] as? Int, let soc = target["targetSOClevel"] as? Double {
                if plugType == 0 { targetSocAC = soc } else if plugType == 1 { targetSocDC = soc }
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

    private func parseGasRange(from vehicleStatus: [String: Any]) -> VehicleStatus.FuelRange? {
        guard let distanceToEmptyData = vehicleStatus["distanceToEmpty"] as? [String: Any],
              let gasRangeValue: Double = extractNumber(from: distanceToEmptyData["value"]),
              let gasRangeUnit: Int = extractNumber(from: distanceToEmptyData["unit"]),
              let fuelLevel: Double = extractNumber(from: vehicleStatus["fuelLevel"]) else { return nil }

        let gasRangeDistance = Distance(length: gasRangeValue, units: Distance.Units(gasRangeUnit))
        return VehicleStatus.FuelRange(range: gasRangeDistance, percentage: fuelLevel)
    }

    private func parseLocation(from lastVehicleInfo: [String: Any]) -> VehicleStatus.Location {
        let location = lastVehicleInfo["location"] as? [String: Any] ?? [:]
        let coord = location["coord"] as? [String: Any] ?? [:]
        return VehicleStatus.Location(
            latitude: extractNumber(from: coord["lat"]) ?? 0,
            longitude: extractNumber(from: coord["lon"]) ?? 0
        )
    }

    private func parseClimateStatus(from vehicleStatus: [String: Any]) -> VehicleStatus.ClimateStatus {
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

    private func parseSyncDate(from vehicleStatus: [String: Any]) -> Date? {
        guard let syncDateData = vehicleStatus["syncDate"] as? [String: Any],
              let utcString = syncDateData["utc"] as? String else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: utcString)
    }

    private func parseHoodTrunk(from vehicleStatus: [String: Any]) -> (trunkOpen: Bool?, hoodOpen: Bool?) {
        if let doorStatus = vehicleStatus["doorStatus"] as? [String: Any] {
            let trunk: Int? = extractNumber(from: doorStatus["trunk"])
            let hood: Int? = extractNumber(from: doorStatus["hood"])
            return (trunk.map { $0 != 0 }, hood.map { $0 != 0 })
        }
        return (vehicleStatus["trunkOpen"] as? Bool, vehicleStatus["hoodOpen"] as? Bool)
    }

    private func parseBattery12V(from vehicleStatus: [String: Any]) -> Int? {
        if let batteryStatus = vehicleStatus["batteryStatus"] as? [String: Any],
           let stateOfCharge: Int = extractNumber(from: batteryStatus["stateOfCharge"]) {
            return stateOfCharge
        }
        if let batteryData = vehicleStatus["battery"] as? [String: Any],
           let batSoc: Int = extractNumber(from: batteryData["batSoc"]) {
            return batSoc
        }
        return nil
    }

    private func parseDoorOpen(from vehicleStatus: [String: Any]) -> VehicleStatus.DoorStatus? {
        let doorData: [String: Any]?
        if let status = vehicleStatus["doorStatus"] as? [String: Any] {
            doorData = status
        } else if let open = vehicleStatus["doorOpen"] as? [String: Any] {
            doorData = open
        } else {
            return nil
        }

        guard let data = doorData else { return nil }
        return VehicleStatus.DoorStatus(
            frontLeft: (extractNumber(from: data["frontLeft"]) ?? 0) != 0,
            frontRight: (extractNumber(from: data["frontRight"]) ?? 0) != 0,
            backLeft: (extractNumber(from: data["backLeft"]) ?? 0) != 0,
            backRight: (extractNumber(from: data["backRight"]) ?? 0) != 0
        )
    }

    private func parseTirePressure(from vehicleStatus: [String: Any]) -> VehicleStatus.TirePressureWarning? {
        if let tireData = vehicleStatus["tirePressure"] as? [String: Any] {
            return VehicleStatus.TirePressureWarning(
                frontLeft: (extractNumber(from: tireData["frontLeft"]) ?? 0) != 0,
                frontRight: (extractNumber(from: tireData["frontRight"]) ?? 0) != 0,
                rearLeft: (extractNumber(from: tireData["rearLeft"]) ?? 0) != 0,
                rearRight: (extractNumber(from: tireData["rearRight"]) ?? 0) != 0,
                all: (extractNumber(from: tireData["all"]) ?? 0) != 0
            )
        }
        if let tireData = vehicleStatus["tirePressureLamp"] as? [String: Any] {
            return VehicleStatus.TirePressureWarning(
                frontLeft: (extractNumber(from: tireData["tirePressureWarningLampFrontLeft"]) ?? 0) != 0,
                frontRight: (extractNumber(from: tireData["tirePressureWarningLampFrontRight"]) ?? 0) != 0,
                rearLeft: (extractNumber(from: tireData["tirePressureWarningLampRearLeft"]) ?? 0) != 0,
                rearRight: (extractNumber(from: tireData["tirePressureWarningLampRearRight"]) ?? 0) != 0,
                all: (extractNumber(from: tireData["tirePressureWarningLampAll"]) ?? 0) != 0
            )
        }
        return nil
    }

    // MARK: - Error Handling

    func checkForKiaErrors(data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any],
              let errorCode: Int = extractNumber(from: status["errorCode"]),
              errorCode != 0 else { return }

        let errorMessage = status["errorMessage"] as? String ?? "Unknown Kia API error"
        let statusCode: Int = extractNumber(from: status["statusCode"]) ?? -1
        let errorType: Int = extractNumber(from: status["errorType"]) ?? -1
        let messageLower = errorMessage.lowercased()

        if statusCode == 1, errorType == 1, errorCode == 1,
           messageLower.contains("valid email") || messageLower.contains("invalid") ||
           messageLower.contains("credential") {
            throw APIError.invalidCredentials("Invalid username or password", apiName: apiName)
        }

        if errorCode == 1005 || errorCode == 1103 {
            throw APIError.invalidVehicleSession(errorMessage, apiName: apiName)
        }

        if errorCode == 1003,
           messageLower.contains("session key") || messageLower.contains("invalid") ||
           messageLower.contains("expired") {
            throw APIError.invalidCredentials("Session Key is either invalid or expired", apiName: apiName)
        }

        if errorCode == 9789 {
            throw APIError.kiaInvalidRequest(
                "Kia API is currently unsupported. " +
                "See https://github.com/schmidtwmark/BetterBlueKit/issues/7 for updates",
                apiName: apiName
            )
        }

        if errorCode == 429 {
            throw APIError.serverError("Rate limited", apiName: apiName)
        }

        if errorCode == 503 {
            throw APIError.serverError("Service unavailable", apiName: apiName)
        }
    }
}
