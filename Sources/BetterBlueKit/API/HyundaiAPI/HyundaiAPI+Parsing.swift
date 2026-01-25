//
//  HyundaiAPI+Parsing.swift
//  BetterBlueKit
//
//  Created by Mark Schmidt on 12/26/25.
//

import Foundation

extension HyundaiAPIEndpointProvider {
    public func parseLoginResponse(_ data: Data, headers _: [String: String]) throws -> AuthToken {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresInString = json["expires_in"] as? String,
              let expiresIn = Int(expiresInString)
        else {
            throw APIError.logError(
                "Invalid login response for \(username): " +
                    "\(String(data: data, encoding: .utf8) ?? "No data")",
                apiName: "HyundaiAPI",
            )
        }

        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        BBLogger.info(.auth, "HyundaiAPI: Authentication completed successfully for user \(username)")
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
            throw APIError.logError(
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
        let battery12V = parseBattery12V(from: statusData)
        let doorOpen = parseDoorOpen(from: statusData)
        let trunkOpen = statusData["trunkOpen"] as? Bool
        let hoodOpen = statusData["hoodOpen"] as? Bool
        let tirePressureWarning = parseTirePressureWarning(from: statusData)

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
            doorOpen: doorOpen,
            trunkOpen: trunkOpen,
            hoodOpen: hoodOpen,
            tirePressureWarning: tirePressureWarning
        )
    }

    private func extractStatusData(from data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusData = json["vehicleStatus"] as? [String: Any]
        else {
            throw APIError.logError(
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
        let remainTime2 = evStatusData["remainTime2"] as? [String: Any] ?? [:]
        let atc = remainTime2["atc"] as? [String: Any] ?? [:]
        let chargeTimeMinutes = extractNumber(from: atc["value"]) ?? 0

        let batteryPlugin: Int = extractNumber(from: evStatusData["batteryPlugin"]) ?? 0

        // Extract target SOC values for AC and DC charging (plugType 0 = AC, plugType 1 = DC)
        let reserveChargeInfos = evStatusData["reservChargeInfos"] as? [String: Any] ?? [:]
        let targetSocList = reserveChargeInfos["targetSOClist"] as? [[String: Any]] ?? []
        var targetSocAC: Double?
        var targetSocDC: Double?

        for target in targetSocList {
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
            evRange: VehicleStatus.FuelRange(range: evRange, percentage: fuelPercentage),
            plugType: VehicleStatus.PlugType(fromBatteryPlugin: batteryPlugin),
            chargeTime: .seconds(60 * chargeTimeMinutes),
            targetSocAC: targetSocAC,
            targetSocDC: targetSocDC
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

    private func parseBattery12V(from statusData: [String: Any]) -> Int? {
        guard let batteryData = statusData["battery"] as? [String: Any],
              let batSoc: Int = extractNumber(from: batteryData["batSoc"]) else { return nil }
        return batSoc
    }

    private func parseDoorOpen(from statusData: [String: Any]) -> VehicleStatus.DoorStatus? {
        guard let doorData = statusData["doorOpen"] as? [String: Any] else { return nil }
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

    private func parseTirePressureWarning(from statusData: [String: Any]) -> VehicleStatus.TirePressureWarning? {
        guard let tireData = statusData["tirePressureLamp"] as? [String: Any] else { return nil }
        let all: Int = extractNumber(from: tireData["tirePressureWarningLampAll"]) ?? 0
        let frontLeft: Int = extractNumber(from: tireData["tirePressureWarningLampFrontLeft"]) ?? 0
        let frontRight: Int = extractNumber(from: tireData["tirePressureWarningLampFrontRight"]) ?? 0
        let rearLeft: Int = extractNumber(from: tireData["tirePressureWarningLampRearLeft"]) ?? 0
        let rearRight: Int = extractNumber(from: tireData["tirePressureWarningLampRearRight"]) ?? 0

        return VehicleStatus.TirePressureWarning(
            frontLeft: frontLeft != 0,
            frontRight: frontRight != 0,
            rearLeft: rearLeft != 0,
            rearRight: rearRight != 0,
            all: all != 0
        )
    }

    public func parseCommandResponse(_ data: Data) throws {
        // Check for PIN validation errors even with 200 status code
        if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check for invalid PIN response
            if let isBlueLinkServicePinValid = jsonResponse["isBlueLinkServicePinValid"] as? String,
               isBlueLinkServicePinValid == "invalid" {
                let remainingAttempts = jsonResponse["remainingAttemptCount"] as? String ?? "unknown"
                let errorMessage = "Invalid PIN, \(remainingAttempts) attempts remaining"
                throw APIError.invalidPin(errorMessage, apiName: "HyundaiAPI")
            }
        }
    }
}
