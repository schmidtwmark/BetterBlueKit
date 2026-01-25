//
//  HyundaiAPI+Endpoints.swift
//  BetterBlueKit
//
//  Created by Mark Schmidt on 12/26/25.
//

import Foundation

extension HyundaiAPIEndpointProvider: APIEndpointProvider {
    public func loginEndpoint() -> APIEndpoint {
        let loginURL = "\(region.apiBaseURL(for: .hyundai))/v2/ac/oauth/token"
        let loginData = [
            "username": username,
            "password": password
        ]

        return APIEndpoint(
            url: loginURL,
            method: .POST,
            headers: getHeaders(),
            body: try? JSONSerialization.data(withJSONObject: loginData),
        )
    }

    public func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint {
        let vehiclesURL = "\(region.apiBaseURL(for: .hyundai))/ac/v2/enrollment/details/\(username)"

        return APIEndpoint(
            url: vehiclesURL,
            method: .GET,
            headers: getAuthorizedHeaders(authToken: authToken),
        )
    }

    public func fetchVehicleStatusEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
        let statusURL = "\(region.apiBaseURL(for: .hyundai))/ac/v2/rcs/rvs/vehicleStatus"

        return APIEndpoint(
            url: statusURL,
            method: .GET,
            headers: getAuthorizedHeaders(authToken: authToken, vehicle: vehicle),
        )
    }

    public func sendCommandEndpoint(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
    ) -> APIEndpoint {
        let endpoint = getEndpointForCommand(command: command, vehicle: vehicle)
        let requestBody = getBodyForCommand(command: command, vehicle: vehicle)

        return APIEndpoint(
            url: endpoint.absoluteString,
            method: .POST,
            headers: getAuthorizedHeaders(authToken: authToken, vehicle: vehicle),
            body: try? JSONSerialization.data(withJSONObject: requestBody),
        )
    }

    private func getEndpointForCommand(command: VehicleCommand, vehicle: Vehicle) -> URL {
        let baseURL = region.apiBaseURL(for: .hyundai)

        switch command {
        case .unlock:
            return URL(string: "\(baseURL)/ac/v2/rcs/rdo/on")!
        case .lock:
            return URL(string: "\(baseURL)/ac/v2/rcs/rdo/off")!
        case .startClimate:
            if vehicle.isElectric {
                return URL(string: "\(baseURL)/ac/v2/evc/fatc/start")!
            } else {
                return URL(string: "\(baseURL)/ac/v2/rcs/rsc/start")!
            }
        case .stopClimate:
            if vehicle.isElectric {
                return URL(string: "\(baseURL)/ac/v2/evc/fatc/stop")!
            } else {
                return URL(string: "\(baseURL)/ac/v2/rcs/rsc/stop")!
            }
        case .startCharge:
            return URL(string: "\(baseURL)/ac/v2/evc/charge/start")!
        case .stopCharge:
            return URL(string: "\(baseURL)/ac/v2/evc/charge/stop")!
        case .setTargetSOC:
            return URL(string: "\(baseURL)/ac/v2/evc/charge/targetsoc/set")!
        }
    }

    public func getBodyForCommand(command: VehicleCommand, vehicle: Vehicle) -> [String: Any] {
        var body: [String: Any] = [:]
        if case let .startClimate(options) = command {
            if vehicle.isElectric {
                body = ["airCtrl": options.climate ? 1 : 0,
                        "airTemp": ["value": String(Int(options.temperature.value)),
                                    "unit": options.temperature.units.integer()],
                        "defrost": options.defrost, "heating1": options.heatValue]
                if vehicle.generation >= 3 {
                    body["igniOnDuration"] = options.duration
                    body["seatHeaterVentInfo"] = options.getSeatHeaterVentInfo()
                }
            } else {
                body = ["Ims": 0, "airCtrl": options.climate ? 1 : 0,
                        "airTemp": ["unit": options.temperature.units.integer(),
                                    "value": Int(options.temperature.value)],
                        "defrost": options.defrost, "heating1": options.heatValue,
                        "igniOnDuration": options.duration,
                        "seatHeaterVentInfo": options.getSeatHeaterVentInfo(),
                        "username": username, "vin": vehicle.vin]
            }
        } else if case .startCharge = command {
            body["chargeRatio"] = 100
        } else if case let .setTargetSOC(acLevel, dcLevel) = command {
            body["targetSOClist"] = [
                ["targetSOClevel": acLevel, "plugType": 0],
                ["targetSOClevel": dcLevel, "plugType": 1]
            ]
        }
        return body
    }

    // MARK: - EV Trip Details (Optional Feature)

    public func supportsEVTripDetails() -> Bool {
        // Only USA region supports trip details for now
        region == .usa
    }

    public func evTripDetailsEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
        let url = "\(region.apiBaseURL(for: .hyundai))/ac/v2/ts/alerts/maintenance/evTripDetails"

        // Trip details endpoint uses slightly different header names than other endpoints
        var headers = getAuthorizedHeaders(authToken: authToken, vehicle: vehicle)
        headers["userId"] = username  // Uses userId instead of username
        headers["access_token"] = authToken.accessToken  // Uses access_token instead of accessToken

        return APIEndpoint(
            url: url,
            method: .GET,
            headers: headers
        )
    }

    public func parseEVTripDetailsResponse(_ data: Data) throws -> [EVTripDetail] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tripDetails = json["tripdetails"] as? [[String: Any]]
        else {
            throw APIError(message: "Failed to parse trip details response", apiName: "HyundaiAPI")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.S"
        dateFormatter.timeZone = TimeZone.current

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
                  let startDate = dateFormatter.date(from: startDateString)
            else {
                BBLogger.warning(.api, "HyundaiAPI: Failed to parse trip detail entry")
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
}
