//
//  KiaAPI+Endpoints.swift
//  BetterBlueKit
//
//  Created by Mark Schmidt on 12/26/25.
//

import Foundation

extension KiaAPIEndpointProvider: APIEndpointProvider {
    public func loginEndpoint() -> APIEndpoint {
        loginEndpoint(sid: nil, rmToken: nil)
    }

    public func loginEndpoint(sid: String?, rmToken: String? = nil) -> APIEndpoint {
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
            body: try? JSONSerialization.data(withJSONObject: loginData),
        )
    }

    public func sendOTPEndpoint(otpKey: String, xid: String, notifyType: String) -> APIEndpoint {
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
            body: try? JSONSerialization.data(withJSONObject: emptyBody),
        )
    }

    public func verifyOTPEndpoint(otpKey: String, xid: String, otp: String) -> APIEndpoint {
        let endpoint = "\(apiURL)cmm/verifyOTP"
        var headers = apiHeaders()
        headers["otpkey"] = otpKey
        headers["xid"] = xid

        let body = ["otp": otp]

        return APIEndpoint(
            url: endpoint,
            method: .POST,
            headers: headers,
            body: try? JSONSerialization.data(withJSONObject: body),
        )
    }

    public func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint {
        let vehiclesURL = "\(apiURL)ownr/gvl"

        return APIEndpoint(
            url: vehiclesURL,
            method: .GET,
            headers: authedApiHeaders(authToken: authToken, vehicleKey: nil),
        )
    }

    public func fetchVehicleStatusEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
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
            body: try? JSONSerialization.data(withJSONObject: body),
        )
    }

    public func sendCommandEndpoint(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken,
    ) -> APIEndpoint {
        let endpoint = getCommandEndpoint(command: command)
        let requestBody = getBodyForCommand(command: command, vehicle: vehicle)

        return APIEndpoint(
            url: endpoint,
            method: .POST,
            headers: authedApiHeaders(authToken: authToken, vehicleKey: vehicle.vehicleKey),
            body: try? JSONSerialization.data(withJSONObject: requestBody),
        )
    }

    public func getBodyForCommand(command: VehicleCommand, vehicle: Vehicle) -> [String: Any] {
        var body: [String: Any] = [:]

        switch command {
        case .startClimate(let options):
            let heatingAccessory: [String: Int] = [
                "steeringWheel": options.steeringWheel > 0 ? 1 : 0,
                "rearWindow": options.rearDefrostEnabled ? 1 : 0,
                "sideMirror": options.rearDefrostEnabled ? 1 : 0
            ]

            var remoteClimate: [String: Any] = [
                "airCtrl": options.climate,
                "defrost": options.defrost,
                "airTemp": [
                    "value": String(Int(options.temperature.value)),
                    "unit": options.temperature.units.integer()
                ],
                "ignitionOnDuration": [
                    "unit": 4,
                    "value": options.duration
                ],
                "heatingAccessory": heatingAccessory
            ]

            // Seat configuration
            let seats: [String: Int] = [
                "driverSeat": convertSeatSetting(options.frontLeftSeat, options.frontLeftVentilationEnabled),
                "passengerSeat": convertSeatSetting(options.frontRightSeat, options.frontRightVentilationEnabled),
                "rearLeftSeat": convertSeatSetting(options.rearLeftSeat, options.rearLeftVentilationEnabled),
                "rearRightSeat": convertSeatSetting(options.rearRightSeat, options.rearRightVentilationEnabled)
            ]

            remoteClimate["heatVentSeat"] = seats

            body = ["remoteClimate": remoteClimate]
        case .startCharge:
            body = ["chargeRatio": 100]
        case .setTargetSOC(let acLevel, let dcLevel):
            body["targetSOClist"] = [
                ["targetSOClevel": acLevel, "plugType": 0],
                ["targetSOClevel": dcLevel, "plugType": 1]
            ]
        case .stopCharge, .stopClimate, .lock, .unlock:
            break
        }

        return body
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
