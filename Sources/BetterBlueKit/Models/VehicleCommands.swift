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
}

public struct ClimateOptions: Codable, Equatable, Sendable {
    public var climate: Bool = true
    public var temperature: Temperature = .init(units: 1, value: "72")
    public var defrost: Bool = false
    public var duration: Int = 10
    public var frontLeftSeat: Int = 0, frontRightSeat: Int = 0
    public var rearLeftSeat: Int = 0, rearRightSeat: Int = 0
    public var steeringWheel: Int = 0

    // New fields added in v1.0.7-1.0.8 - made optional for backward compatibility
    public var frontLeftVentilation: Bool? = false
    public var frontRightVentilation: Bool? = false
    public var rearLeftVentilation: Bool? = false
    public var rearRightVentilation: Bool? = false
    public var rearDefrost: Bool? = false

    public init() {}

    // Safe getters and setters with default values
    public var frontLeftVentilationEnabled: Bool {
        get { frontLeftVentilation ?? false }
        set { frontLeftVentilation = newValue }
    }
    public var frontRightVentilationEnabled: Bool {
        get { frontRightVentilation ?? false }
        set { frontRightVentilation = newValue }
    }
    public var rearLeftVentilationEnabled: Bool {
        get { rearLeftVentilation ?? false }
        set { rearLeftVentilation = newValue }
    }
    public var rearRightVentilationEnabled: Bool {
        get { rearRightVentilation ?? false }
        set { rearRightVentilation = newValue }
    }
    public var rearDefrostEnabled: Bool {
        get { rearDefrost ?? false }
        set { rearDefrost = newValue }
    }

    public var heatValue: Int {
        if !rearDefrostEnabled && steeringWheel == 0 {
            return 0
        } else if rearDefrostEnabled && steeringWheel != 0 {
            return 4
        } else if rearDefrostEnabled {
            return 2
        } else if steeringWheel != 0 {
            return 3
        }
        return 0
    }

    public func getSeatHeaterVentInfo() -> [String: Int] {
        return ["drvSeatHeatState":
                    convertSeatSetting(self.frontLeftSeat, self.frontLeftVentilationEnabled),
                  "astSeatHeatState":
                    convertSeatSetting(self.frontRightSeat, self.frontRightVentilationEnabled),
                  "rlSeatHeatState":
                    convertSeatSetting(self.rearLeftSeat, self.rearLeftVentilationEnabled),
                  "rrSeatHeatState":
                    convertSeatSetting(self.rearRightSeat, self.rearRightVentilationEnabled)]
    }
}

// Taken from the Scriptable project
// Maps the internal ClimateOptions to the values Hyundai/Kia expect
// https://github.com/andyfase/egmp-bluelink-scriptable/blob/e86ccf383944c88a0c17228a6ddd75e34e9c4dac/src/config.ts#L29
func convertSeatSetting(_ value: Int, _ cooling: Bool) -> Int {
    if value == 0 {
        return 0
    }
    // For cooling, 1 -> 3, 2 -> 4, 3 -> 5
    // For warm, 1 -> 6, 2 -> 7, 3 -> 8
    if cooling {
        return value + 2
    } else {
        return value + 5
    }

}
