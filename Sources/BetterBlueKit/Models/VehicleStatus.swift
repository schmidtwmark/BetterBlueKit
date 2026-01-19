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

    public init(vin: String, gasRange: FuelRange? = nil, evStatus: EVStatus? = nil,
                location: Location, lockStatus: LockStatus, climateStatus: ClimateStatus,
                odometer: Distance? = nil, syncDate: Date? = nil) {
        (self.vin, self.gasRange, self.evStatus, self.location) = (vin, gasRange, evStatus, location)
        (self.lockStatus, self.climateStatus, self.odometer, self.syncDate) =
            (lockStatus, climateStatus, odometer, syncDate)
    }
}
