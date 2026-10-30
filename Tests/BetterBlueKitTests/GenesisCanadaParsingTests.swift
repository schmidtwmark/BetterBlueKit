//
//  GenesisCanadaParsingTests.swift
//  BetterBlueKit
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Genesis Canada Parsing")
struct GenesisCanadaParsingTests {

    @MainActor
    private func makeClient() -> GenesisCanadaAPIClient {
        let config = APIClientConfiguration(
            region: .canada,
            brand: .genesis,
            username: "test@example.com",
            password: "password123",
            pin: "1234",
            accountId: UUID()
        )
        return GenesisCanadaAPIClient(configuration: config)
    }

    private func makeVehicle(fuelType: FuelType, odometer: Double? = nil) -> Vehicle {
        Vehicle(
            vin: "TESTVIN0000000000",
            regId: "reg",
            model: "GV70",
            accountId: UUID(),
            fuelType: fuelType,
            generation: 2,
            odometer: odometer.map { Distance(length: $0, units: .kilometers) }
                ?? Distance(length: 42000, units: .kilometers)
        )
    }

    private func response(code: String, desc: String) -> Data {
        Data("""
        {"responseHeader":{"responseCode":1,"responseDesc":"Failure"},
        "error":{"errorCode":"\(code)","errorDesc":"\(desc)"}}
        """.utf8)
    }

    @Test @MainActor func `Genesis Canada vehicle list parses a gasoline GV70`() throws {
        let config = APIClientConfiguration(
            region: .canada,
            brand: .genesis,
            username: "test@example.com",
            password: "password123",
            pin: "1234",
            accountId: UUID()
        )
        let data = Data("""
        {
          "responseHeader": { "responseCode": 0 },
          "result": {
            "vehicles": [{
              "vehicleId": "vehicle-id",
              "nickName": "My GV70",
              "modelName": "GV70",
              "modelYear": "2024",
              "fuelKindCode": "G",
              "genType": "G1",
              "vin": "TESTVIN0000000000",
              "mainBatteryType": false
            }]
          }
        }
        """.utf8)

        let vehicles = try GenesisCanadaAPIClient(configuration: config).parseCanadaVehiclesResponse(data)
        #expect(vehicles.count == 1)
        let vehicle = try #require(vehicles.first)
        #expect(vehicle.vin == "TESTVIN0000000000")
        #expect(vehicle.regId == "vehicle-id")
        #expect(vehicle.model == "My GV70")
        #expect(vehicle.modelYear == 2024)
        #expect(vehicle.fuelType == .gas)

        // G1 retains Canada's existing fallback. Canada request paths do not use Vehicle.generation.
        #expect(vehicle.generation == 3)
    }

    @Test @MainActor func `Genesis OTP challenge accepts response code zero`() {
        let data = Data("""
        {
          "responseHeader": { "responseCode": 0 },
          "error": { "errorCode": "7110", "errorDesc": "OTP required" }
        }
        """.utf8)
        #expect(makeClient().isOTPRequiredResponse(data))
    }

    /// Trimmed from a real 2024 gas GV70 response. Coordinates are synthetic;
    /// the other values retain the reported units.
    @Test @MainActor func `Genesis gasoline status uses the supplied location without EV data`() throws {
        let data = Data("""
        {
          "responseHeader": {"responseCode": 0},
          "result": {
            "status": {
              "lastStatusDate": "20261026014351",
              "fuelLevel": 84, "dte": {"value": 297, "unit": 3},
              "doorLock": false, "engine": false, "airCtrlOn": false, "airTempUnit": "C",
              "doorOpen": {"frontLeft": 1, "frontRight": 1, "backLeft": 0, "backRight": 1},
              "trunkOpen": true, "hoodOpen": false
            },
            "vehicleLocation": {"coord": {"lat": 49.0, "lon": -123.0}}
          }
        }
        """.utf8)
        let status = try makeClient().parseCanadaVehicleStatusResponse(data, for: makeVehicle(fuelType: .gas))

        #expect(status.gasRange == VehicleStatus.FuelRange(range: Distance(length: 297, units: .miles), percentage: 84))
        #expect(status.evStatus == nil)
        #expect(status.climateStatus.temperature == nil)
        #expect(status.location == VehicleStatus.Location(latitude: 49, longitude: -123))
        #expect(status.lockStatus == .unlocked)
        #expect(status.engineOn == false)
        #expect(status.doorOpen == VehicleStatus.DoorStatus(frontLeft: true, frontRight: true, backLeft: false, backRight: true))
        #expect(status.trunkOpen == true)
        #expect(status.hoodOpen == false)
        #expect(status.syncDate == ISO8601DateFormatter().date(from: "2026-10-26T01:43:51Z"))
    }

    @MainActor
    @Test(arguments: [
        (["7402", "7403", "7404", "7406", "7549", "7602", "7606"], APIError.ErrorType.invalidCredentials),
        (["7310", "7311", "7312", "7313", "7314", "7315", "7316"], .invalidPin),
        (["6533"], .concurrentRequest)
    ]) func `Genesis Canada error codes preserve their error type`(codes: [String], errorType: APIError.ErrorType) {
        // A French errorDesc defeats the old substring matching; the
        // code must carry the classification.
        for code in codes {
            let data = response(code: code, desc: "Les informations de connexion sont incorrectes.")
            do {
                _ = try makeClient().parseCanadaResponse(data, context: "test")
                Issue.record("expected throw for code \(code)")
            } catch let error as APIError {
                #expect(error.errorType == errorType, "code \(code)")
            } catch {
                Issue.record("unexpected error type for code \(code)")
            }
        }
    }
}
