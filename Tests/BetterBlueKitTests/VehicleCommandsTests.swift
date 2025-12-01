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
    
    // MARK: - getBodyForCommand Tests
    
    @Test("getBodyForCommand lock command")
    func testGetBodyForCommandLock() {
        let command = VehicleCommand.lock
        let body = command.getBodyForCommand(
            vin: "TEST_VIN",
            isElectric: true,
            generation: 3,
            username: "test@example.com"
        )
        
        // Lock command should return empty body
        #expect(body.isEmpty)
    }
    
    @Test("getBodyForCommand unlock command")
    func testGetBodyForCommandUnlock() {
        let command = VehicleCommand.unlock
        let body = command.getBodyForCommand(
            vin: "TEST_VIN",
            isElectric: false,
            generation: 2,
            username: "test@example.com"
        )
        
        // Unlock command should return empty body
        #expect(body.isEmpty)
    }
    
    @Test("getBodyForCommand startCharge command")
    func testGetBodyForCommandStartCharge() {
        let command = VehicleCommand.startCharge
        let body = command.getBodyForCommand(
            vin: "TEST_VIN",
            isElectric: true,
            generation: 3,
            username: "test@example.com"
        )
        
        #expect(body["chargeRatio"] as? Int == 100)
    }
    
    @Test("getBodyForCommand stopCharge command")
    func testGetBodyForCommandStopCharge() {
        let command = VehicleCommand.stopCharge
        let body = command.getBodyForCommand(
            vin: "TEST_VIN",
            isElectric: true,
            generation: 3,
            username: "test@example.com"
        )
        
        // Stop charge should return empty body
        #expect(body.isEmpty)
    }
    
    @Test("getBodyForCommand stopClimate command")
    func testGetBodyForCommandStopClimate() {
        let command = VehicleCommand.stopClimate
        let body = command.getBodyForCommand(
            vin: "TEST_VIN",
            isElectric: true,
            generation: 3,
            username: "test@example.com"
        )
        
        // Stop climate should return empty body
        #expect(body.isEmpty)
    }
    
    @Test("getBodyForCommand startClimate electric vehicle generation 3")
    func testGetBodyForCommandStartClimateElectricGen3() {
        var options = ClimateOptions()
        options.climate = true
        options.temperature = Temperature(value: 72.0, units: .fahrenheit)
        options.defrost = true
        options.rearDefrostEnabled = true
        options.duration = 15
        options.frontLeftSeat = 2
        options.frontRightSeat = 1
        options.rearLeftSeat = 1
        options.rearRightSeat = 0

        let command = VehicleCommand.startClimate(options)
        let body = command.getBodyForCommand(
            vin: "TEST_VIN",
            isElectric: true,
            generation: 3,
            username: "test@example.com"
        )

        #expect(body["airCtrl"] as? Int == 1)
        #expect(body["defrost"] as? Bool == true)
        #expect(body["heating1"] as? Int == 2) // rear defrost only = 2
        #expect(body["igniOnDuration"] as? Int == 15)
        
        if let airTemp = body["airTemp"] as? [String: Any] {
            #expect(airTemp["value"] as? String == "72")
            #expect(airTemp["unit"] as? Int == 1)
        } else {
            #expect(false, "airTemp should be present")
        }
        
        if let seatInfo = body["seatHeaterVentInfo"] as? [String: Any] {
            // Seat values are converted: warm mode adds 5, so 2->7, 1->6, 1->6, 0->0
            #expect(seatInfo["drvSeatHeatState"] as? Int == 7)
            #expect(seatInfo["astSeatHeatState"] as? Int == 6)
            #expect(seatInfo["rlSeatHeatState"] as? Int == 6)
            #expect(seatInfo["rrSeatHeatState"] as? Int == 0)
        } else {
            #expect(false, "seatHeaterVentInfo should be present")
        }
    }
    
    @Test("getBodyForCommand startClimate electric vehicle generation 2")
    func testGetBodyForCommandStartClimateElectricGen2() {
        var options = ClimateOptions()
        options.climate = false
        options.temperature = Temperature(value: 20.0, units: .celsius)
        options.defrost = false
        options.rearDefrostEnabled = false

        let command = VehicleCommand.startClimate(options)
        let body = command.getBodyForCommand(
            vin: "TEST_VIN",
            isElectric: true,
            generation: 2,
            username: "test@example.com"
        )

        #expect(body["airCtrl"] as? Int == 0)
        #expect(body["defrost"] as? Bool == false)
        #expect(body["heating1"] as? Int == 0) // no rear defrost, no steering wheel = 0
        
        if let airTemp = body["airTemp"] as? [String: Any] {
            #expect(airTemp["value"] as? String == "20")
            #expect(airTemp["unit"] as? Int == 0) // Celsius
        }
        
        // Generation 2 should not have igniOnDuration or seatHeaterVentInfo
        #expect(body["igniOnDuration"] == nil)
        #expect(body["seatHeaterVentInfo"] == nil)
    }
    
    @Test("getBodyForCommand startClimate gas vehicle")
    func testGetBodyForCommandStartClimateGas() {
        var options = ClimateOptions()
        options.climate = true
        options.temperature = Temperature(value: 75.0, units: .fahrenheit)
        options.defrost = true
        options.rearDefrostEnabled = true
        options.steeringWheel = 1
        options.duration = 10
        options.frontLeftSeat = 3
        options.frontRightSeat = 2
        options.rearLeftSeat = 1
        options.rearRightSeat = 1

        let command = VehicleCommand.startClimate(options)
        let body = command.getBodyForCommand(
            vin: "GAS_VIN",
            isElectric: false,
            generation: 3,
            username: "gas@example.com"
        )

        #expect(body["Ims"] as? Int == 0)
        #expect(body["airCtrl"] as? Int == 1)
        #expect(body["defrost"] as? Bool == true)
        #expect(body["heating1"] as? Int == 4) // rear defrost + steering wheel = 4
        #expect(body["igniOnDuration"] as? Int == 10)
        #expect(body["username"] as? String == "gas@example.com")
        #expect(body["vin"] as? String == "GAS_VIN")
        
        if let airTemp = body["airTemp"] as? [String: Any] {
            #expect(airTemp["unit"] as? Int == 1)
            #expect(airTemp["value"] as? Int == 75)
        }
        
        if let seatInfo = body["seatHeaterVentInfo"] as? [String: Any] {
            // Seat values are converted: warm mode adds 5, so 3->8, 2->7, 1->6, 1->6
            #expect(seatInfo["drvSeatHeatState"] as? Int == 8)
            #expect(seatInfo["astSeatHeatState"] as? Int == 7)
            #expect(seatInfo["rlSeatHeatState"] as? Int == 6)
            #expect(seatInfo["rrSeatHeatState"] as? Int == 6)
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("getBodyForCommand with extreme temperature values")
    func testGetBodyForCommandExtremeTemperature() {
        var options = ClimateOptions()
        options.temperature = Temperature(value: 100.0, units: .fahrenheit)
        
        let command = VehicleCommand.startClimate(options)
        let body = command.getBodyForCommand(
            vin: "TEST_VIN",
            isElectric: true,
            generation: 3,
            username: "test@example.com"
        )
        
        if let airTemp = body["airTemp"] as? [String: Any] {
            #expect(airTemp["value"] as? String == "100")
        }
    }
    
    @Test("getBodyForCommand with zero duration")
    func testGetBodyForCommandZeroDuration() {
        var options = ClimateOptions()
        options.duration = 0
        
        let command = VehicleCommand.startClimate(options)
        let body = command.getBodyForCommand(
            vin: "TEST_VIN",
            isElectric: true,
            generation: 3,
            username: "test@example.com"
        )
        
        #expect(body["igniOnDuration"] as? Int == 0)
    }
    
    @Test("getBodyForCommand with negative seat heating values")
    func testGetBodyForCommandNegativeSeatValues() {
        var options = ClimateOptions()
        options.frontLeftSeat = -1
        options.frontRightSeat = -2
        
        let command = VehicleCommand.startClimate(options)
        let body = command.getBodyForCommand(
            vin: "TEST_VIN",
            isElectric: true,
            generation: 3,
            username: "test@example.com"
        )
        
        if let seatInfo = body["seatHeaterVentInfo"] as? [String: Any] {
            // Seat values are converted even for negative: -1+5=4, -2+5=3
            #expect(seatInfo["drvSeatHeatState"] as? Int == 4)
            #expect(seatInfo["astSeatHeatState"] as? Int == 3)
        }
    }
}