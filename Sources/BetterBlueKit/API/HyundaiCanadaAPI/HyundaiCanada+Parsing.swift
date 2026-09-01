//
//  HyundaiCanada+Parsing.swift
//  BetterBlueKit
//
//  Hyundai Canada response parsing
//

import Foundation

extension HyundaiCanadaAPIClient {

    func parseCanadaLoginResponse(_ data: Data) throws -> AuthToken {
        let json = try parseCanadaResponse(data, context: "login")
        guard let result = json["result"] as? [String: Any],
              let token = result["token"] as? [String: Any],
              let accessToken = token["accessToken"] as? String else {
            throw APIError.logError("Invalid Canada login response", apiName: apiName)
        }

        let expiresIn: Int = extractNumber(from: token["expireIn"]) ?? 3600
        let refreshToken = token["refreshToken"] as? String ?? ""

        return AuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    package func parseCanadaVehiclesResponse(_ data: Data) throws -> [Vehicle] {
        let json = try parseCanadaResponse(data, context: "vehicles")
        guard let result = json["result"] as? [String: Any],
              let vehicles = result["vehicles"] as? [[String: Any]] else {
            throw APIError.logError("Invalid Canada vehicles response", apiName: apiName)
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

            let fuelType = detectFuelType(from: vehicleData)

            // The HVAC HEX scale changed at MY2020, so the climate
            // codec needs the model year (nil → pre-2020 scale, matching
            // upstream's default).
            let modelYear: Int? = extractNumber(from: vehicleData["modelYear"])

            return Vehicle(
                vin: vin,
                regId: regId,
                model: nickname,
                accountId: accountId,
                fuelType: fuelType,
                generation: generation,
                odometer: Distance(length: odometerValue, units: .kilometers),
                modelYear: modelYear
            )
        }
    }

    package func parseCanadaVehicleStatusResponse(_ data: Data, for vehicle: Vehicle) throws -> VehicleStatus {
        let json = try parseCanadaResponse(data, context: "status")
        guard let result = json["result"] as? [String: Any] else {
            throw APIError.logError("Invalid Canada status response", apiName: apiName)
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

        // Parse additional boolean flags
        let engineOn = parseBoolOrInt(statusData["engine"])
        let accessoryOn = parseBoolOrInt(statusData["acc"])
        let remoteIgnition = statusData["remoteIgnition"] as? Bool
        let transmissionCondition = statusData["transCond"] as? Bool
        let sleepMode = statusData["sleepModeCheck"] as? Bool
        let washerFluid = parseBoolOrInt(statusData["washerFluidStatus"])

        return VehicleStatus(
            vin: vehicle.vin,
            gasRange: parseCanadaGasRange(from: statusData, vehicle: vehicle),
            evStatus: parseCanadaEVStatus(from: statusData, vehicle: vehicle),
            location: parseCanadaLocation(from: statusData),
            lockStatus: VehicleStatus.LockStatus(locked: statusData["doorLock"] as? Bool),
            climateStatus: parseCanadaClimateStatus(from: statusData, modelYear: vehicle.modelYear),
            odometer: odometer,
            syncDate: parseCanadaSyncDate(from: statusData),
            battery12V: parseCanadaBattery12V(from: statusData),
            doorOpen: parseCanadaDoorStatus(from: statusData),
            trunkOpen: parseCanadaTrunkOpen(from: statusData),
            hoodOpen: parseCanadaHoodOpen(from: statusData),
            tirePressureWarning: parseCanadaTirePressureWarning(from: statusData),
            engineOn: engineOn,
            accessoryOn: accessoryOn,
            remoteIgnition: remoteIgnition,
            transmissionCondition: transmissionCondition,
            sleepMode: sleepMode,
            washerFluidLow: washerFluid
        )
    }

    func validateCommandResponse(_ data: Data, context: String) throws {
        _ = try parseCanadaResponse(data, context: context)
    }

    func parseCommandAuthResponse(_ data: Data) throws -> String {
        let json = try parseCanadaResponse(data, context: "command auth")
        guard let result = json["result"] as? [String: Any],
              let authCode = result["pAuth"] as? String else {
            throw APIError.logError("Invalid Canada command auth response", apiName: apiName)
        }
        return authCode
    }

    func parseCanadaLocationResponse(_ data: Data) throws -> VehicleStatus.Location {
        let json = try parseCanadaResponse(data, context: "location")
        guard let result = json["result"] as? [String: Any] else {
            throw APIError.logError("Invalid Canada location response", apiName: apiName)
        }

        // Three shapes seen from this API: `result.gpsDetail.coord`,
        // `result.coord` (BetterBlueKit#36), and the flat
        // `gpsDetail.coordLat` / `coordLon` pair the surround-view
        // endpoints return. Accept all of them rather than betting on
        // which one a given endpoint uses today.
        let gpsDetail = result["gpsDetail"] as? [String: Any]

        if let coord = (gpsDetail?["coord"] as? [String: Any]) ?? (result["coord"] as? [String: Any]) {
            return VehicleStatus.Location(
                latitude: extractNumber(from: coord["lat"]) ?? 0,
                longitude: extractNumber(from: coord["lon"]) ?? 0
            )
        }

        if let latitude: Double = extractNumber(from: gpsDetail?["coordLat"]),
           let longitude: Double = extractNumber(from: gpsDetail?["coordLon"]) {
            return VehicleStatus.Location(latitude: latitude, longitude: longitude)
        }

        throw APIError.logError("Invalid Canada location response", apiName: apiName)
    }
}
