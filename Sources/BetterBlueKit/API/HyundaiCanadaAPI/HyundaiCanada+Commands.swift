//
//  HyundaiCanada+Commands.swift
//  BetterBlueKit
//
//  Hyundai Canada command helpers
//

import Foundation

extension HyundaiCanadaAPIClient {

    func commandPath(for command: VehicleCommand) -> String {
        switch command {
        case .lock:
            return "drlck"
        case .unlock:
            return "drulck"
        case .startClimate:
            return "evc/rfon"
        case .stopClimate:
            return "evc/rfoff"
        case .startCharge:
            return "evc/rcstrt"
        case .stopCharge:
            return "evc/rcstp"
        case .setTargetSOC:
            return "evc/setsoc"
        }
    }

    func makeCommandBody(
        command: VehicleCommand,
        useRemoteControl: Bool
    ) -> [String: Any] {
        switch command {
        case .startClimate(let options):
            var hvacInfo: [String: Any] = [
                "airCtrl": options.climate ? 1 : 0,
                "defrost": options.defrost,
                "airTemp": [
                    "value": climateTemperatureValue(for: options),
                    "unit": 0,
                    "hvacTempType": 1
                ],
                "igniOnDuration": options.duration,
                "heating1": options.heatValue
            ]

            let seatConfig = makeSeatClimateConfig(options: options)
            if !seatConfig.isEmpty {
                hvacInfo["seatHeaterVentCMD"] = seatConfig
            }

            return [
                "pin": pin,
                useRemoteControl ? "remoteControl" : "hvacInfo": hvacInfo
            ]

        case .stopClimate, .startCharge, .stopCharge, .lock, .unlock:
            return ["pin": pin]

        case .setTargetSOC(let acLevel, let dcLevel):
            return [
                "pin": pin,
                "tsoc": [
                    ["plugType": 0, "level": dcLevel],
                    ["plugType": 1, "level": acLevel]
                ]
            ]
        }
    }

    private func makeSeatClimateConfig(options: ClimateOptions) -> [String: Int] {
        let seatValues: [String: Int] = [
            "drvSeatOptCmd": convertSeatSetting(options.frontLeftSeat, options.frontLeftVentilationEnabled),
            "astSeatOptCmd": convertSeatSetting(options.frontRightSeat, options.frontRightVentilationEnabled),
            "rlSeatOptCmd": convertSeatSetting(options.rearLeftSeat, options.rearLeftVentilationEnabled),
            "rrSeatOptCmd": convertSeatSetting(options.rearRightSeat, options.rearRightVentilationEnabled)
        ]

        return seatValues.filter { $0.value != 0 }
    }

    private func climateTemperatureValue(for options: ClimateOptions) -> String {
        // Hyundai Canada uses the legacy HEX scheme (e.g. "10H").
        // Snap to the standard lookup table's 0.5°C grid first, then
        // encode. Replaces the bespoke
        // `hvacFahrenheitValues` / `hvacCelsiusValues` / `hvacEncodedValues`
        // triple — they were redundant with the canonical Standard
        // table + the inverse of `parseAirTempFromHEX`.
        let tempCelsius = Temperature.hvacConvert(
            options.temperature.value,
            from: options.temperature.units,
            to: .celsius,
            table: .standard
        )
        return Temperature.encodeAirTempToHEX(celsiusValue: tempCelsius)
    }
}
