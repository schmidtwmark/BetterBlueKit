//
//  KiaUSAAPIClient+Commands.swift
//  BetterBlueKit
//
//  Command helpers for Kia USA API
//

import Foundation

// MARK: - Command Helpers

extension KiaUSAAPIClient {

    func commandMethod(for command: VehicleCommand) -> HTTPMethod {
        switch command {
        case .stopClimate, .stopCharge:
            .GET
        default:
            .POST
        }
    }

    func commandURL(for command: VehicleCommand) -> String {
        let path: String = switch command {
        case .lock: "rems/door/lock"
        case .unlock: "rems/door/unlock"
        case .startClimate: "rems/start"
        case .stopClimate: "rems/stop"
        case .startCharge: "evc/charge"
        case .stopCharge: "evc/cancel"
        case .setTargetSOC: "evc/charge/targetsoc/set"
        }
        return "\(apiURL)\(path)"
    }

    func commandBody(for command: VehicleCommand, vehicle: Vehicle) -> [String: Any] {
        switch command {
        case .startClimate(let options):
            let heatingAccessory: [String: Int] = [
                "steeringWheel": options.steeringWheel > 0 ? 1 : 0,
                "steeringWheelStep": options.steeringWheel,
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

            let seats: [String: Int] = [
                "driverSeat": convertSeatSetting(options.frontLeftSeat, options.frontLeftVentilationEnabled),
                "passengerSeat": convertSeatSetting(options.frontRightSeat, options.frontRightVentilationEnabled),
                "rearLeftSeat": convertSeatSetting(options.rearLeftSeat, options.rearLeftVentilationEnabled),
                "rearRightSeat": convertSeatSetting(options.rearRightSeat, options.rearRightVentilationEnabled)
            ]

            remoteClimate["heatVentSeat"] = seats
            return ["remoteClimate": remoteClimate]
        case .startCharge:
            return ["chargeRatio": 100]
        case .setTargetSOC(let acLevel, let dcLevel):
            return ["targetSOClist": [
                ["targetSOClevel": acLevel, "plugType": 0],
                ["targetSOClevel": dcLevel, "plugType": 1]
            ]]
        default:
            return [:]
        }
    }

    // MARK: - Seat Setting Conversion

    private func convertSeatSetting(_ heatLevel: Int, _ ventilationEnabled: Bool) -> Int {
        if ventilationEnabled {
            // Ventilation: 4 = low, 5 = medium, 6 = high
            return min(max(heatLevel, 0), 3) + 3
        } else {
            // Heating: 0 = off, 1 = low, 2 = medium, 3 = high
            return min(max(heatLevel, 0), 3)
        }
    }
}
