//
//  HyundaiCanada+Commands.swift
//  BetterBlueKit
//
//  Hyundai Canada command helpers
//

import Foundation

extension HyundaiCanadaAPIClient {

    func extractTransactionId(from headers: [String: String]) -> String? {
        headers.first { $0.key.lowercased() == "transactionid" }?.value
    }

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
        let values =
            options.temperature.units == .fahrenheit
            ? hvacFahrenheitValues
            : hvacCelsiusValues

        let targetValue = options.temperature.value
        let index = nearestTemperatureIndex(in: values, to: targetValue)

        guard index < hvacEncodedValues.count else {
            return hvacEncodedValues.first ?? "06H"
        }

        return hvacEncodedValues[index]
    }

    private func nearestTemperatureIndex(in values: [Double], to target: Double) -> Int {
        guard !values.isEmpty else {
            return 0
        }

        var bestIndex = 0
        var smallestDelta = abs(values[0] - target)

        for (index, value) in values.enumerated() {
            let delta = abs(value - target)
            if delta < smallestDelta {
                smallestDelta = delta
                bestIndex = index
            }
        }

        return bestIndex
    }
}
