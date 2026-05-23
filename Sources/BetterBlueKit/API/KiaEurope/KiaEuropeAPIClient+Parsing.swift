//
//  KiaEuropeAPIClient+Parsing.swift
//  BetterBlueKit
//
//  Response parsing for the Kia Europe client. Reuses the
//  HyEuResponseKeyPathMap because CCS2 / legacy response shapes are
//  shared between Hyundai EU and Kia EU.
//

import Foundation

extension KiaEuropeAPIClient {

    package func parseAuthToken(from data: Data, isRefresh: Bool) throws -> AuthToken {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw APIError(
                message: "Failed to parse AuthToken response",
                apiName: apiName,
                errorType: .invalidCredentials
            )
        }

        let refreshToken: String = isRefresh
            ? (json["refresh_token"] as? String ?? configuration.refreshToken ?? "")
            : (configuration.refreshToken ?? "")

        return AuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    package func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let resMsg = json["resMsg"] as? [String: Any],
            let vehicleArray = resMsg["vehicles"] as? [[String: Any]]
        else {
            throw APIError.logError("Invalid vehicles response", apiName: apiName)
        }

        return vehicleArray.compactMap { vehicleData -> Vehicle? in
            guard let vehicleId = vehicleData["vehicleId"] as? String,
                  let vin = vehicleData["vin"] as? String,
                  let nickname = vehicleData["nickname"] as? String
                    ?? vehicleData["vehicleName"] as? String
            else { return nil }

            let fuelKindCode = vehicleData["type"] as? String ?? ""
            let fuelType: FuelType =
                switch fuelKindCode {
                case "E", "EV": .electric
                case "P", "PE": .phev
                default: .gas
                }
            let generation = 2
            let ccs2: Bool = getBoolFromJson(from: vehicleData, key: "ccuCCS2ProtocolSupport")

            return Vehicle(
                vin: vin,
                regId: vehicleId,
                model: nickname,
                accountId: accountId,
                fuelType: fuelType,
                generation: generation,
                odometer: Distance(length: 0, units: .kilometers),
                marketOptions: .kiaEurope(ccs2Supported: ccs2)
            )
        }
    }

    package func parseVehicleStatusResponse(_ data: Data, _ locationData: Data?, for vehicle: Vehicle)
        throws -> VehicleStatus {
        guard
            let statusJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let resMsg = statusJson["resMsg"] as? [String: Any]
        else {
            throw APIError.logError("Invalid status response", apiName: apiName)
        }

        var parkData: [String: Any] = [:]
        if let locationData {
            do {
                let parkJson = try JSONSerialization.jsonObject(with: locationData, options: []) as? [String: Any]
                parkData = parkJson?["resMsg"] as? [String: Any] ?? [:]
            } catch {
                BBLogger.warning(.api, "Failed to parse park data: \(error.localizedDescription)")
            }
        }

        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false
        let pathMap = HyEuResponseKeyPathMap(profile: ccs2 ? .ccs2 : .legacy)
        let vehicleData = getChildFromJson(from: resMsg, key: pathMap[.vehicleState])

        let syncDate = Date(
            timeIntervalSince1970: getDoubleFromJson(from: resMsg, key: pathMap[.syncDate]) / 1000
        )
        let odo = Distance(
            length: getDoubleFromJson(from: vehicleData, key: pathMap[.odo]),
            units: Distance.Units(1)
        )

        return VehicleStatus(
            vin: vehicle.vin,
            gasRange: nil,
            evStatus: vehicle.fuelType.hasElectricCapability
                ? parseEVStatus(from: vehicleData, pathMap: pathMap) : nil,
            location: parseLocation(from: vehicleData, park: parkData, pathMap: pathMap),
            lockStatus: parseLockStatus(from: vehicleData, pathMap: pathMap),
            climateStatus: parseClimateStatus(from: vehicleData, pathMap: pathMap),
            odometer: odo,
            syncDate: syncDate,
            battery12V: Int(getDoubleFromJson(from: vehicleData, key: pathMap[.battery12v])),
            doorOpen: parseDoorOpen(from: vehicleData, pathMap: pathMap),
            trunkOpen: getBoolFromJson(from: vehicleData, key: pathMap[.trunk]),
            hoodOpen: getBoolFromJson(from: vehicleData, key: pathMap[.hood]),
            tirePressureWarning: parseTirePressure(from: vehicleData, pathMap: pathMap)
        )
    }

    private func parseEVStatus(from vehicleState: [String: Any], pathMap: HyEuResponseKeyPathMap)
        -> VehicleStatus.EVStatus? {

        let batterySOC = getDoubleFromJson(from: vehicleState, key: pathMap[.soc])
        let remainChargeTime = getDoubleFromJson(from: vehicleState, key: pathMap[.chargeTime])
        let pluggedIn = getBoolFromJson(from: vehicleState, key: pathMap[.pluggedIn])
        let plugType: Int = extractNumber(from: getAnyFromJson(from: vehicleState,
                                                key: pathMap[.pluggedIn])) ?? 0
        let estimatedRange = getDoubleFromJson(from: vehicleState, key: pathMap[.rangeTotal])
        let driveUnit = Int(getDoubleFromJson(from: vehicleState, key: pathMap[.rangeUnit]))
        var targetAC: Double?
        var targetDC: Double?
        var isCharging: Bool
        if pathMap.apiProfile == .ccs2 {
            targetAC = getDoubleFromJson(from: vehicleState, key: pathMap[.targetAC])
            targetDC = getDoubleFromJson(from: vehicleState, key: pathMap[.targetDC])
            isCharging = remainChargeTime > 0
        } else {
            let targetSocList = getChildFromJson(from: vehicleState,
                                                 key: pathMap[.targetSocList]) as? [[String: Any]] ?? []
            for target in targetSocList {
                if let plugType = target["plugType"] as? Int,
                   let soc = target["targetSOClevel"] as? Double {
                    if plugType == 1 {
                        targetAC = soc
                    } else if plugType == 0 {
                        targetDC = soc
                    }
                }
            }
            isCharging = getBoolFromJson(from: vehicleState, key: pathMap[.isCharging])
        }
        // Pre-existing bug: `pathMap[.chargePower]` referenced a
        // non-existent enum case (the EU response keys split it
        // into Std + Fst). Match HyundaiEurope's parser, which
        // takes whichever of the two has a value.
        let chargePower = max(
            getDoubleFromJson(from: vehicleState, key: pathMap[.chargePowerStd]),
            getDoubleFromJson(from: vehicleState, key: pathMap[.chargePowerFst])
        )

        _ = pluggedIn // surfaced via plugType today; kept for future parity
        return VehicleStatus.EVStatus(
            charging: isCharging,
            chargeSpeed: chargePower,
            evRange: VehicleStatus.FuelRange(
                range: Distance(length: estimatedRange, units: Distance.Units(driveUnit)),
                percentage: batterySOC
            ),
            plugType: VehicleStatus.PlugType(fromBatteryPlugin: plugType),
            chargeTime: .seconds(60 * remainChargeTime),
            targetSocAC: targetAC,
            targetSocDC: targetDC
        )
    }

    private func parseDoorOpen(from vehicleState: [String: Any], pathMap: HyEuResponseKeyPathMap)
        -> VehicleStatus.DoorStatus? {
        guard getAnyFromJson(from: vehicleState, key: pathMap[.doorFrontLeft]) is Int else {
            return nil
        }
        return VehicleStatus.DoorStatus(
            frontLeft: getBoolFromJson(from: vehicleState, key: pathMap[.doorFrontLeft]),
            frontRight: getBoolFromJson(from: vehicleState, key: pathMap[.doorFrontRight]),
            backLeft: getBoolFromJson(from: vehicleState, key: pathMap[.doorRearLeft]),
            backRight: getBoolFromJson(from: vehicleState, key: pathMap[.doorRearRight])
        )
    }

    private func parseLockStatus(from vehicleState: [String: Any], pathMap: HyEuResponseKeyPathMap)
        -> VehicleStatus.LockStatus {
        if pathMap.apiProfile == .legacy {
            return VehicleStatus.LockStatus(
                locked: getBoolFromJson(from: vehicleState, key: pathMap[.lockStatus])
            )
        }
        let driver = getBoolFromJson(from: vehicleState, key: pathMap[.lock1L], inverted: true)
        let passenger = getBoolFromJson(from: vehicleState, key: pathMap[.lock1R], inverted: true)
        let backLeft = getBoolFromJson(from: vehicleState, key: pathMap[.lock2L], inverted: true)
        let backRight = getBoolFromJson(from: vehicleState, key: pathMap[.lock2R], inverted: true)
        return VehicleStatus.LockStatus(locked: driver && passenger && backLeft && backRight)
    }

    private func parseClimateStatus(from vehicleState: [String: Any], pathMap: HyEuResponseKeyPathMap)
        -> VehicleStatus.ClimateStatus {
        let temp = Temperature(
            units: getAnyFromJson(from: vehicleState, key: pathMap[.tempUnit]) as? Int ?? 0,
            value: getAnyFromJson(from: vehicleState, key: pathMap[.airTemp]) as? String
        )
        return VehicleStatus.ClimateStatus(
            defrostOn: getBoolFromJson(from: vehicleState, key: pathMap[.defrostOn]),
            airControlOn: (getAnyFromJson(from: vehicleState, key: pathMap[.airconSpeed]) as? Int ?? 0) > 0,
            steeringWheelHeatingOn: getBoolFromJson(from: vehicleState, key: pathMap[.steeringWheelHeatOn]),
            temperature: temp
        )
    }

    private func parseLocation(from vehicleState: [String: Any], park: [String: Any], pathMap: HyEuResponseKeyPathMap)
        -> VehicleStatus.Location {
        let locationDateString = getAnyFromJson(
            from: vehicleState, key: pathMap[.locationDate]) as? String ?? "20000101010000.000"
        let parkDateString = getAnyFromJson(
            from: park, key: pathMap[.parkDate]) as? String ?? "20000101020000"

        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let parkDate = dateFormatter.date(from: parkDateString) ?? Date(timeIntervalSince1970: 0)

        dateFormatter.timeZone = TimeZone.gmt
        dateFormatter.dateFormat = "yyyyMMddHHmmss.SSS"
        let locationDate = dateFormatter.date(from: locationDateString) ?? Date(timeIntervalSince1970: 0)

        if locationDate.compare(parkDate).rawValue <= 0 {
            return VehicleStatus.Location(
                latitude: getDoubleFromJson(from: park, key: pathMap[.parkLat]),
                longitude: getDoubleFromJson(from: park, key: pathMap[.parkLon])
            )
        }
        return VehicleStatus.Location(
            latitude: getDoubleFromJson(from: vehicleState, key: pathMap[.locationLat]),
            longitude: getDoubleFromJson(from: vehicleState, key: pathMap[.locationLon])
        )
    }

    private func parseTirePressure(from vehicleState: [String: Any], pathMap: HyEuResponseKeyPathMap)
        -> VehicleStatus.TirePressureWarning? {
        guard let all = getAnyFromJson(from: vehicleState, key: pathMap[.tpmsStatus]) else {
            return nil
        }
        return VehicleStatus.TirePressureWarning(
            frontLeft: getBoolFromJson(from: vehicleState, key: pathMap[.tpmsFrontLeft]),
            frontRight: getBoolFromJson(from: vehicleState, key: pathMap[.tpmsFrontRight]),
            rearLeft: getBoolFromJson(from: vehicleState, key: pathMap[.tpmsRearLeft]),
            rearRight: getBoolFromJson(from: vehicleState, key: pathMap[.tpmsRearRight]),
            all: (extractNumber(from: all) ?? 0) != 0
        )
    }

    // MARK: - JSON traversal helpers
    // (duplicated from HyundaiEuropeAPIClient+Parsing; left private to keep
    // the Kia EU surface independent. A future refactor could lift these
    // into a shared utility — out of scope for the Kia EU PR.)

    private func getBoolFromJson(from data: [String: Any], key keyString: String?, inverted: Bool = false) -> Bool {
        if keyString == nil || keyString!.isEmpty { return false }
        switch getAnyFromJson(from: data, key: keyString) {
        case let value as Bool:
            return inverted ? !value : value
        case let value as Int:
            return inverted ? value == 0 : value == 1
        case let value as String:
            let lower = value.lowercased()
            if inverted {
                return lower == "false" || lower == "0" || lower == "no"
            } else {
                return lower == "true" || lower == "1" || lower == "yes"
            }
        default: return false
        }
    }

    private func getDoubleFromJson(from data: [String: Any], key keyString: String?) -> Double {
        if keyString == nil || keyString!.isEmpty { return 0 }
        switch getAnyFromJson(from: data, key: keyString!) {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as String: return Double(value) ?? 0
        default: return 0
        }
    }

    private func getChildFromJson(from data: [String: Any], key keyString: String?) -> [String: Any] {
        if keyString == nil || keyString!.isEmpty { return data }
        var current = data
        for key in keyString!.split(separator: ".") {
            if let value = current[String(key)] as? [String: Any] {
                current = value
            }
        }
        return current
    }

    private func getAnyFromJson(from data: [String: Any], key keyString: String?) -> Any? {
        if keyString == nil || keyString!.isEmpty { return nil }
        var current = data
        for key in keyString!.split(separator: ".") {
            if let value = current[String(key)] as? [String: Any] {
                current = value
            } else {
                return current[String(key)]
            }
        }
        return nil
    }
}
