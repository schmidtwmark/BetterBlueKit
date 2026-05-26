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
            // EU CCS2 vehicles only accept temperatures on the
            // 0.5°C grid (15.0–30.0). The car silently no-ops when
            // it gets an off-grid value like 22.22°C (which is what
            // a linear F→C of 72°F produces). `hvacConvert` snaps
            // to the EU lookup table for us.
            let tempCelsius = Temperature.hvacConvert(
                options.temperature.value,
                from: options.temperature.units,
                to: .celsius,
                table: .european
            )
            return ("ccs2/control/temperature", [
                "command": "start",
                "hvacInfo": [
                    "airCtrl": options.climate ? 1 : 0,
                    "defrost": options.defrost,
                    "heating1": options.heatValue,
                    "airTemp": ["value": String(format: "%.1f", tempCelsius), "unit": 0]
                ]
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
            return ("charge/target", [
                "targetSOClist": [
                    ["targetSOClevel": acLevel, "plugType": 0],
                    ["targetSOClevel": dcLevel, "plugType": 1]
                ]
            ])
        }
    }
}
