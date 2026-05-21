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
