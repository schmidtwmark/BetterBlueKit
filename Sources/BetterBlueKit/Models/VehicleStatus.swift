//
//  VehicleStatus.swift
//  BetterBlueKit
//
//  Vehicle status and related nested types
//

import Foundation

// MARK: - Vehicle Status

public struct VehicleStatus: Codable, Hashable, Sendable {
    public let vin: String
    public var lastUpdated: Date = .init(), syncDate: Date?

    public struct FuelRange: Codable, Hashable, Sendable {
        public var range: Distance, percentage: Double
        public init(range: Distance, percentage: Double) {
            (self.range, self.percentage) = (range, percentage)
        }
    }

    public var gasRange: FuelRange?

    public enum PlugType: Int, Codable, Hashable, Sendable {
        case unplugged = 0
        case acCharger = 2
        case dcCharger = 1 // DC is any value other than 0 or 2

        public init(fromBatteryPlugin value: Int) {
            switch value {
            case 0:
                self = .unplugged
            case 2:
                self = .acCharger
            default:
                self = .dcCharger
            }
        }
    }

    public struct EVStatus: Codable, Hashable, Sendable {
        public var charging: Bool, chargeSpeed: Double
        @available(*, deprecated, message: "Use plugType != .unplugged instead")
        public var deprecatedPluggedInField: Bool?
        public var pluggedIn: Bool { plugType != .unplugged }
        public var evRange: FuelRange
        public var maybePlugType: PlugType?
        public var plugType: PlugType { maybePlugType ?? .unplugged }
        private var maybeChargeTimeSeconds: Int64?
        public var chargeTime: Duration { .seconds(maybeChargeTimeSeconds ?? 0 ) }
        public var targetSocAC: Double?
        public var targetSocDC: Double?

        public var currentTargetSOC: Double? {
            switch plugType {
            case .acCharger:
                return targetSocAC
            case .dcCharger:
                return targetSocDC
            case .unplugged:
                return nil
            }
        }

        public init(
            charging: Bool,
            chargeSpeed: Double,
            pluggedIn: Bool = false,
            evRange: FuelRange,
            plugType: PlugType = .unplugged,
            chargeTime: Duration,
            targetSocAC: Double? = nil,
            targetSocDC: Double? = nil
        ) {
            (self.charging, self.chargeSpeed, self.deprecatedPluggedInField, self.evRange, self.maybePlugType,
             self.maybeChargeTimeSeconds) = (charging, chargeSpeed, pluggedIn, evRange, plugType,
                                              chargeTime.components.seconds)
            (self.targetSocAC, self.targetSocDC) = (targetSocAC, targetSocDC)
        }
    }

    public var evStatus: EVStatus?
    public struct Location: Codable, Hashable, Sendable, Equatable {
        public var latitude: Double, longitude: Double
        public init(latitude: Double, longitude: Double) {
            (self.latitude, self.longitude) = (latitude, longitude)
        }

        public var debug: String { "\(latitude)°, \(longitude)°" }
    }

    public var location: Location
    public enum LockStatus: String, Codable, Hashable, Sendable {
        case locked, unlocked, unknown

        public init(locked: Bool?) { self = locked == nil ? .unknown : (locked! ? .locked : .unlocked) }

        public mutating func toggle() {
            self = self == .locked ? .unlocked : (self == .unlocked ? .locked : .unknown)
        }
    }

    public var lockStatus: LockStatus
    public struct ClimateStatus: Codable, Hashable, Sendable {
        public var defrostOn: Bool, airControlOn: Bool
        public var steeringWheelHeatingOn: Bool, temperature: Temperature
        public init(defrostOn: Bool, airControlOn: Bool, steeringWheelHeatingOn: Bool, temperature: Temperature) {
            (self.defrostOn, self.airControlOn, self.steeringWheelHeatingOn, self.temperature) =
                (defrostOn, airControlOn, steeringWheelHeatingOn, temperature)
        }
    }

    public var climateStatus: ClimateStatus, odometer: Distance?

    // Additional status fields
    public var battery12V: Int?
    public var doorOpen: DoorStatus?
    public var trunkOpen: Bool?
    public var hoodOpen: Bool?
    public var tirePressureWarning: TirePressureWarning?

    public struct DoorStatus: Codable, Hashable, Sendable {
        public var frontLeft: Bool
        public var frontRight: Bool
        public var backLeft: Bool
        public var backRight: Bool

        public init(frontLeft: Bool, frontRight: Bool, backLeft: Bool, backRight: Bool) {
            (self.frontLeft, self.frontRight, self.backLeft, self.backRight) =
                (frontLeft, frontRight, backLeft, backRight)
        }

        public var anyOpen: Bool {
            frontLeft || frontRight || backLeft || backRight
        }

        public var openDoorsDescription: String {
            var doors: [String] = []
            if frontLeft { doors.append("FL") }
            if frontRight { doors.append("FR") }
            if backLeft { doors.append("BL") }
            if backRight { doors.append("BR") }
            return doors.isEmpty ? "None" : doors.joined(separator: ", ")
        }
    }

    public struct TirePressureWarning: Codable, Hashable, Sendable {
        public var frontLeft: Bool
        public var frontRight: Bool
        public var rearLeft: Bool
        public var rearRight: Bool
        public var all: Bool

        public init(frontLeft: Bool, frontRight: Bool, rearLeft: Bool, rearRight: Bool, all: Bool) {
            (self.frontLeft, self.frontRight, self.rearLeft, self.rearRight, self.all) =
                (frontLeft, frontRight, rearLeft, rearRight, all)
        }

        public var hasWarning: Bool {
            all || frontLeft || frontRight || rearLeft || rearRight
        }

        public var warningDescription: String {
            if all { return "All tires" }
            var tires: [String] = []
            if frontLeft { tires.append("FL") }
            if frontRight { tires.append("FR") }
            if rearLeft { tires.append("RL") }
            if rearRight { tires.append("RR") }
            return tires.isEmpty ? "OK" : tires.joined(separator: ", ")
        }
    }

    public init(vin: String, gasRange: FuelRange? = nil, evStatus: EVStatus? = nil,
                location: Location, lockStatus: LockStatus, climateStatus: ClimateStatus,
                odometer: Distance? = nil, syncDate: Date? = nil,
                battery12V: Int? = nil, doorOpen: DoorStatus? = nil,
                trunkOpen: Bool? = nil, hoodOpen: Bool? = nil,
                tirePressureWarning: TirePressureWarning? = nil) {
        (self.vin, self.gasRange, self.evStatus, self.location) = (vin, gasRange, evStatus, location)
        (self.lockStatus, self.climateStatus, self.odometer, self.syncDate) =
            (lockStatus, climateStatus, odometer, syncDate)
        (self.battery12V, self.doorOpen, self.trunkOpen, self.hoodOpen, self.tirePressureWarning) =
            (battery12V, doorOpen, trunkOpen, hoodOpen, tirePressureWarning)
    }
}
