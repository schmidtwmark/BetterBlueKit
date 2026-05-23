//
//  KiaEuropeAPIClient+Commands.swift
//  BetterBlueKit
//
//  Command helpers for the Kia Europe client. Endpoint shapes are
//  identical to Hyundai EU — see HyundaiEuropeAPIClient+Commands.swift.
//

import Foundation

extension KiaEuropeAPIClient {

    func commandPathAndBody(for command: VehicleCommand, ccs2: Bool = true)
    -> (String, [String: Any]) {
        let deviceId = configuration.deviceId ?? ""
        switch command {
        case .lock:
            return ccs2
                ? ("ccs2/control/door", ["command": "close"])
                : ("/control/door", ["action": "close", "deviceId": deviceId])
        case .unlock:
            return ccs2
                ? ("ccs2/control/door", ["command": "open"])
                : ("/control/door", ["action": "open", "deviceId": deviceId])
        case .startClimate(let options):
            // CCS2 climate payload shape is fundamentally different from the legacy
            // (non-CCS2) shape used elsewhere in this file. Mirrors the Python
            // reference in hyundai-kia-connect/hyundai_kia_connect_api,
            // ApiImplType1.start_climate (CCS2 branch).
            // Kia EU only accepts temperatures on the 0.5°C grid
            // (15.0–30.0). Sending 22.22 (linear F→C of 72°F)
            // silently no-ops on the car. `hvacConvert` snaps to
            // the EU lookup table.
            let tempCelsius = Temperature.hvacConvert(
                options.temperature.value,
                from: options.temperature.units,
                to: .celsius,
                table: .eu
            )
            return ("ccs2/control/temperature", [
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
            ])
        case .stopClimate:
            return ccs2
                ? ("ccs2/control/temperature", ["command": "stop"])
                : ("control/temperature", [
                    "action": "stop",
                    "hvacType": 0,
                    "options": ["defrost": true, "heating1": 1],
                    "tempCode": "10H",
                    "unit": "C"
                ])
        case .startCharge:
            return ccs2
                ? ("ccs2/control/charge", ["command": "start"])
                : ("control/charge", ["action": "start", "deviceId": deviceId])
        case .stopCharge:
            return ccs2
                ? ("ccs2/control/charge", ["command": "stop"])
                : ("control/charge", ["action": "stop", "deviceId": deviceId])
        case .setTargetSOC(let acLevel, let dcLevel):
            return ("charge/target", [
                "targetSOClist": [
                    ["targetSOClevel": acLevel, "plugType": 0],
                    ["targetSOClevel": dcLevel, "plugType": 1]
                ]
            ])
        }
    }
}
