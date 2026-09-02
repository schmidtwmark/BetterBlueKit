//
//  EuropeCCSPClient+Commands.swift
//  BetterBlueKit
//
//  Command paths and payloads shared by the Hyundai and Kia EU clients.
//  Both brands ride ApiImplType1 upstream, so the endpoint and body shapes
//  are identical — CCS2 cars use flat `ccs2/…` command bodies, legacy cars
//  use the v1 action/hvacType shapes.
//

import Foundation

extension EuropeCCSPClient {

    func commandPathAndBody(
        for command: VehicleCommand,
        ccs2: Bool = true,
        drvSeatLoc: String = "L"
    ) -> (String, [String: Any]) {
        let deviceId = configuration.deviceId ?? ""
        switch command {
        case .lock:
            return ccs2
                ? ("ccs2/control/door", ["command": "close"])
                : ("control/door", ["action": "close", "deviceId": deviceId])
        case .unlock:
            return ccs2
                ? ("ccs2/control/door", ["command": "open"])
                : ("control/door", ["action": "open", "deviceId": deviceId])
        case .startClimate(let options):
            // Kia/Hyundai EU only accept temperatures on the 0.5°C grid
            // (15.0–30.0). Sending 22.22 (linear F→C of 72°F) silently
            // no-ops on the car — `hvacConvert` snaps to the EU lookup table.
            let tempCelsius = Temperature.hvacConvert(
                options.temperature.value,
                from: options.temperature.units,
                to: .celsius,
                table: .european
            )
            if ccs2 {
                return (
                    "ccs2/control/temperature",
                    startClimateCCS2Body(options: options, tempCelsius: tempCelsius, drvSeatLoc: drvSeatLoc)
                )
            }
            // Legacy (non-CCS2) cars take the v1 `control/temperature`
            // action shape with a HEX temp code.
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
            // plugType 0 = DC fast charge, 1 = AC — per ApiImplType1
            // set_charge_limits.
            return ("charge/target", [
                "targetSOClist": [
                    ["targetSOClevel": dcLevel, "plugType": 0],
                    ["targetSOClevel": acLevel, "plugType": 1]
                ]
            ])
        }
    }

    /// CCS2 climate-start body — ApiImplType1.start_climate (CCS2 branch).
    /// `tempCelsius` is already snapped to the 0.5°C EU grid.
    private func startClimateCCS2Body(
        options: ClimateOptions,
        tempCelsius: Double,
        drvSeatLoc: String
    ) -> [String: Any] {
        // On a right-hand-drive car the driver sits on the right, so the
        // front-left/right seat controls map to passenger/driver. Matches
        // hyundai_kia_connect_api's `start_climate` seat handling.
        let (drvSeat, psgSeat) = drvSeatLoc == "R"
            ? (options.frontRightSeat, options.frontLeftSeat)
            : (options.frontLeftSeat, options.frontRightSeat)
        return [
            "command": "start",
            "ignitionDuration": options.duration,
            "strgWhlHeating": options.steeringWheel,
            "hvacTempType": 1,
            "hvacTemp": tempCelsius,
            // Rear-window + side-mirror heaters ride along with the heating
            // levels that engage them (1/2/4); off for 0 and steering-only (3).
            "sideRearMirrorHeating": [1, 2, 4].contains(options.heatValue) ? 1 : 0,
            "drvSeatLoc": drvSeatLoc,
            "seatClimateInfo": [
                "drvSeatClimateState": drvSeat,
                "psgSeatClimateState": psgSeat,
                "rrSeatClimateState": options.rearRightSeat,
                "rlSeatClimateState": options.rearLeftSeat
            ],
            "tempUnit": "C",
            "windshieldFrontDefogState": options.defrost
        ]
    }
}
