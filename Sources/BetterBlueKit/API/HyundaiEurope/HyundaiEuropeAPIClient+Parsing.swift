//
//  HyundaiEuropeAPIClient+Parsing.swift
//  BetterBlueKit
//
//  Response parsing for Hyundai Europe API
//

import Foundation

// MARK: - Response Parsing

extension HyundaiEuropeAPIClient {

    func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resMsg = json["resMsg"] as? [String: Any],
              let vehicleArray = resMsg["vehicles"] as? [[String: Any]] else {
            throw APIError.logError("Invalid vehicles response", apiName: apiName)
        }

        return vehicleArray.compactMap { vehicleData -> Vehicle? in
            guard let vehicleId = vehicleData["vehicleId"] as? String,
                  let vin = vehicleData["vin"] as? String,
                  let nickname = vehicleData["nickname"] as? String ?? vehicleData["vehicleName"] as? String else {
                return nil
            }

            let fuelKindCode = vehicleData["fuelKindCode"] as? String ?? ""
            let isElectric = fuelKindCode == "E" || fuelKindCode == "EV"
            let ownerInfo = vehicleData["master"] as? [String: Any] ?? [:]
            let generation = ownerInfo["carGeneration"] as? Int ?? 2

            return Vehicle(
                vin: vin,
                regId: vehicleId,
                model: nickname,
                accountId: accountId,
                isElectric: isElectric,
                generation: generation,
                odometer: Distance(length: 0, units: .kilometers)
            )
        }
    }

    func parseVehicleStatusResponse(_ data: Data, for vehicle: Vehicle) throws -> VehicleStatus {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resMsg = json["resMsg"] as? [String: Any] else {
            throw APIError.logError("Invalid status response", apiName: apiName)
        }

        let state = resMsg["state"] as? [String: Any] ?? [:]
        let vehicleState = state["Vehicle"] as? [String: Any] ?? [:]
        let syncDate = (resMsg["lastUpdateTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }

        return VehicleStatus(
            vin: vehicle.vin,
            gasRange: nil,
            evStatus: parseEVStatus(from: vehicleState, vehicle: vehicle),
            location: parseLocation(from: resMsg),
            lockStatus: parseLockStatus(from: vehicleState),
            climateStatus: parseClimateStatus(from: vehicleState),
            odometer: vehicle.odometer,
            syncDate: syncDate,
            battery12V: nil,
            doorOpen: nil,
            trunkOpen: nil,
            hoodOpen: nil,
            tirePressureWarning: nil
        )
    }

    private func parseEVStatus(from vehicleState: [String: Any], vehicle: Vehicle) -> VehicleStatus.EVStatus? {
        guard vehicle.isElectric else { return nil }

        let green = vehicleState["Green"] as? [String: Any] ?? [:]
        let drivetrain = green["Drivetrain"] as? [String: Any] ?? [:]
        let evInfo = drivetrain["BatteryManagement"] as? [String: Any] ?? [:]

        let batterySOC = evInfo["BatterySOC"] as? Double ?? 0
        let chargingStatus = evInfo["ChargingStatus"] as? String ?? ""
        let isCharging = chargingStatus.lowercased().contains("charging")
        let pluggedIn = evInfo["PluggedIn"] as? Bool ?? false
        let estimatedRange = evInfo["EstimatedRange"] as? Double ?? 0

        return VehicleStatus.EVStatus(
            charging: isCharging,
            chargeSpeed: 0,
            evRange: VehicleStatus.FuelRange(
                range: Distance(length: estimatedRange, units: .kilometers),
                percentage: batterySOC
            ),
            plugType: pluggedIn ? .acCharger : .unplugged,
            chargeTime: .seconds(0),
            targetSocAC: nil,
            targetSocDC: nil
        )
    }

    private func parseLockStatus(from vehicleState: [String: Any]) -> VehicleStatus.LockStatus {
        let chassis = vehicleState["Chassis"] as? [String: Any] ?? [:]
        let doorLockState = chassis["DoorLock"] as? [String: Any] ?? [:]
        let isLocked = (doorLockState["DoorLockStatus"] as? String ?? "").lowercased() == "locked"
        return VehicleStatus.LockStatus(locked: isLocked)
    }

    private func parseClimateStatus(from vehicleState: [String: Any]) -> VehicleStatus.ClimateStatus {
        let hvac = vehicleState["HVAC"] as? [String: Any] ?? [:]
        let airConOn = hvac["AirConOn"] as? Bool ?? false
        let targetTemp = hvac["TargetTemperature"] as? Double ?? 20.0

        return VehicleStatus.ClimateStatus(
            defrostOn: false,
            airControlOn: airConOn,
            steeringWheelHeatingOn: false,
            temperature: Temperature(value: targetTemp, units: .celsius)
        )
    }

    private func parseLocation(from resMsg: [String: Any]) -> VehicleStatus.Location {
        let location = resMsg["coord"] as? [String: Any] ?? [:]
        return VehicleStatus.Location(
            latitude: location["lat"] as? Double ?? 0,
            longitude: location["lon"] as? Double ?? 0
        )
    }
}
