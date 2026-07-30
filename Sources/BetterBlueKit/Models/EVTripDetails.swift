//
//  EVTripDetails.swift
//  BetterBlueKit
//
//  EV Trip Details for energy consumption tracking
//

import Foundation

// MARK: - EV Trip Summary

/// Represents details of an EV trip including energy consumption breakdown
public struct EVTripSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(startDate.timeIntervalSince1970)-\(odometer.length)" }

    /// Trip distance, in whatever units the API reported
    public let distance: Distance

    /// Odometer reading at trip end, in whatever units the API reported
    public let odometer: Distance

    /// Energy used by accessories (Wh)
    public let accessoriesEnergy: Int

    /// Total energy used (Wh)
    public let totalEnergyUsed: Int

    /// Energy regenerated (Wh)
    public let regenEnergy: Int

    /// Energy used by climate system (Wh)
    public let climateEnergy: Int

    /// Energy used by drivetrain (Wh)
    public let drivetrainEnergy: Int

    /// Energy used for battery care/conditioning (Wh)
    public let batteryCareEnergy: Int

    /// Trip start date
    public let startDate: Date

    /// Trip duration
    public let duration: Duration

    /// Average speed (mph)
    public let avgSpeed: Double

    /// Maximum speed (mph)
    public let maxSpeed: Double

    /// Calculated efficiency in distance-per-kWh, expressed in `units`
    public func efficiency(in units: Distance.Units) -> Double {
        guard totalEnergyUsed > 0 else { return 0 }
        return distance.units.convert(distance.length, to: units) / (Double(totalEnergyUsed) / 1000.0)
    }

    /// Formatted duration string
    public var formattedDuration: String {
        duration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    public init(
        distance: Distance,
        odometer: Distance,
        accessoriesEnergy: Int,
        totalEnergyUsed: Int,
        regenEnergy: Int,
        climateEnergy: Int,
        drivetrainEnergy: Int,
        batteryCareEnergy: Int,
        startDate: Date,
        duration: Duration,
        avgSpeed: Double,
        maxSpeed: Double
    ) {
        self.distance = distance
        self.odometer = odometer
        self.accessoriesEnergy = accessoriesEnergy
        self.totalEnergyUsed = totalEnergyUsed
        self.regenEnergy = regenEnergy
        self.climateEnergy = climateEnergy
        self.drivetrainEnergy = drivetrainEnergy
        self.batteryCareEnergy = batteryCareEnergy
        self.startDate = startDate
        self.duration = duration
        self.avgSpeed = avgSpeed
        self.maxSpeed = maxSpeed
    }
}

// MARK: - Response Container

public struct EVTripSummaryResponse: Codable, Sendable {
    public let trips: [EVTripSummary]

    public init(trips: [EVTripSummary]) {
        self.trips = trips
    }
}

// MARK: - EV Trip Info

/// Represents summary of a specific trip from the tripinfo endpoint
public struct EVTripInfo: Codable, Hashable, Sendable {
    public let date: Date
    public let driveTime: Duration
    public let idleTime: Duration
    public let distance: Distance
    /// Average speed in the API's native unit — matches `distance.units`
    /// per hour (km/h for Europe, the only backend serving this today).
    public let avgSpeed: Double
    /// Maximum speed, same unit convention as `avgSpeed`.
    public let maxSpeed: Double

    public init(date: Date, driveTime: Duration, idleTime: Duration, distance: Distance, avgSpeed: Double, maxSpeed: Double) {
        self.date = date
        self.driveTime = driveTime
        self.idleTime = idleTime
        self.distance = distance
        self.avgSpeed = avgSpeed
        self.maxSpeed = maxSpeed
    }
}
