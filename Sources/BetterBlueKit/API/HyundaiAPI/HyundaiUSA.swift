//
//  HyundaiUSA.swift
//  BetterBlueKit
//
//  Hyundai USA API Endpoint Provider
//

import Foundation

// MARK: - Hyundai USA API Endpoint Provider

@MainActor
public final class HyundaiAPIEndpointProviderUSA: HyundaiAPIEndpointProviderBase {

    // MARK: - Endpoints

    public override func loginEndpoint() -> APIEndpoint {
        let loginURL = "\(region.apiBaseURL(for: .hyundai))/v2/ac/oauth/token"
        let loginData = [
            "username": username,
            "password": password
        ]

        return APIEndpoint(
            url: loginURL,
            method: .POST,
            headers: getHeaders(),
            body: try? JSONSerialization.data(withJSONObject: loginData)
        )
    }

    public override func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint {
        let vehiclesURL = "\(region.apiBaseURL(for: .hyundai))/ac/v2/enrollment/details/\(username)"

        return APIEndpoint(
            url: vehiclesURL,
            method: .GET,
            headers: getAuthorizedHeaders(authToken: authToken)
        )
    }

    public override func fetchVehicleStatusEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
        let statusURL = "\(region.apiBaseURL(for: .hyundai))/ac/v2/rcs/rvs/vehicleStatus"

        return APIEndpoint(
            url: statusURL,
            method: .GET,
            headers: getAuthorizedHeaders(authToken: authToken, vehicle: vehicle)
        )
    }

    public override func sendCommandEndpoint(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken
    ) -> APIEndpoint {
        let endpoint = getEndpointForCommand(command: command, vehicle: vehicle)
        let requestBody = getBodyForCommand(command: command, vehicle: vehicle)

        return APIEndpoint(
            url: endpoint.absoluteString,
            method: .POST,
            headers: getAuthorizedHeaders(authToken: authToken, vehicle: vehicle),
            body: try? JSONSerialization.data(withJSONObject: requestBody)
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

    // MARK: - EV Trip Details (USA supports this)

    public override func supportsEVTripDetails() -> Bool {
        true
    }

    public override func evTripDetailsEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
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

    public override func parseEVTripDetailsResponse(_ data: Data) throws -> [EVTripDetail] {
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

// MARK: - Type Aliases for Convenience

public typealias HyundaiAPIClient = APIClient<HyundaiAPIEndpointProviderUSA>
public typealias HyundaiAPIClientUSA = APIClient<HyundaiAPIEndpointProviderUSA>
