//
//  AdvancedErrorHandlingTests.swift
//  BetterBlueKit
//
//  Advanced error scenarios and edge cases
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Advanced Error Handling Tests")
struct AdvancedErrorHandlingTests {

    // MARK: - Malformed API Response Tests

    @Test("API response with missing payload structure")
    @MainActor func testAPIResponseWithMissingPayload() throws {
        let provider = makeKiaProvider()
        let vehicle = makeTestVehicle()

        let invalidResponseVariants = [
            // Missing payload entirely
            """
            {
              "status": "success",
              "message": "OK"
            }
            """,

            // Payload is not an object
            """
            {
              "payload": "invalid_string"
            }
            """,

            // Payload is an array instead of object
            """
            {
              "payload": ["not", "an", "object"]
            }
            """,

            // Empty payload
            """
            {
              "payload": {}
            }
            """
        ]

        for invalidJSON in invalidResponseVariants {
            let data = Data(invalidJSON.utf8)

            #expect(throws: APIError.self) {
                try provider.parseVehicleStatusResponse(data, for: vehicle)
            }
        }
    }

    @Test("API response with corrupted vehicleInfoList")
    @MainActor func testAPIResponseWithCorruptedVehicleInfoList() throws {
        let provider = makeKiaProvider()
        let vehicle = makeTestVehicle()

        let corruptedVariants = [
            // vehicleInfoList is not an array
            """
            {
              "payload": {
                "vehicleInfoList": "not_an_array"
              }
            }
            """,

            // vehicleInfoList is empty array
            """
            {
              "payload": {
                "vehicleInfoList": []
              }
            }
            """,

            // vehicleInfoList contains non-object elements
            """
            {
              "payload": {
                "vehicleInfoList": ["string", 123, true]
              }
            }
            """
        ]

        for invalidJSON in corruptedVariants {
            let data = Data(invalidJSON.utf8)

            #expect(throws: APIError.self) {
                try provider.parseVehicleStatusResponse(data, for: vehicle)
            }
        }
    }

    @Test("Partial data corruption in vehicle status")
    @MainActor func testPartialDataCorruptionInVehicleStatus() throws {
        let provider = makeKiaProvider()
        let vehicle = makeTestVehicle()

        // Test with corrupted but parseable data
        let partiallyCorruptedJSON = """
        {
          "payload": {
            "vehicleInfoList": [{
              "lastVehicleInfo": {
                "vehicleStatusRpt": {
                  "vehicleStatus": {
                    "doorLock": "not_a_boolean",
                    "evStatus": {
                      "batteryStatus": "not_a_number",
                      "batteryCharge": null,
                      "drvDistance": "not_an_array"
                    },
                    "climate": {
                      "airTemp": {
                        "value": null,
                        "unit": "not_a_number"
                      }
                    }
                  }
                },
                "location": {
                  "coord": {
                    "lat": "not_a_number",
                    "lon": "not_a_number"
                  }
                }
              }
            }]
          }
        }
        """

        let data = Data(partiallyCorruptedJSON.utf8)

        // Should not throw, but should handle gracefully with defaults
        let status = try provider.parseVehicleStatusResponse(data, for: vehicle)

        // Verify graceful handling of corrupted data
        #expect(status.vin == vehicle.vin)
        #expect(status.location.latitude == 0.0) // Should default to 0 for invalid number
        #expect(status.location.longitude == 0.0) // Should default to 0 for invalid number
        #expect(status.lockStatus == VehicleStatus.LockStatus.unknown) // Should handle invalid boolean
    }

    // MARK: - API Version Mismatch Tests

    @Test("API response with unknown fields")
    @MainActor func testAPIResponseWithUnknownFields() throws {
        let provider = makeKiaProvider()
        let vehicle = makeTestVehicle()

        let futureVersionJSON = """
        {
          "payload": {
            "apiVersion": "2.0",
            "newFeature": "future_value",
            "vehicleInfoList": [{
              "lastVehicleInfo": {
                "vehicleStatusRpt": {
                  "vehicleStatus": {
                    "doorLock": true,
                    "futureField": "unknown_value",
                    "newTechnology": {
                      "quantumBattery": 150,
                      "holoDisplay": true
                    },
                    "climate": {
                      "airCtrl": false,
                      "airTemp": {
                        "value": "72",
                        "unit": 1
                      },
                      "defrost": false,
                      "heatingAccessory": {
                        "steeringWheel": 0
                      },
                      "aiPoweredClimate": {
                        "enabled": true,
                        "model": "GPT-10"
                      }
                    }
                  }
                },
                "location": {
                  "coord": {
                    "lat": 40.7128,
                    "lon": -74.0060
                  },
                  "accuracy": "centimeter",
                  "satellite": "GPS-III"
                }
              }
            }]
          }
        }
        """

        let data = Data(futureVersionJSON.utf8)

        // Should parse successfully, ignoring unknown fields
        let status = try provider.parseVehicleStatusResponse(data, for: vehicle)

        #expect(status.vin == vehicle.vin)
        #expect(status.lockStatus == VehicleStatus.LockStatus.locked)
        #expect(status.location.latitude == 40.7128)
        #expect(status.location.longitude == -74.0060)
        #expect(status.climateStatus.airControlOn == false)
        #expect(status.climateStatus.temperature.value == 72.0)
    }

    // MARK: - Rate Limiting Response Tests

    @Test("Rate limiting error response parsing")
    @MainActor func testRateLimitingErrorResponse() throws {
        let provider = makeKiaProvider()

        let rateLimitJSON = """
        {
          "status": {
            "statusCode": 429,
            "errorCode": 429,
            "errorType": 2,
            "errorMessage": "Too many requests. Please wait before trying again.",
            "retryAfter": 60
          }
        }
        """

        let data = Data(rateLimitJSON.utf8)

        #expect(throws: APIError.self) {
            try provider.parseCommandResponse(data)
        }
    }

    @Test("Server maintenance response parsing")
    @MainActor func testServerMaintenanceResponse() throws {
        let provider = makeKiaProvider()

        let maintenanceJSON = """
        {
          "status": {
            "statusCode": 503,
            "errorCode": 503,
            "errorType": 3,
            "errorMessage": "Service temporarily unavailable due to scheduled maintenance. Please try again later.",
            "maintenanceWindow": {
              "start": "2025-10-10T02:00:00Z",
              "end": "2025-10-10T06:00:00Z"
            }
          }
        }
        """

        let data = Data(maintenanceJSON.utf8)

        #expect(throws: APIError.self) {
            try provider.parseCommandResponse(data)
        }
    }

    // MARK: - Authentication Edge Cases

    @Test("Expired session error handling")
    @MainActor func testExpiredSessionErrorHandling() throws {
        let provider = makeKiaProvider()

        let expiredSessionJSON = """
        {
          "status": {
            "statusCode": 1,
            "errorCode": 1003,
            "errorType": 1,
            "errorMessage": "Session Key is invalid or expired. Please re-authenticate."
          }
        }
        """

        let data = Data(expiredSessionJSON.utf8)

        do {
            try provider.parseCommandResponse(data)
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as APIError {
            #expect(error.errorType == .invalidCredentials)
            #expect(error.message.lowercased().contains("session"))
            #expect(error.message.lowercased().contains("expired"))
        }
    }

    @Test("Invalid PIN error handling")
    @MainActor func testInvalidPINErrorHandling() {
        let pinError = APIError.invalidPin("PIN is incorrect", apiName: "TestAPI")

        #expect(pinError.errorType == .invalidPin)
        #expect(pinError.apiName == "TestAPI")
        #expect(pinError.message.contains("PIN is incorrect"))
        // Note: APIError doesn't have a statusCode property in this implementation
    }

    // MARK: - Network Timeout Simulation

    @Test("Network timeout error characteristics")
    func testNetworkTimeoutErrorCharacteristics() {
        let timeoutLog = HTTPLog(
            timestamp: Date(),
            accountId: UUID(),
            requestType: .sendCommand,
            method: "POST",
            url: "https://example.com/api/timeout",
            requestHeaders: ["Content-Type": "application/json"],
            requestBody: "{}",
            responseStatus: nil, // No status code for timeout
            responseHeaders: [:],
            responseBody: nil,
            error: "Request timeout",
            duration: 30.0 // Long duration indicating timeout
        )

        #expect(timeoutLog.responseStatus == nil)
        #expect(timeoutLog.isSuccess == false)
        #expect(timeoutLog.statusText == "Error")
        #expect(timeoutLog.duration >= 30.0)
        #expect(timeoutLog.formattedDuration.contains("30"))
    }

    // MARK: - JSON Structure Variations

    @Test("Different JSON encoding formats")
    @MainActor func testDifferentJSONEncodingFormats() throws {
        let provider = makeKiaProvider()
        let vehicle = makeTestVehicle()

        // Test with different valid JSON formatting
        let compactJSON = """
        {"payload":{"vehicleInfoList":[{"lastVehicleInfo":{"vehicleStatusRpt":{"vehicleStatus":{"doorLock":true,"climate":{"airCtrl":false,"airTemp":{"value":"70","unit":1},"defrost":false,"heatingAccessory":{"steeringWheel":0}}}},"location":{"coord":{"lat":40.0,"lon":-74.0}}}}]}}
        """

        let prettyJSON = """
        {
          "payload" : {
            "vehicleInfoList" : [ {
              "lastVehicleInfo" : {
                "vehicleStatusRpt" : {
                  "vehicleStatus" : {
                    "doorLock" : true,
                    "climate" : {
                      "airCtrl" : false,
                      "airTemp" : {
                        "value" : "70",
                        "unit" : 1
                      },
                      "defrost" : false,
                      "heatingAccessory" : {
                        "steeringWheel" : 0
                      }
                    }
                  }
                },
                "location" : {
                  "coord" : {
                    "lat" : 40.0,
                    "lon" : -74.0
                  }
                }
              }
            } ]
          }
        }
        """

        // Both should parse successfully
        let compactData = Data(compactJSON.utf8)
        let prettyData = Data(prettyJSON.utf8)

        let status1 = try provider.parseVehicleStatusResponse(compactData, for: vehicle)
        let status2 = try provider.parseVehicleStatusResponse(prettyData, for: vehicle)

        // Results should be identical
        #expect(status1.vin == status2.vin)
        #expect(status1.lockStatus == status2.lockStatus)
        #expect(status1.location.latitude == status2.location.latitude)
        #expect(status1.location.longitude == status2.location.longitude)
    }

    // MARK: - Memory and Performance Edge Cases

    @Test("Deeply nested JSON handling")
    func testDeeplyNestedJSONHandling() throws {
        // Create deeply nested JSON structure
        let nestedJSON = """
        {
          "level1": {
            "level2": {
              "level3": {
                "level4": {
                  "level5": {
                    "level6": {
                      "level7": {
                        "level8": {
                          "level9": {
                            "level10": {
                              "data": "deep_value"
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """

        let data = Data(nestedJSON.utf8)

        // Should parse without stack overflow or performance issues
        let startTime = Date()
        let json = try JSONSerialization.jsonObject(with: data)
        let endTime = Date()

        #expect(json is [String: Any])
        #expect(endTime.timeIntervalSince(startTime) < 0.1) // Should be fast
    }

    // MARK: - Helper Methods

    @MainActor private func makeKiaProvider() -> KiaAPIEndpointProviderUSA {
        let config = APIClientConfiguration(
            region: .usa,
            brand: .kia,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )
        return KiaAPIEndpointProviderUSA(configuration: config)
    }

    private func makeTestVehicle() -> Vehicle {
        Vehicle(
            vin: "KNDJ23AU1N7000000",
            regId: "REG789012",
            model: "EV6",
            accountId: UUID(),
            isElectric: true,
            generation: 4,
            odometer: Distance(length: 25000.0, units: .miles),
            vehicleKey: "test_vehicle_key"
        )
    }
}
