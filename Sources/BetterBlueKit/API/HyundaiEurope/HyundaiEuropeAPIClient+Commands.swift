//
//  HyundaiEuropeAPIClient+Commands.swift
//  BetterBlueKit
//
//  Command helpers for Hyundai Europe API
//

import Foundation

// MARK: - Command Helpers

extension HyundaiEuropeAPIClient {

    func commandPathAndBody(for command: VehicleCommand, ccs2: Bool = true)
    -> (String, [String: Any]) {
        let deviceId = configuration.deviceId ?? ""
        switch command {
        case .lock:
            return ccs2 ? ("ccs2/control/door", ["command": "close"])
            : ("control/door", ["action": "close", "deviceId": deviceId])
        case .unlock:
            return ccs2 ? ("ccs2/control/door", ["command": "open"])
            : ("control/door", ["action": "open", "deviceId": deviceId])
        case .startClimate(let options):
            // EU vehicles share ApiImplType1.start_climate across
            // both brands — CCS2 uses a flat body (same as Kia EU);
            // legacy uses an action/hvacType body with a HEX temp
            // code. We previously sent a hand-rolled `hvacInfo`
            // body that matched neither, so Hyundai EU climate
            // silently failed.
            let tempCelsius = Temperature.hvacConvert(
                options.temperature.value,
                from: options.temperature.units,
                to: .celsius,
                table: .european
            )
            if ccs2 {
                return ("ccs2/control/temperature", startClimateCCS2Body(options: options, tempCelsius: tempCelsius))
            }
            return ("control/temperature", [
                "action": "start",
                "hvacType": 0,
                "options": [
                    "defrost": options.defrost,
                    "heating1": options.heatValue,
                    "igniOnDuration": options.duration
                ],
                "tempCode": Temperature.encodeAirTempToHEX(celsiusValue: tempCelsius),
                "unit": "C"
            ])
        case .stopClimate:
            return ccs2 ? ("ccs2/control/temperature", ["command": "stop"]) :
            ("control/temperature", [
                "action": "stop",
                "hvacType": 0,
                "options": [
                    "defrost": true,
                    "heating1": 1
                ],
                "tempCode": "10H",
                "unit": "C"
            ])
        case .startCharge:
            return ccs2 ? ("ccs2/control/charge", ["command": "start"])
            : ("control/charge", ["action": "start", "deviceId": deviceId])
        case .stopCharge:
            return ccs2 ? ("ccs2/control/charge", ["command": "stop"])
            : ("control/charge", ["action": "stop", "deviceId": deviceId])
        case .setTargetSOC(let acLevel, let dcLevel):
            // plugType 0 = DC fast charge, 1 = AC — per ApiImplType1
            // set_charge_limits. The mapping was inverted, so users
            // set the AC and DC limits onto the opposite plug type.
            return ("charge/target", [
                "targetSOClist": [
                    ["targetSOClevel": dcLevel, "plugType": 0],
                    ["targetSOClevel": acLevel, "plugType": 1]
                ]
            ])
        }
    }

    /// CCS2 climate-start body. Identical shape to Kia EU's — both
    /// brands share ApiImplType1.start_climate (CCS2 branch).
    /// `tempCelsius` is already snapped to the 0.5°C EU grid.
    private func startClimateCCS2Body(options: ClimateOptions, tempCelsius: Double) -> [String: Any] {
        [
            "command": "start",
            "ignitionDuration": options.duration,
            "strgWhlHeating": options.steeringWheel,
            "hvacTempType": 1,
            "hvacTemp": tempCelsius,
            "sideRearMirrorHeating": 1,
            "drvSeatLoc": "R",
            "seatClimateInfo": [
                "drvSeatClimateState": options.frontLeftSeat,
                "psgSeatClimateState": options.frontRightSeat,
                "rrSeatClimateState": options.rearRightSeat,
                "rlSeatClimateState": options.rearLeftSeat
            ],
            "tempUnit": "C",
            "windshieldFrontDefogState": options.defrost
        ]
    }
}

extension VehicleCommand {
    var isChargeLimitCommand: Bool {
        if case .setTargetSOC = self {
            return true
        }
        return false
    }
}
