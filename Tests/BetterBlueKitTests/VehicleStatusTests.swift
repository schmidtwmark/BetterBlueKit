//
//  VehicleStatusTests.swift
//  BetterBlueKit
//
//  VehicleStatus and nested types tests
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("VehicleStatus Tests")
struct VehicleStatusTests {
    
    // MARK: - FuelRange Tests
    
    @Test("FuelRange creation")
    func testFuelRangeCreation() {
        let range = Distance(length: 250.0, units: .miles)
        let fuelRange = VehicleStatus.FuelRange(range: range, percentage: 75.5)
        
        #expect(fuelRange.range.length == 250.0)
        #expect(fuelRange.range.units == .miles)
        #expect(fuelRange.percentage == 75.5)
    }
    
    @Test("FuelRange Codable")
    func testFuelRangeCodable() throws {
        let original = VehicleStatus.FuelRange(
            range: Distance(length: 180.0, units: .kilometers),
            percentage: 60.0
        )
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VehicleStatus.FuelRange.self, from: encoded)
        
        #expect(decoded.range.length == original.range.length)
        #expect(decoded.range.units == original.range.units)
        #expect(decoded.percentage == original.percentage)
    }
    
    // MARK: - EVStatus Tests
    
    @Test("EVStatus creation")
    func testEVStatusCreation() {
        let evRange = VehicleStatus.FuelRange(
            range: Distance(length: 200.0, units: .miles),
            percentage: 85.0
        )
        
        let evStatus = VehicleStatus.EVStatus(
            charging: true,
            chargeSpeed: 50.0,
            pluggedIn: true,
            evRange: evRange
        )
        
        #expect(evStatus.charging == true)
        #expect(evStatus.chargeSpeed == 50.0)
        #expect(evStatus.pluggedIn == true)
        #expect(evStatus.evRange.percentage == 85.0)
        #expect(evStatus.evRange.range.length == 200.0)
    }
    
    @Test("EVStatus Codable")
    func testEVStatusCodable() throws {
        let original = VehicleStatus.EVStatus(
            charging: false,
            chargeSpeed: 0.0,
            pluggedIn: false,
            evRange: VehicleStatus.FuelRange(
                range: Distance(length: 150.0, units: .kilometers),
                percentage: 40.0
            )
        )
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VehicleStatus.EVStatus.self, from: encoded)
        
        #expect(decoded.charging == original.charging)
        #expect(decoded.chargeSpeed == original.chargeSpeed)
        #expect(decoded.pluggedIn == original.pluggedIn)
        #expect(decoded.evRange.percentage == original.evRange.percentage)
    }
    
    // MARK: - Location Tests
    
    @Test("Location creation")
    func testLocationCreation() {
        let location = VehicleStatus.Location(latitude: 37.7749, longitude: -122.4194)
        
        #expect(location.latitude == 37.7749)
        #expect(location.longitude == -122.4194)
    }
    
    @Test("Location debug description")
    func testLocationDebug() {
        let location = VehicleStatus.Location(latitude: 40.7128, longitude: -74.0060)
        #expect(location.debug == "40.7128°, -74.006°")
    }
    
    @Test("Location Equatable")
    func testLocationEquatable() {
        let location1 = VehicleStatus.Location(latitude: 37.7749, longitude: -122.4194)
        let location2 = VehicleStatus.Location(latitude: 37.7749, longitude: -122.4194)
        let location3 = VehicleStatus.Location(latitude: 40.7128, longitude: -74.0060)
        
        #expect(location1 == location2)
        #expect(location1 != location3)
    }
    
    @Test("Location Codable")
    func testLocationCodable() throws {
        let original = VehicleStatus.Location(latitude: 51.5074, longitude: -0.1278)
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VehicleStatus.Location.self, from: encoded)
        
        #expect(decoded.latitude == original.latitude)
        #expect(decoded.longitude == original.longitude)
    }
    
    // MARK: - LockStatus Tests
    
    @Test("LockStatus initialization from bool")
    func testLockStatusFromBool() {
        #expect(VehicleStatus.LockStatus(locked: true) == .locked)
        #expect(VehicleStatus.LockStatus(locked: false) == .unlocked)
        #expect(VehicleStatus.LockStatus(locked: nil) == .unknown)
    }
    
    @Test("LockStatus toggle")
    func testLockStatusToggle() {
        var status1 = VehicleStatus.LockStatus.locked
        status1.toggle()
        #expect(status1 == .unlocked)
        
        var status2 = VehicleStatus.LockStatus.unlocked
        status2.toggle()
        #expect(status2 == .locked)
        
        var status3 = VehicleStatus.LockStatus.unknown
        status3.toggle()
        #expect(status3 == .unknown)
    }
    
    @Test("LockStatus Codable")
    func testLockStatusCodable() throws {
        let statuses: [VehicleStatus.LockStatus] = [.locked, .unlocked, .unknown]
        
        for status in statuses {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(VehicleStatus.LockStatus.self, from: encoded)
            #expect(decoded == status)
        }
    }
    
    // MARK: - ClimateStatus Tests
    
    @Test("ClimateStatus creation")
    func testClimateStatusCreation() {
        let temperature = Temperature(value: 72.0, units: .fahrenheit)
        let climateStatus = VehicleStatus.ClimateStatus(
            defrostOn: true,
            airControlOn: false,
            steeringWheelHeatingOn: true,
            temperature: temperature
        )
        
        #expect(climateStatus.defrostOn == true)
        #expect(climateStatus.airControlOn == false)
        #expect(climateStatus.steeringWheelHeatingOn == true)
        #expect(climateStatus.temperature.value == 72.0)
        #expect(climateStatus.temperature.units == .fahrenheit)
    }
    
    @Test("ClimateStatus Codable")
    func testClimateStatusCodable() throws {
        let original = VehicleStatus.ClimateStatus(
            defrostOn: false,
            airControlOn: true,
            steeringWheelHeatingOn: false,
            temperature: Temperature(value: 20.0, units: .celsius)
        )
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VehicleStatus.ClimateStatus.self, from: encoded)
        
        #expect(decoded.defrostOn == original.defrostOn)
        #expect(decoded.airControlOn == original.airControlOn)
        #expect(decoded.steeringWheelHeatingOn == original.steeringWheelHeatingOn)
        #expect(decoded.temperature.value == original.temperature.value)
        #expect(decoded.temperature.units == original.temperature.units)
    }
    
    // MARK: - VehicleStatus Tests
    
    @Test("VehicleStatus creation with electric vehicle")
    func testVehicleStatusElectricVehicle() {
        let evRange = VehicleStatus.FuelRange(
            range: Distance(length: 250.0, units: .miles),
            percentage: 80.0
        )
        let evStatus = VehicleStatus.EVStatus(
            charging: false,
            chargeSpeed: 0.0,
            pluggedIn: true,
            evRange: evRange
        )
        let location = VehicleStatus.Location(latitude: 37.7749, longitude: -122.4194)
        let climateStatus = VehicleStatus.ClimateStatus(
            defrostOn: false,
            airControlOn: true,
            steeringWheelHeatingOn: false,
            temperature: Temperature(value: 22.0, units: .celsius)
        )
        
        let vehicleStatus = VehicleStatus(
            vin: "EV_TEST_VIN",
            gasRange: nil,
            evStatus: evStatus,
            location: location,
            lockStatus: .locked,
            climateStatus: climateStatus,
            odometer: Distance(length: 15000.0, units: .miles),
            syncDate: Date()
        )
        
        #expect(vehicleStatus.vin == "EV_TEST_VIN")
        #expect(vehicleStatus.gasRange == nil)
        #expect(vehicleStatus.evStatus != nil)
        #expect(vehicleStatus.evStatus?.charging == false)
        #expect(vehicleStatus.evStatus?.pluggedIn == true)
        #expect(vehicleStatus.location.latitude == 37.7749)
        #expect(vehicleStatus.lockStatus == .locked)
        #expect(vehicleStatus.climateStatus.airControlOn == true)
        #expect(vehicleStatus.odometer?.length == 15000.0)
    }
    
    @Test("VehicleStatus creation with gas vehicle")
    func testVehicleStatusGasVehicle() {
        let gasRange = VehicleStatus.FuelRange(
            range: Distance(length: 300.0, units: .miles),
            percentage: 65.0
        )
        let location = VehicleStatus.Location(latitude: 40.7128, longitude: -74.0060)
        let climateStatus = VehicleStatus.ClimateStatus(
            defrostOn: true,
            airControlOn: false,
            steeringWheelHeatingOn: true,
            temperature: Temperature(value: 75.0, units: .fahrenheit)
        )
        
        let vehicleStatus = VehicleStatus(
            vin: "GAS_TEST_VIN",
            gasRange: gasRange,
            evStatus: nil,
            location: location,
            lockStatus: .unlocked,
            climateStatus: climateStatus
        )
        
        #expect(vehicleStatus.vin == "GAS_TEST_VIN")
        #expect(vehicleStatus.gasRange != nil)
        #expect(vehicleStatus.gasRange?.percentage == 65.0)
        #expect(vehicleStatus.evStatus == nil)
        #expect(vehicleStatus.lockStatus == .unlocked)
        #expect(vehicleStatus.climateStatus.defrostOn == true)
        #expect(vehicleStatus.odometer == nil)
        #expect(vehicleStatus.syncDate == nil)
    }
    
    @Test("VehicleStatus lastUpdated defaults to current time")
    func testVehicleStatusLastUpdated() {
        let vehicleStatus = VehicleStatus(
            vin: "TIME_TEST_VIN",
            location: VehicleStatus.Location(latitude: 0, longitude: 0),
            lockStatus: .unknown,
            climateStatus: VehicleStatus.ClimateStatus(
                defrostOn: false,
                airControlOn: false,
                steeringWheelHeatingOn: false,
                temperature: Temperature(value: 70.0, units: .fahrenheit)
            )
        )
        
        let now = Date()
        let timeDifference = abs(vehicleStatus.lastUpdated.timeIntervalSince(now))
        #expect(timeDifference < 1.0) // Should be within 1 second
    }
    
    @Test("VehicleStatus Codable")
    func testVehicleStatusCodable() throws {
        let original = VehicleStatus(
            vin: "CODABLE_VIN",
            gasRange: VehicleStatus.FuelRange(
                range: Distance(length: 200.0, units: .kilometers),
                percentage: 50.0
            ),
            evStatus: nil,
            location: VehicleStatus.Location(latitude: 51.5074, longitude: -0.1278),
            lockStatus: .locked,
            climateStatus: VehicleStatus.ClimateStatus(
                defrostOn: false,
                airControlOn: true,
                steeringWheelHeatingOn: false,
                temperature: Temperature(value: 18.0, units: .celsius)
            ),
            odometer: Distance(length: 20000.0, units: .kilometers),
            syncDate: Date()
        )
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VehicleStatus.self, from: encoded)
        
        #expect(decoded.vin == original.vin)
        #expect(decoded.gasRange?.percentage == original.gasRange?.percentage)
        #expect(decoded.evStatus == nil)
        #expect(decoded.location.latitude == original.location.latitude)
        #expect(decoded.lockStatus == original.lockStatus)
        #expect(decoded.climateStatus.airControlOn == original.climateStatus.airControlOn)
    }
    
    // MARK: - Edge Cases
    
    @Test("VehicleStatus with extreme coordinates")
    func testVehicleStatusExtremeCoordinates() {
        let location = VehicleStatus.Location(latitude: -90.0, longitude: -180.0)
        let vehicleStatus = VehicleStatus(
            vin: "EXTREME_VIN",
            location: location,
            lockStatus: .unknown,
            climateStatus: VehicleStatus.ClimateStatus(
                defrostOn: false,
                airControlOn: false,
                steeringWheelHeatingOn: false,
                temperature: Temperature(value: 0.0, units: .celsius)
            )
        )
        
        #expect(vehicleStatus.location.latitude == -90.0)
        #expect(vehicleStatus.location.longitude == -180.0)
        #expect(vehicleStatus.location.debug == "-90.0°, -180.0°")
    }
    
    @Test("VehicleStatus with zero percentage fuel")
    func testVehicleStatusZeroFuel() {
        let gasRange = VehicleStatus.FuelRange(
            range: Distance(length: 0.0, units: .miles),
            percentage: 0.0
        )
        
        let vehicleStatus = VehicleStatus(
            vin: "ZERO_FUEL_VIN",
            gasRange: gasRange,
            location: VehicleStatus.Location(latitude: 0, longitude: 0),
            lockStatus: .locked,
            climateStatus: VehicleStatus.ClimateStatus(
                defrostOn: false,
                airControlOn: false,
                steeringWheelHeatingOn: false,
                temperature: Temperature(value: 70.0, units: .fahrenheit)
            )
        )
        
        #expect(vehicleStatus.gasRange?.percentage == 0.0)
        #expect(vehicleStatus.gasRange?.range.length == 0.0)
    }
}