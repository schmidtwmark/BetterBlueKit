//
//  HyundaiEuropeAPIClient+Commands.swift
//  BetterBlueKit
//
//  Command helpers for Hyundai Europe API
//

import Foundation

// MARK: - Command Helpers

extension HyundaiEuropeAPIClient {

    func commandPathAndBody(for command: VehicleCommand) -> (String, [String: Any]) {
        switch command {
        case .lock:
            return ("ccs2/control/door", ["command": "close"])
        case .unlock:
            return ("ccs2/control/door", ["command": "open"])
        case .startClimate(let options):
            let tempCelsius = options.temperature.units == .celsius
                ? options.temperature.value
                : (options.temperature.value - 32.0) * 5.0 / 9.0
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
            return ("ccs2/control/temperature", ["command": "stop"])
        case .startCharge:
            return ("ccs2/control/charge", ["command": "start"])
        case .stopCharge:
            return ("ccs2/control/charge", ["command": "stop"])
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
