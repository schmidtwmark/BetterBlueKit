//
//  VehicleCommands.swift
//  BetterBlueKit
//
//  Vehicle command definitions and climate options
//

import Foundation

// MARK: - Vehicle Commands

public enum VehicleCommand: Sendable {
    case lock, unlock, startClimate(ClimateOptions)
    case stopClimate, startCharge, stopCharge

    public func getBodyForCommand(vin: String, isElectric: Bool, generation: Int, username: String) -> [String: Any] {
        var body: [String: Any] = [:]
        if case let .startClimate(options) = self {
            if isElectric {
                body = ["airCtrl": options.climate ? 1 : 0,
                        "airTemp": ["value": String(Int(options.temperature.value)),
                                    "unit": options.temperature.units.integer()],
                        "defrost": options.defrost, "heating1": options.heating ? 1 : 0]
                if generation >= 3 {
                    body["igniOnDuration"] = options.duration
                    body["seatHeaterVentInfo"] = ["drvSeatHeatState": options.frontLeftSeat,
                                                  "astSeatHeatState": options.frontRightSeat,
                                                  "rlSeatHeatState": options.rearLeftSeat,
                                                  "rrSeatHeatState": options.rearRightSeat]
                }
            } else {
                body = ["Ims": 0, "airCtrl": options.climate ? 1 : 0,
                        "airTemp": ["unit": options.temperature.units.integer(),
                                    "value": Int(options.temperature.value)],
                        "defrost": options.defrost, "heating1": options.heating,
                        "igniOnDuration": options.duration,
                        "seatHeaterVentInfo": ["drvSeatHeatState": options.frontLeftSeat,
                                               "astSeatHeatState": options.frontRightSeat,
                                               "rlSeatHeatState": options.rearLeftSeat,
                                               "rrSeatHeatState": options.rearRightSeat],
                        "username": username, "vin": vin]
            }
        } else if case .startCharge = self {
            body["chargeRatio"] = 100
        }
        return body
    }
}

public struct ClimateOptions: Codable, Equatable, Sendable {
    public var climate: Bool = true
    public var temperature: Temperature = .init(units: 1, value: "72")
    public var defrost: Bool = false
    public var heating: Bool = false
    public var duration: Int = 10
    public var frontLeftSeat: Int = 0, frontRightSeat: Int = 0
    public var rearLeftSeat: Int = 0, rearRightSeat: Int = 0
    public var steeringWheel: Int = 0

    // New fields added in v1.0.7-1.0.8 - made optional for backward compatibility
    public var frontLeftVentilation: Bool? = false
    public var frontRightVentilation: Bool? = false
    public var rearLeftVentilation: Bool? = false
    public var rearRightVentilation: Bool? = false
    public var rearDefrost: Bool? = true

    public init() {}

    // Safe getters and setters with default values
    public var hasFrontLeftVentilation: Bool {
        get { frontLeftVentilation ?? false }
        set { frontLeftVentilation = newValue }
    }
    public var hasFrontRightVentilation: Bool {
        get { frontRightVentilation ?? false }
        set { frontRightVentilation = newValue }
    }
    public var hasRearLeftVentilation: Bool {
        get { rearLeftVentilation ?? false }
        set { rearLeftVentilation = newValue }
    }
    public var hasRearRightVentilation: Bool {
        get { rearRightVentilation ?? false }
        set { rearRightVentilation = newValue }
    }
    public var hasRearDefrost: Bool {
        get { rearDefrost ?? true }
        set { rearDefrost = newValue }
    }
}
