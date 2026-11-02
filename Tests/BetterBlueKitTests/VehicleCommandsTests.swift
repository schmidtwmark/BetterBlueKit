//
//  VehicleCommandsTests.swift
//  BetterBlueKit
//
//  VehicleCommands and ClimateOptions tests
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("VehicleCommands Tests")
struct VehicleCommandsTests {

    // MARK: - ClimateOptions Tests

    @Test("ClimateOptions default initialization")
    func testClimateOptionsDefaults() {
        let options = ClimateOptions()

        #expect(options.climate == true)
        #expect(options.temperature.value == 72.0)
        #expect(options.temperature.units == .fahrenheit)
        #expect(options.defrost == false)
        #expect(options.heatValue == 0)
        #expect(options.duration == 10)
        #expect(options.frontLeftSeat == 0)
        #expect(options.frontRightSeat == 0)
        #expect(options.rearLeftSeat == 0)
        #expect(options.rearRightSeat == 0)
        #expect(options.steeringWheel == 0)
    }

    @Test("ClimateOptions custom values")
    func testClimateOptionsCustomValues() {
        var options = ClimateOptions()
        options.climate = false
        options.temperature = Temperature(value: 68.0, units: .fahrenheit)
        options.defrost = true
        options.rearDefrostEnabled = true
        options.duration = 15
        options.frontLeftSeat = 3
        options.frontRightSeat = 2
        options.rearLeftSeat = 1
        options.rearRightSeat = 2
        options.steeringWheel = 1

        #expect(options.climate == false)
        #expect(options.temperature.value == 68.0)
        #expect(options.defrost == true)
        #expect(options.rearDefrostEnabled == true)
        #expect(options.heatValue == 4) // rear defrost + steering wheel = 4
        #expect(options.duration == 15)
        #expect(options.frontLeftSeat == 3)
        #expect(options.frontRightSeat == 2)
        #expect(options.rearLeftSeat == 1)
        #expect(options.rearRightSeat == 2)
        #expect(options.steeringWheel == 1)
    }

    @Test("ClimateOptions Equatable")
    func testClimateOptionsEquatable() {
        let options1 = ClimateOptions()
        var options2 = ClimateOptions()

        #expect(options1 == options2)

        options2.temperature = Temperature(value: 70.0, units: .fahrenheit)
        #expect(options1 != options2)
    }

    @Test("ClimateOptions Codable")
    func testClimateOptionsCodable() throws {
        var original = ClimateOptions()
        original.climate = true
        original.temperature = Temperature(value: 22.0, units: .celsius)
        original.defrost = true
        original.rearDefrostEnabled = false
        original.duration = 20
        original.frontLeftSeat = 2
        original.frontRightSeat = 1

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClimateOptions.self, from: encoded)

        #expect(decoded.climate == original.climate)
        #expect(decoded.temperature.value == original.temperature.value)
        #expect(decoded.temperature.units == original.temperature.units)
        #expect(decoded.defrost == original.defrost)
        #expect(decoded.rearDefrostEnabled == original.rearDefrostEnabled)
        #expect(decoded.duration == original.duration)
        #expect(decoded.frontLeftSeat == original.frontLeftSeat)
        #expect(decoded.frontRightSeat == original.frontRightSeat)
    }

    // MARK: - VehicleCommand Tests

    @MainActor
    @Test(arguments: [
        (VehicleCommand.startCharge, FuelType.gas),
        (.startCharge, .electric),
        (.stopCharge, .electric),
        (.setTargetSOC(acLevel: 80, dcLevel: 80), .electric),
        (.startClimate(ClimateOptions()), .electric),
        (.stopClimate, .electric),
        (.startClimate(ClimateOptions()), .phev),
        (.stopClimate, .phev)
    ]) func `Genesis rejects unsupported EV commands`(command: VehicleCommand, fuelType: FuelType) async {
        let session = URLSession(configuration: .ephemeral)

        // An invalidated session prevents requests to the live service if this guard regresses.
        session.invalidateAndCancel()
        let client = GenesisCanadaAPIClient(configuration: APIClientConfiguration(
            region: .canada, brand: .genesis, username: "test@example.com", password: "password123",
            pin: "1234", accountId: UUID()
        ), urlSession: session)
        let vehicle = Vehicle(
            vin: "TESTVIN0000000000", regId: "reg", model: "Genesis", accountId: client.accountId,
            fuelType: fuelType, generation: 3, odometer: Distance(length: 0, units: .kilometers)
        )
        do {
            try await client.sendCommand(
                for: vehicle, command: command,
                authToken: AuthToken(accessToken: "test", refreshToken: "", expiresAt: .distantFuture)
            )
            Issue.record("Expected an unsupported-feature error")
        } catch let error as APIError {
            #expect(error.errorType == .featureNotSupported)
            #expect(error.apiName == "GenesisCanada")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("VehicleCommand simple commands")
    func testSimpleCommands() {
        let lockCommand = VehicleCommand.lock
        let unlockCommand = VehicleCommand.unlock
        let stopClimateCommand = VehicleCommand.stopClimate
        let startChargeCommand = VehicleCommand.startCharge
        let stopChargeCommand = VehicleCommand.stopCharge

        // These should compile and be valid enum cases
        #expect(true) // If we get here, the enum cases are valid
    }

    @Test("VehicleCommand startClimate with options")
    func testStartClimateCommand() {
        var options = ClimateOptions()
        options.temperature = Temperature(value: 75.0, units: .fahrenheit)
        options.defrost = true

        let command = VehicleCommand.startClimate(options)

        if case let .startClimate(extractedOptions) = command {
            #expect(extractedOptions.temperature.value == 75.0)
            #expect(extractedOptions.defrost == true)
        } else {
            #expect(false, "Command should be startClimate")
        }
    }
}
