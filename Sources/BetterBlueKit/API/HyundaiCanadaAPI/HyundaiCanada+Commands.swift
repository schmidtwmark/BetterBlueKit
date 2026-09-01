//
//  HyundaiCanada+Commands.swift
//  BetterBlueKit
//
//  Hyundai Canada command helpers. Paths and payloads port
//  hyundai_kia_connect_api's KiaUvoApiCA: EVs use the `evc/*` family,
//  everything else (gas, PHEV) uses `rmtstrt`/`rmtstp` with the
//  `setting`-wrapped payload.
//

import Foundation

extension HyundaiCanadaAPIClient {

    func commandPath(for command: VehicleCommand, vehicle: Vehicle) -> String {
        // Upstream branches strictly on ENGINE_TYPES.EV — PHEVs take the
        // ICE climate path too.
        let isEV = vehicle.fuelType == .electric
        switch command {
        case .lock:
            return "drlck"
        case .unlock:
            return "drulck"
        case .startClimate:
            return isEV ? "evc/rfon" : "rmtstrt"
        case .stopClimate:
            return isEV ? "evc/rfoff" : "rmtstp"
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
        vehicle: Vehicle,
        useRemoteControl: Bool
    ) -> [String: Any] {
        switch command {
        case .startClimate(let options):
            if vehicle.fuelType == .electric {
                return makeEVClimateBody(
                    options: options, vehicle: vehicle, useRemoteControl: useRemoteControl
                )
            }
            return makeICEClimateBody(options: options, vehicle: vehicle)

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

    private func makeEVClimateBody(
        options: ClimateOptions,
        vehicle: Vehicle,
        useRemoteControl: Bool
    ) -> [String: Any] {
        let climateSettings: [String: Any] = [
            "airCtrl": options.climate ? 1 : 0,
            "defrost": options.defrost,
            "airTemp": [
                "value": climateTemperatureValue(for: options, vehicle: vehicle),
                "unit": 0,
                "hvacTempType": 1
            ],
            "igniOnDuration": options.duration,
            "heating1": options.heatValue,
            "seatHeaterVentCMD": makeSeatClimateConfig(options: options)
        ]
        return [
            "pin": pin,
            useRemoteControl ? "remoteControl" : "hvacInfo": climateSettings
        ]
    }

    /// Non-EV climate start (`rmtstrt`): the whole configuration rides
    /// in a `setting` wrapper with `ims: 0` and `hvacTempType: 0`,
    /// per upstream's ICE branch.
    private func makeICEClimateBody(options: ClimateOptions, vehicle: Vehicle) -> [String: Any] {
        [
            "setting": [
                "airCtrl": options.climate ? 1 : 0,
                "defrost": options.defrost,
                "heating1": options.heatValue,
                "igniOnDuration": options.duration,
                "ims": 0,
                "airTemp": [
                    "value": climateTemperatureValue(for: options, vehicle: vehicle),
                    "unit": 0,
                    "hvacTempType": 0
                ],
                "seatHeaterVentCMD": makeSeatClimateConfig(options: options)
            ],
            "pin": pin
        ]
    }

    private func makeSeatClimateConfig(options: ClimateOptions) -> [String: Int] {
        // All four keys are always sent, zeros included — upstream never
        // omits entries, and a missing key risks reading as "no change"
        // rather than "off" on the server side.
        [
            "drvSeatOptCmd": convertSeatSetting(options.frontLeftSeat, options.frontLeftVentilationEnabled),
            "astSeatOptCmd": convertSeatSetting(options.frontRightSeat, options.frontRightVentilationEnabled),
            "rlSeatOptCmd": convertSeatSetting(options.rearLeftSeat, options.rearLeftVentilationEnabled),
            "rrSeatOptCmd": convertSeatSetting(options.rearRightSeat, options.rearRightVentilationEnabled)
        ]
    }

    private func climateTemperatureValue(for options: ClimateOptions, vehicle: Vehicle) -> String {
        // Hyundai Canada uses the legacy HEX scheme (e.g. "10H"), with a
        // scale that shifted at MY2020 (14.0°C base vs 16.0°C). Snap to
        // the standard lookup table's 0.5°C grid first, then encode with
        // the vehicle's scale.
        let tempCelsius = Temperature.hvacConvert(
            options.temperature.value,
            from: options.temperature.units,
            to: .celsius,
            table: .standard
        )
        return Temperature.encodeCanadaAirTempToHEX(
            celsiusValue: tempCelsius, modelYear: vehicle.modelYear
        )
    }
}
