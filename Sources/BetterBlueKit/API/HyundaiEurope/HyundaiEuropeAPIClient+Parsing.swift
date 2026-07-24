//
//  HyundaiEuropeAPIClient+Parsing.swift
//  BetterBlueKit
//
//  Response parsing for Hyundai Europe API
//

import Foundation

// MARK: - Response Parsing

extension HyundaiEuropeAPIClient {

    package func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let resMsg = json["resMsg"] as? [String: Any],
            let vehicleArray = resMsg["vehicles"] as? [[String: Any]]
        else {
            throw APIError.logError( "Invalid vehicles response", apiName: apiName )
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
            let generation = 2  // always 2 there is no such attribute
            let ccs2: Bool = getBoolFromJson( from: vehicleData, key: "ccuCCS2ProtocolSupport" )

            return Vehicle(
                vin: vin,
                regId: vehicleId,
                model: nickname,
                accountId: accountId,
                fuelType: fuelType,
                generation: generation,
                odometer: Distance(length: 0, units: .kilometers),
                marketOptions: .hyundaiEurope(ccs2Supported: ccs2)
            )
        }
    }

    package func parseVehicleStatusResponse( _ data: Data, _ locationData: Data?, for vehicle: Vehicle )
    throws -> VehicleStatus {
        guard
            let statusJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let resMsg = statusJson["resMsg"] as? [String: Any]
        else {
            throw APIError.logError("Invalid status response", apiName: apiName)
        }

        // park data are optional -> location from vehicle status is used in case of error
        var parkData: [String: Any] = [:]
        if let locationData = locationData,
           let parkJson = try? JSONSerialization.jsonObject(with: locationData, options: []) as? [String: Any] {
            parkData = parkJson["resMsg"] as? [String: Any] ?? [:]
        } else {
            BBLogger.warning(.api, "Failed to parse park data using location from vehicle status" )
            parkData = [:]
        }

        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false
        let pathMap = HyEuResponseKeyPathMap(profile: ccs2 ? .ccs2 : .legacy)

        let vehicleData = getChildFromJson( from: resMsg, key: pathMap[.vehicleState] )

        // get datetime string from response (utc) and transform it to date
        let syncDate = BluelinkDateParser.parse(getAnyFromJson( from: resMsg,
                                                                key: pathMap[.syncDate] ) as? String,
                                                timeZone: TimeZone(identifier: "Europe/Berlin"))
        // get odometer from drivetrain data
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
            tirePressureWarning: parseTirePressure(from: vehicleData, pathMap: pathMap),
            engineOn: getBoolFromJson(from: vehicleData, key: pathMap[.engineOn])
        )
    }

    package func parseAuthToken(from data: Data, isRefresh: Bool) throws -> AuthToken {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rToken = isRefresh ? json["refresh_token"] as? String : configuration.refreshToken,
              let expiresIn = json["expires_in"] as? Int,
              let accessToken = json["access_token"] as? String else {
            throw APIError(message: "Failed to parse AuthToken info", apiName: apiName, errorType: .invalidCredentials)
        }

        return AuthToken(
                accessToken: accessToken,
                refreshToken: rToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
            )
    }

    private func parseEVStatus(from vehicleState: [String: Any], pathMap: HyEuResponseKeyPathMap)
        -> VehicleStatus.EVStatus? {

        let batterySOC = getDoubleFromJson(from: vehicleState, key: pathMap[.soc])
        let remainChargeTime = getDoubleFromJson(from: vehicleState, key: pathMap[.chargeTime])
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
            let targetSocList = getAnyFromJson(from: vehicleState, key: pathMap[.targetSocList])
            let socList = targetSocList as? [[String: Any]] ?? []
            for target in socList {
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
        let chargePower = max(getDoubleFromJson(from: vehicleState, key: pathMap[.chargePowerStd]),
                              getDoubleFromJson(from: vehicleState, key: pathMap[.chargePowerFst]))

        return VehicleStatus.EVStatus(
            charging: isCharging,
            chargeSpeed: chargePower,
            evRange: VehicleStatus.FuelRange(
                range: Distance(
                    length: estimatedRange,
                    units: Distance.Units(driveUnit)
                ),
                percentage: batterySOC
            ),
            plugType: VehicleStatus.PlugType(fromBatteryPlugin: plugType),
            chargeTime: .seconds(60 * remainChargeTime),
            targetSocAC: targetAC,
            targetSocDC: targetDC
        )
    }

    private func parseDoorOpen(
        from vehicleState: [String: Any],
        pathMap: HyEuResponseKeyPathMap
    ) -> VehicleStatus.DoorStatus? {
        guard
            getAnyFromJson(from: vehicleState, key: pathMap[.doorFrontLeft]) is Int
        else { return nil }
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
        let driver = getBoolFromJson(
            from: vehicleState,
            key: pathMap[.lock1L],
            inverted: true
        )
        let passanger = getBoolFromJson(
            from: vehicleState,
            key: pathMap[.lock1R],
            inverted: true
        )
        let backLeft = getBoolFromJson(
            from: vehicleState,
            key: pathMap[.lock2L],
            inverted: true
        )
        let backRight = getBoolFromJson(
            from: vehicleState,
            key: pathMap[.lock2R],
            inverted: true
        )
        return VehicleStatus.LockStatus(
            locked: driver && passanger && backLeft && backRight
        )
    }

    private func parseClimateStatus(from vehicleState: [String: Any], pathMap: HyEuResponseKeyPathMap)
    -> VehicleStatus.ClimateStatus {

        let temp = Temperature(
            units: getAnyFromJson(from: vehicleState, key: pathMap[.tempUnit]) as? Int ?? 0,
            value: getAnyFromJson(from: vehicleState, key: pathMap[.airTemp]) as? String ?? "",
        )

        var airConOn: Bool = false
        if pathMap.apiProfile == .legacy {
            airConOn = getBoolFromJson(from: vehicleState, key: pathMap[.airControlOn])
        } else {
            airConOn = getAnyFromJson(from: vehicleState, key: pathMap[.airconSpeed]) as? Int ?? 0 > 0
        }

        return VehicleStatus.ClimateStatus(
            defrostOn: getBoolFromJson(from: vehicleState, key: pathMap[.defrostOn]),
            airControlOn: airConOn,
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

        /*
         * Workaround because CCS2 location in status is currently stale
         * normally we would just use coords from vehicleState without time check
         */

        // park date is always in exact Zone
        let parkDate = BluelinkDateParser.parse(parkDateString, timeZone: TimeZone.current)

        /*
         * status location is currently in UTC for ccs2 cars
         * "Offset" value seems to be a hint what timezone the car is in
         */
        let locationTimeZone = pathMap.apiProfile == .legacy ? TimeZone(identifier: "Europe/Berlin") : TimeZone.gmt
        let locationDate = BluelinkDateParser.parse(locationDateString, timeZone: locationTimeZone)

        // Two candidate sources: the /location/park endpoint and the
        // location embedded in the status response. Either can be empty —
        // park returns no coordinates when the car has no recent park
        // event, and the status-embedded location is often stale/missing.
        let parkLocation = VehicleStatus.Location(
            latitude: getDoubleFromJson(from: park, key: pathMap[.parkLat]),
            longitude: getDoubleFromJson(from: park, key: pathMap[.parkLon])
        )
        let statusLocation = VehicleStatus.Location(
            latitude: getDoubleFromJson(from: vehicleState, key: pathMap[.locationLat]),
            longitude: getDoubleFromJson(from: vehicleState, key: pathMap[.locationLon])
        )

        // Prefer the park endpoint when it has coordinates and is at least
        // as recent as the (often stale) status location. Fall back to
        // whichever source actually carries coordinates so a missing park
        // event no longer drops the location entirely.
        let parkIsNewer = (parkDate != nil && locationDate != nil)
            ? locationDate!.compare(parkDate!).rawValue <= 0
            : parkLocation.hasCoordinates
        if parkIsNewer, parkLocation.hasCoordinates {
            return parkLocation
        }
        if statusLocation.hasCoordinates {
            return statusLocation
        }
        return parkLocation.hasCoordinates ? parkLocation : statusLocation
    }

    private func parseTirePressure(from vehicleState: [String: Any], pathMap: HyEuResponseKeyPathMap)
    -> VehicleStatus.TirePressureWarning? {
        guard
            let all = getAnyFromJson(from: vehicleState, key: pathMap[.tpmsStatus])
        else { return nil }
        return VehicleStatus.TirePressureWarning(
            frontLeft: getBoolFromJson(from: vehicleState, key: pathMap[.tpmsFrontLeft]),
            frontRight: getBoolFromJson(from: vehicleState, key: pathMap[.tpmsFrontRight]),
            rearLeft: getBoolFromJson(from: vehicleState, key: pathMap[.tpmsRearLeft]),
            rearRight: getBoolFromJson(from: vehicleState, key: pathMap[.tpmsRearRight]),
            all: (extractNumber(from: all) ?? 0) != 0
        )
    }

    private func getBoolFromJson(from data: [String: Any], key keyString: String?, inverted: Bool = false) -> Bool {
        if keyString == nil || keyString!.isEmpty { return false }
        switch getAnyFromJson(from: data, key: keyString) {
        case let value as Bool:
            if inverted { return !value } else { return value }
        case let value as Int:
            if inverted { return value == 0 } else { return value == 1 }
        case let value as String:
            if inverted {
                return value.lowercased() == "false"
                    || value.lowercased() == "0"
                    || value.lowercased() == "no"
            } else {
                return value.lowercased() == "true"
                    || value.lowercased() == "1"
                    || value.lowercased() == "yes"
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
        for (key) in keyString!.split(separator: ".") {
            if let value = current[String(key)] as? [String: Any] {
                current = value
            }
        }
        return current
    }

    private func getAnyFromJson(from data: [String: Any], key keyString: String?) -> Any? {
        guard let keyString, !keyString.isEmpty else { return nil }

        var current: Any = data

        for key in keyString.split(separator: ".") {
            let keyStr = String(key)

            if let dict = current as? [String: Any] {
                // default dictionary access
                guard let next = dict[keyStr] else { return nil }
                current = next

            } else if let array = current as? [Any] {
                // array access with index ("drvDistance.0.rangeByFuel")
                guard let index = Int(keyStr), array.indices.contains(index) else { return nil }
                current = array[index]

            } else {
                // no Dict or Array → no further child found
                return nil
            }
        }

        return current
    }

    package func parseEVTripDetailsResponse(_ data: Data, vehicle: Vehicle) throws -> [EVTripDetail] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let resMsg = json["resMsg"] as? [String: Any],
            let drivingInfoDetail = resMsg["drivingInfoDetail"] as? [[String: Any]]
        else {
            throw APIError(message: "Failed to parse EU trip details", apiName: apiName)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd"

        return drivingInfoDetail.compactMap { tripData -> EVTripDetail? in
            guard let dateString = tripData["drivingDate"] as? String,
                let startDate = dateFormatter.date(from: dateString)
            else {
                return nil
            }

            let totalPwrCsp = tripData["totalPwrCsp"] as? Int ?? 0
            let motorPwrCsp = tripData["motorPwrCsp"] as? Int ?? 0
            let climatePwrCsp = tripData["climatePwrCsp"] as? Int ?? 0
            let eDPwrCsp = tripData["eDPwrCsp"] as? Int ?? 0
            let batteryMgPwrCsp = tripData["batteryMgPwrCsp"] as? Int ?? 0
            let regenPwr = tripData["regenPwr"] as? Int ?? 0

            // calculativeOdo arrives as a plain number on current backends,
            // but sibling CCS payloads wrap distances as {value, unit} dicts —
            // handle both, honoring the response's unit code when present and
            // defaulting to kilometers (the EU fleet's native unit).
            let odoValue: Double
            let odoUnits: Distance.Units
            if let odoDict = tripData["calculativeOdo"] as? [String: Any] {
                odoValue = getDoubleFromJson(from: odoDict, key: "value")
                odoUnits = Distance.Units(odoDict["unit"] as? Int ?? 1)
            } else {
                odoValue = getDoubleFromJson(from: tripData, key: "calculativeOdo")
                odoUnits = Distance.Units(1)
            }

            return EVTripDetail(
                distance: Distance(length: odoValue, units: odoUnits),
                odometer: Distance(length: 0, units: odoUnits),  // Not provided by EU /drvhistory
                accessoriesEnergy: eDPwrCsp,
                totalEnergyUsed: totalPwrCsp,
                regenEnergy: regenPwr,
                climateEnergy: climatePwrCsp,
                drivetrainEnergy: motorPwrCsp,
                batteryCareEnergy: batteryMgPwrCsp,
                startDate: startDate,
                durationSeconds: 0,  // Populated later from /tripinfo
                avgSpeed: 0,  // Populated later from /tripinfo
                maxSpeed: 0  // Populated later from /tripinfo
            )
        }
    }

    package func parseIndividualTripsResponse(_ data: Data) throws -> [EVTripInfo] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let resMsg = json["resMsg"] as? [String: Any],
            let dayTripList = resMsg["dayTripList"] as? [[String: Any]]
        else {
            throw APIError(message: "Failed to parse EU individual trips", apiName: apiName)
        }

        var allTrips: [EVTripInfo] = []

        for dayTrip in dayTripList {
            let date = dayTrip["tripDay"] as? String ?? dayTrip["date"] as? String ?? ""
            
            guard let tripList = dayTrip["tripList"] as? [[String: Any]] else {
                continue
            }
            
            for tripData in tripList {
                let hhmmss = tripData["tripTime"] as? String ?? tripData["hhmmss"] as? String ?? ""
                let driveTime = tripData["tripDrvTime"] as? Int ?? tripData["drive_time"] as? Int ?? 0
                let idleTime = tripData["tripIdleTime"] as? Int ?? tripData["idle_time"] as? Int ?? 0
                let distance = getDoubleFromJson(from: tripData, key: "tripDist")
                let avgSpeed = getDoubleFromJson(from: tripData, key: "tripAvgSpeed")
                let maxSpeed = getDoubleFromJson(from: tripData, key: "tripMaxSpeed")

                allTrips.append(EVTripInfo(
                    date: date,
                    hhmmss: hhmmss,
                    driveTimeMinutes: driveTime,
                    idleTimeMinutes: idleTime,
                    distance: distance,
                    avgSpeed: avgSpeed,
                    maxSpeed: maxSpeed
                ))
            }
        }

        return allTrips
    }
}
