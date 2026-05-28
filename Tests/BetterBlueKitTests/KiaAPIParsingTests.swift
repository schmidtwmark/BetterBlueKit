//
//  KiaAPIParsingTests.swift
//  BetterBlueKit
//
//  Tests for Kia API client functionality
//
//  Note: Parsing tests have been removed as the parsing methods are now
//  private implementation details of KiaUSAAPIClient. This file retains
//  sample JSON data for documentation and integration testing reference.
//

import Foundation
import Testing
@testable import BetterBlueKit

// MARK: - Sample JSON Data

/// Sample Kia API JSON responses for documentation and testing reference
enum KiaSampleJSON {

    /// Sample vehicle status response from Kia USA API
    static let vehicleStatus = """
    {
      "payload": {
        "vehicleInfoList": [{
          "lastVehicleInfo": {
            "linkStatus" : 0,
            "vehicleStatusRpt" : {
              "reportDate" : {
                "utc" : "20251003012955",
                "offset" : -7
              },
              "vehicleStatus" : {
                "distanceToEmpty" : {
                  "value" : 279,
                  "unit" : 3
                },
                "doorLock" : true,
                "syncDate" : {
                  "utc" : "20251003012546",
                  "offset" : -7
                },
                "evStatus" : {
                  "batteryPlugin" : 0,
                  "batteryStatus" : 76,
                  "batteryCharge" : false,
                  "drvDistance" : [
                    {
                      "type" : 2,
                      "rangeByFuel" : {
                        "evModeRange" : {
                          "value" : 279,
                          "unit" : 3
                        },
                        "totalAvailableRange" : {
                          "value" : 279,
                          "unit" : 3
                        }
                      }
                    }
                  ],
                  "targetSOC" : [
                    {
                      "targetSOClevel" : 80,
                      "plugType" : 1
                    },
                    {
                      "targetSOClevel" : 80,
                      "plugType" : 0
                    }
                  ]
                },
                "climate" : {
                  "airCtrl" : false,
                  "airTemp" : {
                    "value" : "72",
                    "unit" : 1
                  },
                  "heatingAccessory" : {
                    "steeringWheel" : 0
                  },
                  "defrost" : false
                }
              }
            },
            "location" : {
              "syncDate" : {
                "utc" : "20251003012257",
                "offset" : -4
              },
              "coord" : {
                "lat" : 38.964186,
                "lon" : -84.516544
              }
            }
          }
        }]
      }
    }
    """

    /// Sample login response requiring MFA
    static let mfaRequired = """
    {
      "payload": {
        "otpKey": "abc123otpkey",
        "hasEmail": true,
        "hasPhone": true,
        "email": "t***@example.com",
        "phone": "***-***-1234",
        "rmTokenExpired": false
      }
    }
    """

    /// Sample vehicles list response
    static let vehiclesList = """
    {
      "payload": {
        "vehicleSummary": [
          {
            "vin": "KNDJ23AU1N7000000",
            "vehicleIdentifier": "REG123456",
            "nickName": "My EV6",
            "vehicleKey": "key123abc",
            "genType": "4",
            "fuelType": 1,
            "mileage": 25000
          }
        ]
      }
    }
    """

    /// Sample error response
    static let errorResponse = """
    {
      "status": {
        "statusCode": 1,
        "errorCode": 1003,
        "errorType": 1,
        "errorMessage": "Session Key is invalid or expired"
      }
    }
    """
}

// MARK: - Kia API Client Tests

@Suite("Kia API Client Tests")
struct KiaAPIClientTests {

    @Test("KiaUSAAPIClient initialization")
    @MainActor func testKiaClientInitialization() {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .kia,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )

        let client = KiaUSAAPIClient(configuration: config)

        #expect(client.apiName == "KiaUSA")
        #expect(client.supportsMFA() == true)
    }

    @Test("KiaUSAAPIClient supports MFA")
    @MainActor func testKiaClientSupportsMFA() {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .kia,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )

        let client = KiaUSAAPIClient(configuration: config)
        #expect(client.supportsMFA() == true)
    }

    @MainActor private func makeKiaUSClient() -> KiaUSAAPIClient {
        KiaUSAAPIClient(configuration: APIClientConfiguration(
            region: .usa, brand: .kia, username: "test@example.com",
            password: "password123", pin: "0000", accountId: UUID()
        ))
    }

    private func makeVehicle() -> Vehicle {
        Vehicle(
            vin: "KNDC3DLC5N0000000", regId: "REG", model: "EV6",
            accountId: UUID(), fuelType: .electric, generation: 3,
            odometer: Distance(length: 1000, units: .miles),
            vehicleKey: "vk"
        )
    }

    @Test("Kia US climate always sends Fahrenheit (unit 1)")
    @MainActor func testKiaUSClimateForcesFahrenheit() {
        let client = makeKiaUSClient()
        var options = ClimateOptions()
        // Celsius preset — must be converted to F + unit 1.
        options.temperature = Temperature(value: 22, units: .celsius)

        let body = client.commandBody(for: .startClimate(options), vehicle: makeVehicle())
        let remoteClimate = body["remoteClimate"] as? [String: Any]
        let airTemp = remoteClimate?["airTemp"] as? [String: Any]
        // 22°C ≈ 71.6°F → rounds to 72.
        #expect(airTemp?["unit"] as? Int == 1)
        #expect(airTemp?["value"] as? String == "72")
    }

    @Test("Kia US climate clamps out-of-range temps to LOW/HIGH")
    @MainActor func testKiaUSClimateClampsTemps() {
        let client = makeKiaUSClient()
        let vehicle = makeVehicle()

        var cold = ClimateOptions()
        cold.temperature = Temperature(value: 55, units: .fahrenheit)
        let coldBody = client.commandBody(for: .startClimate(cold), vehicle: vehicle)
        let coldTemp = (coldBody["remoteClimate"] as? [String: Any])?["airTemp"] as? [String: Any]
        #expect(coldTemp?["value"] as? String == "LOW")

        var hot = ClimateOptions()
        hot.temperature = Temperature(value: 90, units: .fahrenheit)
        let hotBody = client.commandBody(for: .startClimate(hot), vehicle: vehicle)
        let hotTemp = (hotBody["remoteClimate"] as? [String: Any])?["airTemp"] as? [String: Any]
        #expect(hotTemp?["value"] as? String == "HIGH")
    }

    @Test("Kia US climate omits heatVentSeat when no seat is set")
    @MainActor func testKiaUSClimateOmitsSeatsWhenUnset() {
        let client = makeKiaUSClient()
        let options = ClimateOptions() // all seats default 0, no ventilation
        let body = client.commandBody(for: .startClimate(options), vehicle: makeVehicle())
        let remoteClimate = body["remoteClimate"] as? [String: Any]
        #expect(remoteClimate?["heatVentSeat"] == nil)
    }

    @Test("Kia US climate includes heatVentSeat when a seat is set")
    @MainActor func testKiaUSClimateIncludesSeatsWhenSet() {
        let client = makeKiaUSClient()
        var options = ClimateOptions()
        options.frontLeftSeat = 2 // driver seat heat level 2 (medium heat)
        let body = client.commandBody(for: .startClimate(options), vehicle: makeVehicle())
        let remoteClimate = body["remoteClimate"] as? [String: Any]
        let seats = remoteClimate?["heatVentSeat"] as? [String: [String: Int]]
        #expect(seats != nil)
        // Medium heat → type 1 (heat), level 3, step 2.
        #expect(seats?["driverSeat"]?["heatVentType"] == 1)
        #expect(seats?["driverSeat"]?["heatVentLevel"] == 3)
        #expect(seats?["driverSeat"]?["heatVentStep"] == 2)
    }
}

// MARK: - JSON Format Documentation Tests

@Suite("Kia JSON Format Tests")
struct KiaJSONFormatTests {

    @Test("Vehicle status JSON is valid")
    func testVehicleStatusJSONValid() throws {
        let data = Data(KiaSampleJSON.vehicleStatus.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json != nil)
        #expect(json?["payload"] != nil)
    }

    @Test("MFA required JSON is valid")
    func testMFARequiredJSONValid() throws {
        let data = Data(KiaSampleJSON.mfaRequired.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json != nil)
        #expect(json?["payload"] != nil)

        let payload = json?["payload"] as? [String: Any]
        #expect(payload?["otpKey"] as? String == "abc123otpkey")
        #expect(payload?["hasEmail"] as? Bool == true)
    }

    @Test("Vehicles list JSON is valid")
    func testVehiclesListJSONValid() throws {
        let data = Data(KiaSampleJSON.vehiclesList.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json != nil)

        let payload = json?["payload"] as? [String: Any]
        let vehicles = payload?["vehicleSummary"] as? [[String: Any]]
        #expect(vehicles?.count == 1)
        #expect(vehicles?.first?["vin"] as? String == "KNDJ23AU1N7000000")
    }

    @Test("Error response JSON is valid")
    func testErrorResponseJSONValid() throws {
        let data = Data(KiaSampleJSON.errorResponse.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json != nil)

        let status = json?["status"] as? [String: Any]
        #expect(status?["errorCode"] as? Int == 1003)
        #expect((status?["errorMessage"] as? String)?.contains("expired") == true)
    }
}
