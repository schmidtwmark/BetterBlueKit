//
//  HyundaiCanada+Parsing.swift
//  BetterBlueKit
//
//  Hyundai Canada parsing helpers
//

import Foundation

extension HyundaiAPIEndpointProviderCanada {
    func parseCanadaLoginResponse(_ data: Data, headers _: [String: String]) throws -> AuthToken {
        let json = try parseCanadaResponse(data, context: "login")
        guard let result = json["result"] as? [String: Any],
              let token = result["token"] as? [String: Any],
              let accessToken = token["accessToken"] as? String else {
            throw APIError.logError(
                "Invalid Canada login response",
                apiName: "HyundaiAPI"
            )
        }

        let expiresIn: Int = extractNumber(from: token["expireIn"]) ?? 3600
        let refreshToken = token["refreshToken"] as? String ?? ""
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))

        return AuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            pin: pin,
            authCookie: cloudFlareCookie
        )
    }

    func parseCanadaVehiclesResponse(_ data: Data) throws -> [Vehicle] {
        let json = try parseCanadaResponse(data, context: "vehicles")
        guard let result = json["result"] as? [String: Any],
              let vehicles = result["vehicles"] as? [[String: Any]] else {
            throw APIError.logError(
                "Invalid Canada vehicles response",
                apiName: "HyundaiAPI"
            )
        }

        return vehicles.compactMap { vehicleData in
            guard let vin = vehicleData["vin"] as? String else {
                return nil
            }

            let regId =
                vehicleData["vehicleId"] as? String ??
                vehicleData["regid"] as? String ??
                vehicleData["registrationId"] as? String ??
                vin
            let nickname =
                vehicleData["nickName"] as? String ??
                vehicleData["modelName"] as? String ??
                vehicleData["model"] as? String ??
                vin

            let generation: Int =
                extractNumber(from: vehicleData["vehicleGeneration"]) ??
                extractNumber(from: vehicleData["genType"]) ?? 3

            let odometerObject = vehicleData["odometer"] as? [String: Any] ?? [:]
            let odometerValue: Double =
                extractNumber(from: vehicleData["odometer"]) ??
                extractNumber(from: odometerObject["value"]) ?? 0
            let isElectric = detectElectricVehicle(from: vehicleData)

            return Vehicle(
                vin: vin,
                regId: regId,
                model: nickname,
                accountId: accountId,
                isElectric: isElectric,
                generation: generation,
                odometer: Distance(length: odometerValue, units: .kilometers)
            )
        }
    }

    func parseCanadaVehicleStatusResponse(_ data: Data, for vehicle: Vehicle) throws -> VehicleStatus {
        let json = try parseCanadaResponse(data, context: "status")
        guard let result = json["result"] as? [String: Any] else {
            throw APIError.logError(
                "Invalid Canada status response",
                apiName: "HyundaiAPI"
            )
        }

        let statusData =
            result["status"] as? [String: Any] ??
            result["vehicleStatus"] as? [String: Any] ??
            [:]
        let vehicleData = result["vehicle"] as? [String: Any] ?? [:]
        let statusOdometer = statusData["odometer"] as? [String: Any] ?? [:]
        let vehicleOdometer = vehicleData["odometer"] as? [String: Any] ?? [:]

        let odometer: Distance? = {
            let value: Double? =
                extractNumber(from: statusData["odometer"]) ??
                extractNumber(from: statusOdometer["value"]) ??
                extractNumber(from: vehicleData["odometer"]) ??
                extractNumber(from: vehicleOdometer["value"])
            guard let value else { return vehicle.odometer }
            return Distance(length: value, units: .kilometers)
        }()

        return VehicleStatus(
            vin: vehicle.vin,
            gasRange: parseCanadaGasRange(from: statusData, vehicle: vehicle),
            evStatus: parseCanadaEVStatus(from: statusData, vehicle: vehicle),
            location: parseCanadaLocation(from: statusData),
            lockStatus: VehicleStatus.LockStatus(locked: statusData["doorLock"] as? Bool),
            climateStatus: parseCanadaClimateStatus(from: statusData),
            odometer: odometer,
            syncDate: parseCanadaSyncDate(from: statusData),
            battery12V: parseCanadaBattery12V(from: statusData),
            doorOpen: parseCanadaDoorStatus(from: statusData),
            trunkOpen: parseCanadaTrunkOpen(from: statusData),
            hoodOpen: parseCanadaHoodOpen(from: statusData),
            tirePressureWarning: parseCanadaTirePressureWarning(from: statusData)
        )
    }

    func parseCanadaCommandResponse(_ data: Data) throws {
        _ = try parseCanadaResponse(data, context: "command")
    }

    private func detectElectricVehicle(from vehicleData: [String: Any]) -> Bool {
        if let evStatus = vehicleData["evStatus"] as? String {
            return evStatus.uppercased().hasPrefix("E")
        }
        if let fuelType: Int = extractNumber(from: vehicleData["fuelType"]) {
            return fuelType != 3
        }
        if let modelName = (vehicleData["modelName"] as? String)?.lowercased() {
            return modelName.contains("ev") || modelName.contains("electric")
        }
        return true
    }

    private func parseCanadaEVStatus(
        from statusData: [String: Any],
        vehicle: Vehicle
    ) -> VehicleStatus.EVStatus? {
        guard vehicle.isElectric,
              let evStatusData = statusData["evStatus"] as? [String: Any] else { return nil }

        let batteryStatus: Double = extractNumber(from: evStatusData["batteryStatus"]) ?? 0
        let chargeTimeMinutes = parseChargeTimeMinutes(from: evStatusData)
        let batteryPlugin: Int = extractNumber(from: evStatusData["batteryPlugin"]) ?? 0
        let charging = evStatusData["batteryCharge"] as? Bool ?? false
        let chargeSpeed = parseChargeSpeed(from: evStatusData)
        let range = parseCanadaEVRange(from: evStatusData) ?? Distance(length: 0, units: .kilometers)
        let (targetSocAC, targetSocDC) = parseTargetSOCs(from: evStatusData)

        return VehicleStatus.EVStatus(
            charging: charging,
            chargeSpeed: chargeSpeed,
            evRange: VehicleStatus.FuelRange(range: range, percentage: batteryStatus),
            plugType: VehicleStatus.PlugType(fromBatteryPlugin: batteryPlugin),
            chargeTime: .seconds(60 * chargeTimeMinutes),
            targetSocAC: targetSocAC,
            targetSocDC: targetSocDC
        )
    }

    private func parseCanadaGasRange(
        from statusData: [String: Any],
        vehicle: Vehicle
    ) -> VehicleStatus.FuelRange? {
        guard !vehicle.isElectric,
              let fuelLevel: Double = extractNumber(from: statusData["fuelLevel"]) else {
            return nil
        }

        if let distanceToEmpty = statusData["distanceToEmpty"] as? [String: Any],
           let value: Double = extractNumber(from: distanceToEmpty["value"]) {
            let unit: Int = extractNumber(from: distanceToEmpty["unit"]) ?? 1
            return VehicleStatus.FuelRange(
                range: Distance(length: value, units: Distance.Units(unit)),
                percentage: fuelLevel
            )
        }

        if let evStatus = statusData["evStatus"] as? [String: Any],
           let drvDistance = evStatus["drvDistance"] as? [[String: Any]] {
            for entry in drvDistance {
                let rangeByFuel = entry["rangeByFuel"] as? [String: Any] ?? [:]
                let totalRange = rangeByFuel["totalAvailableRange"] as? [String: Any] ?? [:]
                if let value: Double = extractNumber(from: totalRange["value"]) {
                    let unit: Int = extractNumber(from: totalRange["unit"]) ?? 1
                    return VehicleStatus.FuelRange(
                        range: Distance(length: value, units: Distance.Units(unit)),
                        percentage: fuelLevel
                    )
                }
            }
        }

        return nil
    }

    private func parseCanadaEVRange(from evStatusData: [String: Any]) -> Distance? {
        let drvDistance = evStatusData["drvDistance"] as? [[String: Any]] ?? []
        for entry in drvDistance {
            let rangeByFuel = entry["rangeByFuel"] as? [String: Any] ?? [:]
            let evModeRange = rangeByFuel["evModeRange"] as? [String: Any]
            let totalRange = rangeByFuel["totalAvailableRange"] as? [String: Any]
            let preferred = evModeRange ?? totalRange ?? [:]
            if let value: Double = extractNumber(from: preferred["value"]) {
                let unit: Int = extractNumber(from: preferred["unit"]) ?? 1
                return Distance(length: value, units: Distance.Units(unit))
            }
        }
        return nil
    }

    private func parseChargeSpeed(from evStatusData: [String: Any]) -> Double {
        if let batteryPower = evStatusData["batteryPower"] as? [String: Any] {
            let fast: Double = extractNumber(from: batteryPower["batteryFstChrgPower"]) ?? 0
            let standard: Double = extractNumber(from: batteryPower["batteryStndChrgPower"]) ?? 0
            return max(fast, standard)
        }
        let fast: Double = extractNumber(from: evStatusData["batteryFstChrgPower"]) ?? 0
        let standard: Double = extractNumber(from: evStatusData["batteryStndChrgPower"]) ?? 0
        return max(fast, standard)
    }

    private func parseChargeTimeMinutes(from evStatusData: [String: Any]) -> Int {
        let remainTime2 = evStatusData["remainTime2"] as? [String: Any] ?? [:]
        let atc = remainTime2["atc"] as? [String: Any] ?? [:]
        if let value: Int = extractNumber(from: atc["value"]) {
            return value
        }
        let remainChargeTime = evStatusData["remainChargeTime"] as? [[String: Any]] ?? []
        return extractNumber(from: remainChargeTime.first?["value"]) ?? 0
    }

    private func parseTargetSOCs(from evStatusData: [String: Any]) -> (Double?, Double?) {
        let reserveChargeInfos = evStatusData["reservChargeInfos"] as? [String: Any] ?? [:]
        let targetSocList = reserveChargeInfos["targetSOClist"] as? [[String: Any]] ??
            evStatusData["targetSOC"] as? [[String: Any]] ?? []

        var targetSocAC: Double?
        var targetSocDC: Double?
        for target in targetSocList {
            if let plugType = target["plugType"] as? Int,
               let soc: Double = extractNumber(from: target["targetSOClevel"]) {
                if plugType == 1 {
                    targetSocAC = soc
                } else if plugType == 0 {
                    targetSocDC = soc
                }
            }
        }
        return (targetSocAC, targetSocDC)
    }

    private func parseCanadaLocation(from statusData: [String: Any]) -> VehicleStatus.Location {
        let vehicleLocation = statusData["vehicleLocation"] as? [String: Any] ?? [:]
        let coord = vehicleLocation["coord"] as? [String: Any] ?? statusData["coord"] as? [String: Any] ?? [:]
        return VehicleStatus.Location(
            latitude: extractNumber(from: coord["lat"]) ?? 0,
            longitude: extractNumber(from: coord["lon"]) ?? 0
        )
    }

    private func parseCanadaClimateStatus(from statusData: [String: Any]) -> VehicleStatus.ClimateStatus {
        let airTemp = statusData["airTemp"] as? [String: Any] ?? [:]
        let temperatureValue = stringify(airTemp["value"])

        return VehicleStatus.ClimateStatus(
            defrostOn: statusData["defrost"] as? Bool ?? false,
            airControlOn: (statusData["airCtrlOn"] as? Bool) ?? (statusData["airCtrl"] as? Bool) ?? false,
            steeringWheelHeatingOn: (extractNumber(from: statusData["steerWheelHeat"]) ?? 0) != 0,
            temperature: Temperature(
                units: extractNumber(from: airTemp["unit"]),
                value: temperatureValue
            )
        )
    }

    private func parseCanadaSyncDate(from statusData: [String: Any]) -> Date? {
        if let dateTime = statusData["dateTime"] as? String,
           let isoDate = ISO8601DateFormatter().date(from: dateTime) {
            return isoDate
        }
        if let lastStatusDate = statusData["lastStatusDate"] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMddHHmmss"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.date(from: lastStatusDate)
        }
        return nil
    }

    private func parseCanadaBattery12V(from statusData: [String: Any]) -> Int? {
        if let battery = statusData["battery"] as? [String: Any] {
            return extractNumber(from: battery["batSoc"])
        }
        return nil
    }

    private func parseCanadaDoorStatus(from statusData: [String: Any]) -> VehicleStatus.DoorStatus? {
        let doorData =
            statusData["doorOpen"] as? [String: Any] ??
            statusData["doorStatus"] as? [String: Any] ?? [:]
        if doorData.isEmpty {
            return nil
        }

        let frontLeft: Int = extractNumber(from: doorData["frontLeft"]) ?? 0
        let frontRight: Int = extractNumber(from: doorData["frontRight"]) ?? 0
        let backLeft: Int = extractNumber(from: doorData["backLeft"]) ?? 0
        let backRight: Int = extractNumber(from: doorData["backRight"]) ?? 0

        return VehicleStatus.DoorStatus(
            frontLeft: frontLeft != 0,
            frontRight: frontRight != 0,
            backLeft: backLeft != 0,
            backRight: backRight != 0
        )
    }

    private func parseCanadaTrunkOpen(from statusData: [String: Any]) -> Bool? {
        if let trunk = statusData["trunkOpen"] as? Bool {
            return trunk
        }
        let doorStatus = statusData["doorStatus"] as? [String: Any] ?? [:]
        if let trunkValue: Int = extractNumber(from: doorStatus["trunk"]) {
            return trunkValue != 0
        }
        return nil
    }

    private func parseCanadaHoodOpen(from statusData: [String: Any]) -> Bool? {
        if let hood = statusData["hoodOpen"] as? Bool {
            return hood
        }
        let doorStatus = statusData["doorStatus"] as? [String: Any] ?? [:]
        if let hoodValue: Int = extractNumber(from: doorStatus["hood"]) {
            return hoodValue != 0
        }
        return nil
    }

    private func parseCanadaTirePressureWarning(
        from statusData: [String: Any]
    ) -> VehicleStatus.TirePressureWarning? {
        guard let tireData = statusData["tirePressureLamp"] as? [String: Any] else {
            return nil
        }

        let all: Int =
            extractNumber(from: tireData["tirePressureWarningLampAll"]) ??
            extractNumber(from: tireData["all"]) ?? 0
        let frontLeft: Int =
            extractNumber(from: tireData["tirePressureWarningLampFrontLeft"]) ??
            extractNumber(from: tireData["frontLeft"]) ?? 0
        let frontRight: Int =
            extractNumber(from: tireData["tirePressureWarningLampFrontRight"]) ??
            extractNumber(from: tireData["frontRight"]) ?? 0
        let rearLeft: Int =
            extractNumber(from: tireData["tirePressureWarningLampRearLeft"]) ??
            extractNumber(from: tireData["rearLeft"]) ?? 0
        let rearRight: Int =
            extractNumber(from: tireData["tirePressureWarningLampRearRight"]) ??
            extractNumber(from: tireData["rearRight"]) ?? 0

        return VehicleStatus.TirePressureWarning(
            frontLeft: frontLeft != 0,
            frontRight: frontRight != 0,
            rearLeft: rearLeft != 0,
            rearRight: rearRight != 0,
            all: all != 0
        )
    }

    private func stringify(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }
}
