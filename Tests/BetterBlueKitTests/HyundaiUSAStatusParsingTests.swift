//
//  HyundaiUSAStatusParsingTests.swift
//  BetterBlueKit
//
//  Hyundai USA `rcs/rvs/vehicleStatus` charge-rate parsing. Fixtures are
//  real payloads (trimmed to the fields the parser reads, location
//  dropped) unless marked synthetic. No raw US payload captured during a
//  DC fast charge has turned up, so every DC case here is synthetic.
//

import Foundation
import Testing
@testable import BetterBlueKit

// MARK: - Sample JSON

enum HyundaiUSAStatusSampleJSON {

    /// Wraps a `vehicleStatus` object in the `rcs/rvs/vehicleStatus` envelope.
    static func response(vehicleStatus: String) -> String {
        """
        {
          "hataTID": "00000000-0000-0000-0000-000000000000",
          "vehicleStatus": \(vehicleStatus)
        }
        """
    }

    /// Ioniq 5 charging on AC at 1.4 kW — kia_uvo#1206 (a debug-log dict,
    /// converted to JSON). `realTimePower` and `batteryStndChrgPower`
    /// agree, and there's no `batteryFstChrgPower`.
    static let ioniq5ACCharging = response(vehicleStatus: """
    {
      "dateTime": "2025-08-12T00:20:21Z",
      "fuelLevel": 0,
      "doorLock": true,
      "battery": { "batSoc": 85, "batState": 0 },
      "dte": { "unit": 3, "value": 288 },
      "evStatus": {
        "remainTime2": {
          "etc3": { "unit": 0, "value": 20 },
          "etc2": { "unit": 1, "value": 195 },
          "atc": { "unit": 1, "value": 190 },
          "etc1": { "unit": 1, "value": 3 }
        },
        "batteryStndChrgPower": 1.4,
        "batteryPlugin": 2,
        "realTimePower": 1.4,
        "remainTime": [{ "unit": 1, "value": 190 }],
        "batteryCharge": true,
        "batteryStatus": 75,
        "drvDistance": [
          { "type": 0, "rangeByFuel": {
              "totalAvailableRange": { "unit": 3, "value": 288 },
              "evModeRange": { "unit": 3, "value": 288 } } }
        ],
        "reservChargeInfos": {
          "targetSOClist": [
            { "plugType": 0, "targetSOClevel": 80 },
            { "plugType": 1, "targetSOClevel": 80 }
          ]
        },
        "chargePortDoorOpen": 1
      }
    }
    """)

    /// 2024 Kona Electric charging on AC — egmp-bluelink-scriptable#63
    /// (raw response from api.telematics.hyundaiusa.com). Same shape as
    /// the Ioniq 5: equal Standard / realTime power, no Fast key.
    static let konaACCharging = response(vehicleStatus: """
    {
      "dateTime": "2026-02-14T03:56:46Z",
      "fuelLevel": 0,
      "doorLock": true,
      "battery": { "batSoc": 83, "batState": 0 },
      "evStatus": {
        "batteryDisCharge": false,
        "batteryPlugin": 2,
        "batteryStatus": 39,
        "remainTime": [{ "value": 450, "unit": 1 }],
        "reservChargeInfos": {
          "targetSOClist": [
            { "targetSOClevel": 80, "plugType": 0 },
            { "targetSOClevel": 80, "plugType": 1 }
          ]
        },
        "batteryStndChrgPower": 3.8,
        "remainTime2": {
          "atc": { "value": 450, "unit": 1 },
          "etc3": { "value": 140, "unit": 1 },
          "etc1": { "value": 34, "unit": 1 },
          "etc2": { "value": 640, "unit": 1 }
        },
        "realTimePower": 3.8,
        "batteryCharge": true,
        "drvDistance": [
          { "rangeByFuel": {
              "evModeRange": { "value": 108, "unit": 3 },
              "totalAvailableRange": { "value": 108, "unit": 3 } }, "type": 0 }
        ],
        "chargePortDoorOpen": 1
      }
    }
    """)

    /// 2025 Ioniq 6 parked and unplugged — egmp-bluelink-scriptable#63
    /// (raw). Both power fields are 0 and there's no `realTimePower`.
    static let ioniq6Unplugged = response(vehicleStatus: """
    {
      "dateTime": "2025-10-31T17:43:32Z",
      "doorLock": true,
      "battery": { "batSoc": 94 },
      "evStatus": {
        "batteryDisChargePlugin": 1,
        "batteryFstChrgPower": 0,
        "batteryPlugin": 0,
        "batteryStatus": 88,
        "remainTime": [],
        "reservChargeInfos": {
          "targetSOClist": [
            { "plugType": 0, "targetSOClevel": 100 },
            { "plugType": 1, "targetSOClevel": 100 }
          ]
        },
        "batteryStndChrgPower": 0,
        "remainTime2": {
          "atc": { "value": 0, "unit": 1 },
          "etc3": { "value": 65, "unit": 1 },
          "etc1": { "value": 21, "unit": 1 },
          "etc2": { "value": 560, "unit": 1 }
        },
        "batteryCharge": false,
        "batteryDischrgPower": 0,
        "drvDistance": [
          { "rangeByFuel": {
              "totalAvailableRange": { "value": 261, "unit": 3 },
              "evModeRange": { "value": 261, "unit": 3 },
              "gasModeRange": { "value": 0, "unit": 3 } }, "type": 2 }
        ],
        "v2L": false
      }
    }
    """)

    /// Hyundai USA EV charging on AC with no `realTimePower` — the US
    /// test fixture in openHAB's bluelink binding
    /// (vehicle-status-us.json; its provenance isn't stated).
    static let acChargingWithoutRealTimePower = response(vehicleStatus: """
    {
      "dateTime": "2025-12-18T04:09:28Z",
      "doorLock": true,
      "battery": { "batSoc": 75 },
      "evStatus": {
        "batteryCharge": true,
        "batteryDisChargePlugin": 1,
        "batteryDischrgPower": 7.4,
        "batteryFstChrgPower": 0.0,
        "batteryPlugin": 2,
        "batteryStatus": 42,
        "batteryStndChrgPower": 7.4,
        "drvDistance": [
          { "rangeByFuel": {
              "evModeRange": { "unit": 1, "value": 184.0 },
              "gasModeRange": { "unit": 1, "value": 0.0 },
              "totalAvailableRange": { "unit": 1, "value": 184.0 } }, "type": 2 }
        ],
        "remainTime": [],
        "remainTime2": {
          "atc": { "unit": 1, "value": 265 },
          "etc1": { "unit": 1, "value": 41 },
          "etc2": { "unit": 1, "value": 1680 },
          "etc3": { "unit": 1, "value": 175 }
        },
        "reservChargeInfos": {
          "targetSOClist": [
            { "plugType": 0, "targetSOClevel": 80, "type": 2 },
            { "plugType": 1, "targetSOClevel": 80, "type": 2 }
          ]
        }
      }
    }
    """)
}

// MARK: - Tests

@Suite("Hyundai USA Status Parsing")
struct HyundaiUSAStatusParsingTests {

    @MainActor private func makeClient() -> HyundaiUSAAPIClient {
        HyundaiUSAAPIClient(configuration: APIClientConfiguration(
            region: .usa, brand: .hyundai, username: "test@example.com",
            password: "password123", pin: "1234", accountId: UUID()
        ))
    }

    private func makeVehicle() -> Vehicle {
        Vehicle(
            vin: "KM8KRDDF0SU000000", regId: "REG", model: "IONIQ 5",
            accountId: UUID(), fuelType: .electric, generation: 3,
            odometer: Distance(length: 1000, units: .miles)
        )
    }

    @MainActor private func parse(_ json: String) throws -> VehicleStatus {
        try makeClient().parseVehicleStatusResponse(Data(json.utf8), for: makeVehicle())
    }

    /// Swaps one exact snippet of a fixture, and fails if it isn't there.
    private func tweak(_ json: String, _ old: String, _ new: String) -> String {
        #expect(json.contains(old), "fixture no longer contains \(old)")
        return json.replacingOccurrences(of: old, with: new)
    }

    @Test("AC charging reports the charge rate and time remaining")
    @MainActor func testACCharging() throws {
        let ioniq5 = try #require(try parse(HyundaiUSAStatusSampleJSON.ioniq5ACCharging).evStatus)
        #expect(ioniq5.charging)
        #expect(ioniq5.chargeSpeed == 1.4)
        #expect(ioniq5.chargeTime == .seconds(190 * 60))
        #expect(ioniq5.plugType == .acCharger)
        #expect(ioniq5.evRange.percentage == 75)

        let kona = try #require(try parse(HyundaiUSAStatusSampleJSON.konaACCharging).evStatus)
        #expect(kona.charging)
        #expect(kona.chargeSpeed == 3.8)
        #expect(kona.chargeTime == .seconds(450 * 60))
        #expect(kona.plugType == .acCharger)
    }

    @Test("DC fast charge reports realTimePower, not the AC Standard figure")
    @MainActor func testDCChargeUsesRealTimePower() throws {
        // Synthetic, shaped after hyundai_kia_connect_api#1270's account:
        // Standard holds the car's AC rate, realTimePower the DC rate.
        var json = HyundaiUSAStatusSampleJSON.ioniq5ACCharging
        json = tweak(json, #""batteryStndChrgPower": 1.4,"#, #""batteryStndChrgPower": 7.2,"#)
        json = tweak(json, #""realTimePower": 1.4,"#, #""realTimePower": 150.0,"#)
        let ev = try #require(try parse(json).evStatus)
        #expect(ev.charging)
        #expect(ev.chargeSpeed == 150)
    }

    @Test("DC rate reported in batteryFstChrgPower still shows")
    @MainActor func testDCChargeInFastPowerField() throws {
        // Synthetic, shaped after pyvisioniq's account of a 143 kW DC
        // session: Standard at 0 and the rate in batteryFstChrgPower.
        let fast = tweak(
            HyundaiUSAStatusSampleJSON.konaACCharging,
            #""batteryStndChrgPower": 3.8,"#,
            #""batteryStndChrgPower": 0, "batteryFstChrgPower": 143.0,"#
        )
        let withoutRealTime = tweak(fast, #""realTimePower": 3.8,"#, "")
        #expect(try parse(withoutRealTime).evStatus?.chargeSpeed == 143)

        // Hypothetical: were realTimePower to lag on DC, Fast is a floor.
        let lagging = tweak(fast, #""realTimePower": 3.8,"#, #""realTimePower": 0,"#)
        #expect(try parse(lagging).evStatus?.chargeSpeed == 143)
    }

    @Test("Without realTimePower the rate falls back to batteryStndChrgPower")
    @MainActor func testFallbackToStandardPower() throws {
        let ev = try #require(
            try parse(HyundaiUSAStatusSampleJSON.acChargingWithoutRealTimePower).evStatus
        )
        #expect(ev.charging)
        #expect(ev.chargeSpeed == 7.4)
        #expect(ev.chargeTime == .seconds(265 * 60))
    }

    @Test("A rate only counts while charging, and never below 0")
    @MainActor func testChargeRateGatedOnCharging() throws {
        let unplugged = try #require(try parse(HyundaiUSAStatusSampleJSON.ioniq6Unplugged).evStatus)
        #expect(!unplugged.charging)
        #expect(!unplugged.pluggedIn)
        #expect(unplugged.chargeSpeed == 0)

        // Synthetic tweaks of the real Kona payload.
        let stopped = tweak(
            HyundaiUSAStatusSampleJSON.konaACCharging,
            #""batteryCharge": true,"#, #""batteryCharge": false,"#
        )
        let idle = try #require(try parse(stopped).evStatus)
        #expect(!idle.charging)
        #expect(idle.chargeSpeed == 0)

        let negative = tweak(
            HyundaiUSAStatusSampleJSON.konaACCharging,
            #""realTimePower": 3.8,"#, #""realTimePower": -2.0, "batteryFstChrgPower": -1.0,"#
        )
        #expect(try parse(negative).evStatus?.chargeSpeed == 0)
    }
}
