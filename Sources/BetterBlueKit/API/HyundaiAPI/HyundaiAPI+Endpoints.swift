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
        }
        return body
    }
}
