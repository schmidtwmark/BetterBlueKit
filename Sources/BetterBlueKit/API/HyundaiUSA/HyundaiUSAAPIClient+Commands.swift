//
//  HyundaiUSAAPIClient+Commands.swift
//  BetterBlueKit
//
//  Command helpers for Hyundai USA API
//

import Foundation

// MARK: - Command Helpers

extension HyundaiUSAAPIClient {

    func commandURL(for command: VehicleCommand, vehicle: Vehicle) -> String {
        let path: String = switch command {
        case .unlock: "ac/v2/rcs/rdo/on"
        case .lock: "ac/v2/rcs/rdo/off"
        case .startClimate: vehicle.fuelType.hasElectricCapability ? "ac/v2/evc/fatc/start" : "ac/v2/rcs/rsc/start"
        case .stopClimate: vehicle.fuelType.hasElectricCapability ? "ac/v2/evc/fatc/stop" : "ac/v2/rcs/rsc/stop"
        case .startCharge: "ac/v2/evc/charge/start"
        case .stopCharge: "ac/v2/evc/charge/stop"
        case .setTargetSOC: "ac/v2/evc/charge/targetsoc/set"
        }
        return "\(baseURL)/\(path)"
    }

    func commandBody(for command: VehicleCommand, vehicle: Vehicle) -> [String: Any] {
        switch command {
        case .startClimate(let options):
            if vehicle.fuelType.hasElectricCapability {
                var body: [String: Any] = [
                    "airCtrl": options.climate ? 1 : 0,
                    "airTemp": [
                        "value": String(Int(options.temperature.value)),
                        "unit": options.temperature.units.integer()
                    ],
                    "defrost": options.defrost,
                    "heating1": options.heatValue
                ]
                if vehicle.generation >= 3 {
                    body["igniOnDuration"] = options.duration
                    body["seatHeaterVentInfo"] = options.getSeatHeaterVentInfo()
                }
                return body
            } else {
                return [
                    "Ims": 0,
                    "airCtrl": options.climate ? 1 : 0,
                    "airTemp": ["unit": options.temperature.units.integer(), "value": Int(options.temperature.value)],
                    "defrost": options.defrost,
                    "heating1": options.heatValue,
                    "igniOnDuration": options.duration,
                    "seatHeaterVentInfo": options.getSeatHeaterVentInfo(),
                    "username": username,
                    "vin": vehicle.vin
                ]
            }
        case .startCharge:
            return ["chargeRatio": 100]
        case .setTargetSOC(let acLevel, let dcLevel):
            return ["targetSOClist": [
                ["targetSOClevel": acLevel, "plugType": 1],
                ["targetSOClevel": dcLevel, "plugType": 0]
            ]]
        default:
            return [:]
        }
    }
}
