//
//  EVTripDetails.swift
//  BetterBlueKit
//
//  EV Trip Details for energy consumption tracking
//

import Foundation

// MARK: - EV Trip Details

/// Represents details of an EV trip including energy consumption breakdown
public struct EVTripDetail: Codable, Hashable, Sendable, Identifiable {
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

    /// Trip duration in seconds
    public let durationSeconds: Int

    /// Average speed (mph)
    public let avgSpeed: Double

    /// Maximum speed (mph)
    public let maxSpeed: Double

    /// Calculated efficiency in distance-per-kWh, expressed in `units`
    public func efficiency(in units: Distance.Units) -> Double {
        guard totalEnergyUsed > 0 else { return 0 }
        return distance.units.convert(distance.length, to: units) / (Double(totalEnergyUsed) / 1000.0)
    }

    /// Trip duration as Duration
    public var duration: Duration {
        .seconds(durationSeconds)
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
        durationSeconds: Int,
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
        self.durationSeconds = durationSeconds
        self.avgSpeed = avgSpeed
        self.maxSpeed = maxSpeed
    }
}

// MARK: - Response Container

public struct EVTripDetailsResponse: Codable, Sendable {
    public let trips: [EVTripDetail]

    public init(trips: [EVTripDetail]) {
        self.trips = trips
    }
}
