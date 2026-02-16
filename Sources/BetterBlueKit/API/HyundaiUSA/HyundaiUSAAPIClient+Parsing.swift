//
//  HyundaiUSAAPIClient+Parsing.swift
//  BetterBlueKit
//
//  Response parsing for Hyundai USA API
//

import Foundation

// MARK: - Response Parsing

extension HyundaiUSAAPIClient {

    func parseLoginResponse(_ data: Data) throws -> AuthToken {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresInString = json["expires_in"] as? String,
              let expiresIn = Int(expiresInString) else {
            let responseText = String(data: data, encoding: .utf8) ?? ""
            throw APIError.logError("Invalid login response: \(responseText)", apiName: apiName)
        }

        BBLogger.info(.auth, "HyundaiUSA: Login successful")
        return AuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            pin: pin
        )
    }

    func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] {
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

    func parseVehicleStatusResponse(_ data: Data, for vehicle: Vehicle) throws -> VehicleStatus {
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

    func parseCommandResponse(_ data: Data) throws {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let pinValid = json["isBlueLinkServicePinValid"] as? String,
           pinValid == "invalid" {
            let remaining = json["remainingAttemptCount"] as? String ?? "unknown"
            throw APIError.invalidPin("Invalid PIN, \(remaining) attempts remaining", apiName: apiName)
        }
    }

    func parseEVTripDetailsResponse(_ data: Data) throws -> [EVTripDetail] {
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
                if plugType == 1 { targetSocAC = soc } else if plugType == 0 { targetSocDC = soc }
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
