//
//  Vehicle.swift
//  BetterBlueKit
//
//  Vehicle model definitions
//

import Foundation

// MARK: - Vehicle Models

public struct Vehicle: Codable, Identifiable, Equatable, Sendable {
    public var id: String { vin }
    public var regId: String, vin: String, model: String
    public var accountId: UUID, fuelType: FuelType
    public var generation: Int, odometer: Distance, vehicleKey: String?

    public init(vin: String, regId: String, model: String, accountId: UUID,
                fuelType: FuelType, generation: Int, odometer: Distance, vehicleKey: String? = nil) {
        (self.vin, self.regId, self.model, self.accountId) = (vin, regId, model, accountId)
        (self.fuelType, self.generation, self.odometer, self.vehicleKey) =
            (fuelType, generation, odometer, vehicleKey)
    }
}
