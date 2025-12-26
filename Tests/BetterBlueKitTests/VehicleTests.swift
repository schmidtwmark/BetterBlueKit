//
//  VehicleTests.swift
//  BetterBlueKit
//
//  Vehicle model tests
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Vehicle Tests")
struct VehicleTests {

    @Test("Vehicle creation with all parameters")
    func testVehicleCreation() {
        let accountId = UUID()
        let odometer = Distance(length: 15000.0, units: .miles)

        let vehicle = Vehicle(
            vin: "KMHL14JA3PA000000",
            regId: "REG123456",
            model: "Elantra Hybrid",
            accountId: accountId,
            isElectric: false,
            generation: 3,
            odometer: odometer,
            vehicleKey: "vehicle_key_123"
        )

        #expect(vehicle.vin == "KMHL14JA3PA000000")
        #expect(vehicle.regId == "REG123456")
        #expect(vehicle.model == "Elantra Hybrid")
        #expect(vehicle.accountId == accountId)
        #expect(vehicle.isElectric == false)
        #expect(vehicle.generation == 3)
        #expect(vehicle.odometer.length == 15000.0)
        #expect(vehicle.odometer.units == .miles)
        #expect(vehicle.vehicleKey == "vehicle_key_123")
    }

    @Test("Vehicle creation without vehicle key")
    func testVehicleCreationWithoutVehicleKey() {
        let accountId = UUID()
        let odometer = Distance(length: 25000.0, units: .kilometers)

        let vehicle = Vehicle(
            vin: "KNDJ23AU1N7000000",
            regId: "REG789012",
            model: "Ioniq 5",
            accountId: accountId,
            isElectric: true,
            generation: 4,
            odometer: odometer
        )

        #expect(vehicle.vin == "KNDJ23AU1N7000000")
        #expect(vehicle.regId == "REG789012")
        #expect(vehicle.model == "Ioniq 5")
        #expect(vehicle.accountId == accountId)
        #expect(vehicle.isElectric == true)
        #expect(vehicle.generation == 4)
        #expect(vehicle.odometer.length == 25000.0)
        #expect(vehicle.odometer.units == .kilometers)
        #expect(vehicle.vehicleKey == nil)
    }

    @Test("Vehicle id property returns vin")
    func testVehicleIdProperty() {
        let vehicle = Vehicle(
            vin: "TEST123VIN456",
            regId: "REG001",
            model: "Test Model",
            accountId: UUID(),
            isElectric: true,
            generation: 2,
            odometer: Distance(length: 0, units: .miles)
        )

        #expect(vehicle.id == "TEST123VIN456")
        #expect(vehicle.id == vehicle.vin)
    }

    @Test("Vehicle Equatable conformance")
    func testVehicleEquatable() {
        let accountId = UUID()
        let odometer = Distance(length: 10000.0, units: .miles)

        let vehicle1 = Vehicle(
            vin: "SAME_VIN_123",
            regId: "REG001",
            model: "Model A",
            accountId: accountId,
            isElectric: true,
            generation: 3,
            odometer: odometer,
            vehicleKey: "key1"
        )

        let vehicle2 = Vehicle(
            vin: "SAME_VIN_123",
            regId: "REG001",
            model: "Model A",
            accountId: accountId,
            isElectric: true,
            generation: 3,
            odometer: odometer,
            vehicleKey: "key1"
        )

        let vehicle3 = Vehicle(
            vin: "DIFFERENT_VIN",
            regId: "REG001",
            model: "Model A",
            accountId: accountId,
            isElectric: true,
            generation: 3,
            odometer: odometer,
            vehicleKey: "key1"
        )

        #expect(vehicle1 == vehicle2)
        #expect(vehicle1 != vehicle3)
    }

    @Test("Vehicle Codable encoding and decoding")
    func testVehicleCodable() throws {
        let accountId = UUID()
        let original = Vehicle(
            vin: "CODABLE_TEST_VIN",
            regId: "REG_CODABLE",
            model: "Codable Model",
            accountId: accountId,
            isElectric: false,
            generation: 2,
            odometer: Distance(length: 5000.0, units: .kilometers),
            vehicleKey: "codable_key"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Vehicle.self, from: encoded)

        #expect(decoded.vin == original.vin)
        #expect(decoded.regId == original.regId)
        #expect(decoded.model == original.model)
        #expect(decoded.accountId == original.accountId)
        #expect(decoded.isElectric == original.isElectric)
        #expect(decoded.generation == original.generation)
        #expect(decoded.odometer.length == original.odometer.length)
        #expect(decoded.odometer.units == original.odometer.units)
        #expect(decoded.vehicleKey == original.vehicleKey)
    }

    @Test("Vehicle Codable without optional vehicle key")
    func testVehicleCodableWithoutVehicleKey() throws {
        let original = Vehicle(
            vin: "NO_KEY_VIN",
            regId: "NO_KEY_REG",
            model: "No Key Model",
            accountId: UUID(),
            isElectric: true,
            generation: 3,
            odometer: Distance(length: 1000.0, units: .miles)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Vehicle.self, from: encoded)

        #expect(decoded.vin == original.vin)
        #expect(decoded.vehicleKey == nil)
    }

    @Test("Vehicle Identifiable conformance")
    func testVehicleIdentifiable() {
        let vehicle = Vehicle(
            vin: "IDENTIFIABLE_VIN",
            regId: "ID_REG",
            model: "ID Model",
            accountId: UUID(),
            isElectric: false,
            generation: 1,
            odometer: Distance(length: 0, units: .miles)
        )

        #expect(vehicle.id == "IDENTIFIABLE_VIN")

        // Test that we can use it in contexts that require Identifiable
        let vehicles = [vehicle]
        let ids = vehicles.map { $0.id }
        #expect(ids == ["IDENTIFIABLE_VIN"])
    }

    // MARK: - Edge Cases

    @Test("Vehicle with zero odometer")
    func testVehicleWithZeroOdometer() {
        let vehicle = Vehicle(
            vin: "ZERO_ODOMETER",
            regId: "ZERO_REG",
            model: "Zero Model",
            accountId: UUID(),
            isElectric: true,
            generation: 1,
            odometer: Distance(length: 0.0, units: .miles)
        )

        #expect(vehicle.odometer.length == 0.0)
        #expect(vehicle.odometer.units == .miles)
    }

    @Test("Vehicle with very high generation number")
    func testVehicleWithHighGeneration() {
        let vehicle = Vehicle(
            vin: "HIGH_GEN_VIN",
            regId: "HIGH_GEN_REG",
            model: "Future Model",
            accountId: UUID(),
            isElectric: true,
            generation: 99,
            odometer: Distance(length: 0, units: .miles)
        )

        #expect(vehicle.generation == 99)
    }

    @Test("Vehicle with empty string properties")
    func testVehicleWithEmptyStrings() {
        let vehicle = Vehicle(
            vin: "",
            regId: "",
            model: "",
            accountId: UUID(),
            isElectric: false,
            generation: 1,
            odometer: Distance(length: 0, units: .miles),
            vehicleKey: ""
        )

        #expect(vehicle.vin == "")
        #expect(vehicle.regId == "")
        #expect(vehicle.model == "")
        #expect(vehicle.vehicleKey == "")
        #expect(vehicle.id == "") // id should still equal vin, even if empty
    }

    @Test("Vehicle with extremely long VIN")
    func testVehicleWithExtremelyLongVIN() {
        let longVIN = String(repeating: "A", count: 100) // Much longer than standard 17-character VIN
        let vehicle = Vehicle(
            vin: longVIN,
            regId: "REG001",
            model: "Test Model",
            accountId: UUID(),
            isElectric: false,
            generation: 1,
            odometer: Distance(length: 0, units: .miles)
        )

        #expect(vehicle.vin == longVIN)
        #expect(vehicle.id == longVIN)
        #expect(vehicle.vin.count == 100)
    }

    @Test("Vehicle with special characters in model name")
    func testVehicleWithSpecialCharactersInModel() {
        let specialModel = "Ioniq 5 N-Line™ (Limited Edition) 🚗 2024.5"
        let vehicle = Vehicle(
            vin: "SPECIAL_CHAR_VIN",
            regId: "REG_SPECIAL",
            model: specialModel,
            accountId: UUID(),
            isElectric: true,
            generation: 4,
            odometer: Distance(length: 1000, units: .kilometers)
        )

        #expect(vehicle.model == specialModel)
        #expect(vehicle.model.contains("™"))
        #expect(vehicle.model.contains("🚗"))
        #expect(vehicle.model.contains("("))
        #expect(vehicle.model.contains(")"))
    }

    @Test("Vehicle generation boundaries")
    func testVehicleGenerationBoundaries() {
        // Test generation 0
        let vehicle0 = Vehicle(
            vin: "GEN_0_VIN",
            regId: "GEN_0_REG",
            model: "Generation 0",
            accountId: UUID(),
            isElectric: false,
            generation: 0,
            odometer: Distance(length: 0, units: .miles)
        )
        #expect(vehicle0.generation == 0)

        // Test negative generation (edge case)
        let vehicleNeg = Vehicle(
            vin: "GEN_NEG_VIN",
            regId: "GEN_NEG_REG",
            model: "Negative Generation",
            accountId: UUID(),
            isElectric: false,
            generation: -1,
            odometer: Distance(length: 0, units: .miles)
        )
        #expect(vehicleNeg.generation == -1)

        // Test very large generation
        let vehicleLarge = Vehicle(
            vin: "GEN_LARGE_VIN",
            regId: "GEN_LARGE_REG",
            model: "Future Generation",
            accountId: UUID(),
            isElectric: true,
            generation: Int.max,
            odometer: Distance(length: 0, units: .miles)
        )
        #expect(vehicleLarge.generation == Int.max)
    }

    @Test("Vehicle with Unicode characters in VIN and regId")
    func testVehicleWithUnicodeCharacters() {
        let unicodeVIN = "VIN_测试_🚙_123"
        let unicodeRegId = "REG_Ñoño_Müller"

        let vehicle = Vehicle(
            vin: unicodeVIN,
            regId: unicodeRegId,
            model: "International Model",
            accountId: UUID(),
            isElectric: true,
            generation: 2,
            odometer: Distance(length: 5000, units: .kilometers)
        )

        #expect(vehicle.vin == unicodeVIN)
        #expect(vehicle.regId == unicodeRegId)
        #expect(vehicle.id == unicodeVIN)
    }

    @Test("Vehicle with maximum distance values")
    func testVehicleWithMaximumDistanceValues() {
        let maxDistance = Distance(length: Double.greatestFiniteMagnitude, units: .miles)

        let vehicle = Vehicle(
            vin: "MAX_DISTANCE_VIN",
            regId: "MAX_DISTANCE_REG",
            model: "High Mileage Vehicle",
            accountId: UUID(),
            isElectric: false,
            generation: 1,
            odometer: maxDistance
        )

        #expect(vehicle.odometer.length == Double.greatestFiniteMagnitude)
        #expect(vehicle.odometer.units == .miles)
    }

    @Test("Vehicle equality with different optional fields")
    func testVehicleEqualityWithOptionalFields() {
        let accountId = UUID()
        let odometer = Distance(length: 10000.0, units: .miles)

        // Vehicle with vehicleKey
        let vehicleWithKey = Vehicle(
            vin: "SAME_VIN_123",
            regId: "REG001",
            model: "Model A",
            accountId: accountId,
            isElectric: true,
            generation: 3,
            odometer: odometer,
            vehicleKey: "key123"
        )

        // Vehicle without vehicleKey
        let vehicleWithoutKey = Vehicle(
            vin: "SAME_VIN_123",
            regId: "REG001",
            model: "Model A",
            accountId: accountId,
            isElectric: true,
            generation: 3,
            odometer: odometer
        )

        // Should not be equal due to different vehicleKey values
        #expect(vehicleWithKey != vehicleWithoutKey)

        // Vehicles with different vehicleKey values
        let vehicleWithDifferentKey = Vehicle(
            vin: "SAME_VIN_123",
            regId: "REG001",
            model: "Model A",
            accountId: accountId,
            isElectric: true,
            generation: 3,
            odometer: odometer,
            vehicleKey: "different_key"
        )

        #expect(vehicleWithKey != vehicleWithDifferentKey)
    }
}
