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
                // Kia US always expects Fahrenheit (unit 1). The
                // value is the F temperature as a string, clamped to
                // "LOW"/"HIGH" outside the 62–82°F range. Matches
                // KiaUvoApiUSA.start_climate. Previously we sent the
                // raw preset value + its own unit, so a Celsius
                // preset produced {"value":"22","unit":0} — which the
                // car reads as 22°F (freezing) or rejects outright.
                "airTemp": kiaUSAirTemp(for: options.temperature),
                "ignitionOnDuration": [
                    "unit": 4,
                    "value": options.duration
                ],
                "heatingAccessory": heatingAccessory
            ]

            // Only include heatVentSeat when the user actually set a
            // seat — Kia now validates seat-climate capability at the
            // car level and rejects the whole command if the body
            // includes heatVentSeat on a vehicle that can't do it.
            // (See the explicit note in KiaUvoApiUSA.start_climate.)
            let seats: [String: Int] = [
                "driverSeat": convertSeatSetting(options.frontLeftSeat, options.frontLeftVentilationEnabled),
                "passengerSeat": convertSeatSetting(options.frontRightSeat, options.frontRightVentilationEnabled),
                "rearLeftSeat": convertSeatSetting(options.rearLeftSeat, options.rearLeftVentilationEnabled),
                "rearRightSeat": convertSeatSetting(options.rearRightSeat, options.rearRightVentilationEnabled)
            ]
            if seats.values.contains(where: { $0 != 0 }) {
                remoteClimate["heatVentSeat"] = seats
            }
            return ["remoteClimate": remoteClimate]
        case .startCharge:
            return ["chargeRatio": 100]
        case .setTargetSOC(let acLevel, let dcLevel):
            // Kia US encodes plugType 0 as DC fast charge and plugType 1
            // as AC (matches hyundai_kia_connect_api). The previous
            // mapping was inverted, so users saw — and set — AC/DC
            // limits swapped (issue #41).
            return ["targetSOClist": [
                ["targetSOClevel": dcLevel, "plugType": 0],
                ["targetSOClevel": acLevel, "plugType": 1]
            ]]
        default:
            return [:]
        }
    }

    /// Builds the `airTemp` payload for Kia US: always Fahrenheit
    /// (unit 1), value clamped to the 62–82°F controllable range
    /// with "LOW"/"HIGH" sentinels outside it. Converts from
    /// whatever unit the preset was stored in.
    private func kiaUSAirTemp(for temperature: Temperature) -> [String: Any] {
        let fahrenheit = temperature.units.convert(temperature.value, to: .fahrenheit)
        let value: String
        if fahrenheit < 62 {
            value = "LOW"
        } else if fahrenheit > 82 {
            value = "HIGH"
        } else {
            value = String(Int(fahrenheit.rounded()))
        }
        return ["value": value, "unit": 1]
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
