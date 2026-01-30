//
//  KiaUSA.swift
//  BetterBlueKit
//
//  Kia USA API Endpoint Provider
//

import Foundation

// MARK: - Kia USA API Endpoint Provider

@MainActor
public final class KiaAPIEndpointProviderUSA: KiaAPIEndpointProviderBase {

    // MARK: - Endpoints

    public override func loginEndpoint() -> APIEndpoint {
        loginEndpoint(sid: nil, rmToken: nil)
    }

    public override func loginEndpoint(sid: String?, rmToken: String? = nil) -> APIEndpoint {
        let loginURL = "\(apiURL)prof/authUser"
        let loginData: [String: Any] = [
            "deviceKey": deviceId,
            "deviceType": 2,
            "tncFlag": 1,
            "userCredential": [
                "userId": username,
                "password": password
            ]
        ]

        var headers = apiHeaders()
        // Use rmToken parameter if provided, otherwise fall back to stored rememberMeToken
        if let token = rmToken ?? rememberMeToken {
            headers["rmtoken"] = token
        }
        if let sid {
            headers["sid"] = sid
        }

        return APIEndpoint(
            url: loginURL,
            method: .POST,
            headers: headers,
            body: try? JSONSerialization.data(withJSONObject: loginData)
        )
    }

    public override func sendOTPEndpoint(otpKey: String, xid: String, notifyType: String) -> APIEndpoint {
        let endpoint = "\(apiURL)cmm/sendOTP"
        var headers = apiHeaders()
        headers["otpkey"] = otpKey
        headers["notifytype"] = notifyType
        headers["xid"] = xid

        // The API expects an empty JSON body {}
        let emptyBody: [String: Any] = [:]

        return APIEndpoint(
            url: endpoint,
            method: .POST,
            headers: headers,
            body: try? JSONSerialization.data(withJSONObject: emptyBody)
        )
    }

    public override func verifyOTPEndpoint(otpKey: String, xid: String, otp: String) -> APIEndpoint {
        let endpoint = "\(apiURL)cmm/verifyOTP"
        var headers = apiHeaders()
        headers["otpkey"] = otpKey
        headers["xid"] = xid

        let body = ["otp": otp]

        return APIEndpoint(
            url: endpoint,
            method: .POST,
            headers: headers,
            body: try? JSONSerialization.data(withJSONObject: body)
        )
    }

    public override func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint {
        let vehiclesURL = "\(apiURL)ownr/gvl"

        return APIEndpoint(
            url: vehiclesURL,
            method: .GET,
            headers: authedApiHeaders(authToken: authToken, vehicleKey: nil)
        )
    }

    public override func fetchVehicleStatusEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
        let statusURL = "\(apiURL)cmm/gvi"

        // Log the vehicleKey for debugging
        BBLogger.debug(.api, "KiaAPI: Fetching status for VIN: \(vehicle.vin)," +
                       "vehicleKey: \(vehicle.vehicleKey ?? "nil")")

        let body: [String: Any] = [
            "vehicleConfigReq": [
                "airTempRange": "0",
                "maintenance": "1",
                "seatHeatCoolOption": "0",
                "vehicle": "1",
                "vehicleFeature": "0"
            ],
            "vehicleInfoReq": [
                "drivingActivty": "0",
                "dtc": "1",
                "enrollment": "1",
                "functionalCards": "0",
                "location": "1",
                "vehicleStatus": "1",
                "weather": "0"
            ],
            "vinKey": [vehicle.vehicleKey ?? ""]
        ]

        return APIEndpoint(
            url: statusURL,
            method: .POST,
            headers: authedApiHeaders(authToken: authToken, vehicleKey: vehicle.vehicleKey),
            body: try? JSONSerialization.data(withJSONObject: body)
        )
    }

    public override func sendCommandEndpoint(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken
    ) -> APIEndpoint {
        let endpoint = getCommandEndpoint(command: command)
        let requestBody = getBodyForCommand(command: command, vehicle: vehicle)

        return APIEndpoint(
            url: endpoint,
            method: .POST,
            headers: authedApiHeaders(authToken: authToken, vehicleKey: vehicle.vehicleKey),
            body: try? JSONSerialization.data(withJSONObject: requestBody)
        )
    }

    private func getCommandEndpoint(command: VehicleCommand) -> String {
        let path = switch command {
        case .lock:
            "rems/door/lock"
        case .unlock:
            "rems/door/unlock"
        case .startClimate:
            "rems/start"
        case .stopClimate:
            "rems/stop"
        case .startCharge:
            "evc/charge"
        case .stopCharge:
            "evc/cancel"
        case .setTargetSOC:
            "evc/charge/targetsoc/set"
        }
        return "\(apiURL)\(path)"
    }
}

// MARK: - Type Aliases for Convenience

public typealias KiaAPIClient = APIClient<KiaAPIEndpointProviderUSA>
public typealias KiaAPIClientUSA = APIClient<KiaAPIEndpointProviderUSA>
