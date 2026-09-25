//
//  KiaUSAStatusParsingTests.swift
//  BetterBlueKit
//
//  Kia USA `cmm/gvi` status parsing — charge rate, time remaining and
//  the gas range. Fixtures are real payloads (trimmed to the fields the
//  parser reads, location zeroed) unless marked synthetic.
//

import Foundation
import Testing
@testable import BetterBlueKit

// MARK: - Sample JSON

enum KiaUSAStatusSampleJSON {

    /// Wraps a `vehicleStatus` object in the `cmm/gvi` envelope.
    static func gvi(vehicleStatus: String) -> String {
        """
        {
          "status": { "statusCode": 0, "errorType": 0, "errorCode": 0 },
          "payload": {
            "vehicleInfoList": [{
              "lastVehicleInfo": {
                "vehicleStatusRpt": {
                  "statusType": "2",
                  "vehicleStatus": \(vehicleStatus)
                },
                "location": { "coord": { "lat": 0.0, "lon": 0.0, "alt": 0.0, "type": 0 } }
              }
            }]
          }
        }
        """
    }

    /// 2026 EV9 GT-Line (ccNC) AC charging — kia_uvo#1312. Same car
    /// generation as issue #107. `realTimePower` is the charge rate in
    /// kW, the ETA is one `remainChargeType: 4` entry, and `fuelLevel`
    /// is the number 0 next to a `distanceToEmpty` equal to EV range.
    static let ev9Charging = gvi(vehicleStatus: """
    {
      "climate": { "airCtrl": false, "defrost": false, "airTemp": { "value": "72", "unit": 1 },
                   "heatingAccessory": { "steeringWheel": 0, "sideMirror": 0, "rearWindow": 0 } },
      "engine": false,
      "doorLock": true,
      "doorStatus": { "frontLeft": 0, "frontRight": 0, "backLeft": 0, "backRight": 0, "trunk": 0, "hood": 0 },
      "lowFuelLight": false,
      "evStatus": {
        "batteryCharge": true,
        "batteryStatus": 43,
        "batteryPlugin": 4,
        "batteryPrecondition": false,
        "remainChargeTime": [
          { "remainChargeType": 4, "timeInterval": { "value": 225, "unit": 4 } }
        ],
        "drvDistance": [
          { "type": 2, "rangeByFuel": {
              "evModeRange": { "value": 120.55, "unit": 3 },
              "totalAvailableRange": { "value": 120.55, "unit": 3 } } }
        ],
        "syncDate": { "utc": "20250918070534", "offset": -7.0 },
        "targetSOC": [
          { "plugType": 1, "targetSOClevel": 80, "dte": { "type": 0, "rangeByFuel": {
              "gasModeRange": { "value": 0.0, "unit": 3 },
              "evModeRange": { "value": 375.0, "unit": 3 },
              "totalAvailableRange": { "value": 375.0, "unit": 3 } } } },
          { "plugType": 0, "targetSOClevel": 80, "dte": { "type": 0, "rangeByFuel": {
              "gasModeRange": { "value": 0.0, "unit": 3 },
              "evModeRange": { "value": 375.0, "unit": 3 },
              "totalAvailableRange": { "value": 375.0, "unit": 3 } } } }
        ],
        "pluggedInState": 1,
        "v2lStatus": 0,
        "v2xStatus": 0,
        "dischargeRemainTime": 0,
        "dischargeSocLimit": 20,
        "realTimePower": 11.3,
        "wirelessCharging": false,
        "batteryConditioning": 0,
        "chargingDoorState": 1,
        "chargingCurrent": 1
      },
      "ign3": true,
      "transCond": true,
      "distanceToEmpty": { "value": 120.55, "unit": 3 },
      "tirePressure": { "all": 0, "frontLeft": 0, "frontRight": 0, "rearLeft": 0, "rearRight": 0 },
      "syncDate": { "utc": "20250918070534", "offset": -7.0 },
      "batteryStatus": { "stateOfCharge": 89, "sensorStatus": 0, "deliveryMode": 1, "warning": 100 },
      "fuelLevel": 0,
      "washerFluidStatus": false
    }
    """)

    /// 2024 EV9 Land parked and unplugged — dahlb/ha_kia_hyundai#186.
    /// Three what-if ETAs (DC / L1 / L2), `realTimePower: 0`,
    /// `fuelLevel: 0`.
    static let ev9Unplugged = gvi(vehicleStatus: """
    {
      "engine": false,
      "doorLock": true,
      "doorStatus": { "frontLeft": 0, "frontRight": 0, "backLeft": 0, "backRight": 0, "trunk": 0, "hood": 0 },
      "lowFuelLight": false,
      "evStatus": {
        "batteryCharge": false,
        "batteryStatus": 59,
        "batteryPlugin": 0,
        "batteryPrecondition": false,
        "remainChargeTime": [
          { "remainChargeType": 1, "timeInterval": { "value": 39, "unit": 4 } },
          { "remainChargeType": 2, "timeInterval": { "value": 1100, "unit": 4 } },
          { "remainChargeType": 3, "timeInterval": { "value": 240, "unit": 4 } }
        ],
        "drvDistance": [
          { "type": 2, "rangeByFuel": {
              "evModeRange": { "value": 189, "unit": 3 },
              "totalAvailableRange": { "value": 189, "unit": 3 } } }
        ],
        "syncDate": { "utc": "20241227054006", "offset": -8 },
        "targetSOC": [
          { "plugType": 0, "targetSOClevel": 100 },
          { "plugType": 1, "targetSOClevel": 100 }
        ],
        "pluggedInState": 0,
        "v2lStatus": 0,
        "v2xStatus": 0,
        "dischargeRemainTime": 0,
        "dischargeSocLimit": 20,
        "realTimePower": 0,
        "wirelessCharging": false,
        "batteryConditioning": 0,
        "chargingDoorState": 2,
        "chargingCurrent": 1
      },
      "ign3": false,
      "transCond": true,
      "distanceToEmpty": { "value": 188.48, "unit": 3 },
      "syncDate": { "utc": "20241227054006", "offset": -8 },
      "batteryStatus": { "stateOfCharge": 89, "sensorStatus": 0 },
      "fuelLevel": 0
    }
    """)

    /// 2022 EV6 GT-Line plugged in on L2 but not charging —
    /// BetterBlueKit#5 (raw). Only the L2 estimate is listed, and there
    /// is no `realTimePower`, `fuelLevel` or `distanceToEmpty`.
    static let ev6PluggedNotCharging = gvi(vehicleStatus: """
    {
      "climate": { "airCtrl": false, "defrost": false, "airTemp": { "value": "72", "unit": 1 },
                   "heatingAccessory": { "steeringWheel": 0, "sideMirror": 0, "rearWindow": 0 } },
      "engine": false,
      "doorLock": false,
      "doorStatus": { "frontLeft": 0, "frontRight": 0, "backLeft": 0, "backRight": 0, "trunk": 0, "hood": 0 },
      "lowFuelLight": false,
      "evStatus": {
        "batteryCharge": false,
        "batteryStatus": 62,
        "batteryPlugin": 2,
        "remainChargeTime": [
          { "remainChargeType": 3, "timeInterval": { "value": 90, "unit": 4 } }
        ],
        "drvDistance": [
          { "type": 2, "rangeByFuel": {
              "gasModeRange": { "value": 0.0, "unit": 3 },
              "evModeRange": { "value": 184.0, "unit": 3 },
              "totalAvailableRange": { "value": 184.0, "unit": 3 } } }
        ],
        "syncDate": { "utc": "20251008200029", "offset": -4.0 },
        "targetSOC": [
          { "plugType": 0, "targetSOClevel": 80 },
          { "plugType": 1, "targetSOClevel": 80 }
        ],
        "wirelessCharging": false
      },
      "ign3": false,
      "transCond": true,
      "tirePressure": { "all": 0 },
      "syncDate": { "utc": "20251008200029", "offset": -4.0 },
      "batteryStatus": { "stateOfCharge": 97, "deliveryMode": 1, "warning": 65, "powerAutoCutMode": 2 }
    }
    """)

    /// 2019 Niro EV charging on L2 — kia_uvo#100. Predates
    /// `realTimePower`, so there's an ETA but no rate.
    static let niroEVCharging = gvi(vehicleStatus: """
    {
      "climate": { "airCtrl": false, "defrost": false, "airTemp": { "value": "72", "unit": 1 },
                   "heatingAccessory": { "steeringWheel": 0, "sideMirror": 0, "rearWindow": 0 } },
      "engine": false,
      "doorLock": true,
      "doorStatus": { "frontLeft": 0, "frontRight": 0, "backLeft": 0, "backRight": 0, "trunk": 0, "hood": 0 },
      "lowFuelLight": false,
      "evStatus": {
        "batteryCharge": true,
        "batteryStatus": 80,
        "batteryPlugin": 2,
        "remainChargeTime": [
          { "remainChargeType": 3, "timeInterval": { "value": 95, "unit": 4 } }
        ],
        "drvDistance": [
          { "type": 2, "rangeByFuel": {
              "evModeRange": { "value": 227, "unit": 3 },
              "totalAvailableRange": { "value": 227, "unit": 3 } } }
        ],
        "syncDate": { "utc": "20211108005846", "offset": -8 },
        "targetSOC": [
          { "plugType": 0, "targetSOClevel": 90 },
          { "plugType": 1, "targetSOClevel": 90 }
        ]
      },
      "ign3": true,
      "transCond": true,
      "tirePressure": { "all": 0 },
      "syncDate": { "utc": "20211108005846", "offset": -8 },
      "batteryStatus": { "stateOfCharge": 87, "sensorStatus": 0 }
    }
    """)

    /// Synthetic gas car: a positive `fuelLevel` plus `distanceToEmpty`
    /// and no `evStatus` — the shape the gas-range parser reads.
    static let gasCar = gvi(vehicleStatus: """
    {
      "engine": false,
      "doorLock": true,
      "doorStatus": { "frontLeft": 0, "frontRight": 0, "backLeft": 0, "backRight": 0, "trunk": 0, "hood": 0 },
      "lowFuelLight": false,
      "distanceToEmpty": { "value": 342, "unit": 3 },
      "syncDate": { "utc": "20250918070534", "offset": -7.0 },
      "fuelLevel": 61
    }
    """)

    /// 2018 Niro PHEV — kia_uvo#558 (vehicle-list fuelType 7). No
    /// top-level `fuelLevel` or `distanceToEmpty`; its gas range exists
    /// only as the evStatus `gasModeRange`.
    static let niroPHEV = niroPHEV(topLevel: "")

    /// Synthetic PHEV: the real Niro PHEV plus a positive `fuelLevel` and
    /// a `distanceToEmpty` longer than its gas-only `gasModeRange`. A
    /// PHEV that sends these must keep its gas range.
    static let phevWithFuel = niroPHEV(topLevel: """
      "fuelLevel": 40,
      "distanceToEmpty": { "value": 72, "unit": 3 },
    """)

    private static func niroPHEV(topLevel: String) -> String {
        gvi(vehicleStatus: """
        {
        \(topLevel)
          "engine": false,
          "doorLock": true,
          "lowFuelLight": false,
          "evStatus": {
            "batteryCharge": false,
            "batteryStatus": 16,
            "batteryPlugin": 0,
            "remainChargeTime": [
              { "remainChargeType": 1, "timeInterval": { "value": 0, "unit": 4 } },
              { "remainChargeType": 2, "timeInterval": { "value": 380, "unit": 4 } },
              { "remainChargeType": 3, "timeInterval": { "value": 140, "unit": 4 } }
            ],
            "drvDistance": [
              { "type": 2, "rangeByFuel": {
                  "gasModeRange": { "value": 60, "unit": 3 },
                  "evModeRange": { "value": 0, "unit": 3 },
                  "totalAvailableRange": { "value": 60, "unit": 3 } } }
            ],
            "syncDate": { "utc": "20230106214927", "offset": -8 }
          },
          "syncDate": { "utc": "20230106214927", "offset": -8 }
        }
        """)
    }
}

// MARK: - Tests

@Suite("Kia USA Status Parsing")
struct KiaUSAStatusParsingTests {

    @MainActor private func makeClient() -> KiaUSAAPIClient {
        KiaUSAAPIClient(configuration: APIClientConfiguration(
            region: .usa, brand: .kia, username: "test@example.com",
            password: "password123", pin: "0000", accountId: UUID()
        ))
    }

    // The Kia USA status parser ignores `vehicle.fuelType` (the app's
    // copy may be a stale self-heal), so the payload alone has to decide
    // whether there's a gas tank.
    private func makeVehicle() -> Vehicle {
        Vehicle(
            vin: "KNDC3DLC5N0000000", regId: "REG", model: "EV9",
            accountId: UUID(), fuelType: .electric, generation: 3,
            odometer: Distance(length: 1000, units: .miles),
            vehicleKey: "vk"
        )
    }

    @MainActor private func parse(_ json: String) throws -> VehicleStatus {
        try makeClient().parseVehicleStatusResponse(Data(json.utf8), for: makeVehicle())
    }

    @Test("Charging EV9 reports the charge rate and time remaining (issue #107)")
    @MainActor func testEV9ChargingRateAndTime() throws {
        let ev = try #require(try parse(KiaUSAStatusSampleJSON.ev9Charging).evStatus)
        #expect(ev.charging)
        #expect(ev.chargeSpeed == 11.3)
        #expect(ev.chargeTime == .seconds(225 * 60))
        #expect(ev.plugType == .acCharger)
        #expect(ev.evRange.percentage == 43)
        #expect(ev.targetSocAC == 80)
        #expect(ev.targetSocDC == 80)
    }

    @Test("EV reporting fuelLevel 0 gets no phantom gas range (issue #107)")
    @MainActor func testEVFuelLevelZeroHasNoGasRange() throws {
        let charging = try parse(KiaUSAStatusSampleJSON.ev9Charging)
        #expect(charging.gasRange == nil)
        #expect(charging.evStatus != nil)

        let unplugged = try parse(KiaUSAStatusSampleJSON.ev9Unplugged)
        #expect(unplugged.gasRange == nil)
    }

    @Test("Car with a battery and a positive fuel level keeps its gas range")
    @MainActor func testPHEVKeepsGasRange() throws {
        let status = try parse(KiaUSAStatusSampleJSON.phevWithFuel)
        let gas = try #require(status.gasRange)
        #expect(gas.percentage == 40)
        #expect(gas.range.length == 60) // gasModeRange, not distanceToEmpty
        #expect(status.evStatus != nil)
    }

    @Test("PHEV that sends no fuel level reports no gas range")
    @MainActor func testPHEVWithoutFuelLevel() throws {
        // `FuelRange` needs a percentage, so a range alone isn't enough.
        let status = try parse(KiaUSAStatusSampleJSON.niroPHEV)
        #expect(status.gasRange == nil)
        #expect(status.evStatus?.evRange.percentage == 16)
    }

    @Test("Vehicle-list fuelType codes map to powertrains")
    @MainActor func testKiaUSAFuelTypeCodes() {
        #expect(KiaUSAAPIClient.kiaUSAFuelType(from: 4) == .electric) // Niro EV, EV6, EV9
        #expect(KiaUSAAPIClient.kiaUSAFuelType(from: 7) == .phev)     // 2018 Niro PHEV
        #expect(KiaUSAAPIClient.kiaUSAFuelType(from: 1) == .gas)      // Sportage
        #expect(KiaUSAAPIClient.kiaUSAFuelType(from: 3) == .gas)      // Niro / Sorento hybrid
    }

    @Test("Unplugged EV9 reports no rate or ETA from the what-if estimates")
    @MainActor func testEV9UnpluggedHasNoChargeTime() throws {
        let ev = try #require(try parse(KiaUSAStatusSampleJSON.ev9Unplugged).evStatus)
        #expect(!ev.charging)
        #expect(!ev.pluggedIn)
        #expect(ev.chargeSpeed == 0)
        #expect(ev.chargeTime == .zero)
    }

    @Test("realTimePower only counts as a charge rate while charging, and never below 0")
    @MainActor func testChargeRateGatedOnCharging() throws {
        // Synthetic tweaks of real payloads.
        let idle = KiaUSAStatusSampleJSON.ev9Unplugged
            .replacingOccurrences(of: #""realTimePower": 0,"#, with: #""realTimePower": 3.2,"#)
        #expect(idle.contains("3.2"))
        #expect(try parse(idle).evStatus?.chargeSpeed == 0)

        let negative = KiaUSAStatusSampleJSON.ev9Charging
            .replacingOccurrences(of: #""realTimePower": 11.3,"#, with: #""realTimePower": -2.0,"#)
        #expect(negative.contains("-2.0"))
        #expect(try parse(negative).evStatus?.chargeSpeed == 0)
    }

    @Test("Plugged-in EV6 that isn't charging reports no ETA")
    @MainActor func testEV6PluggedNotCharging() throws {
        let status = try parse(KiaUSAStatusSampleJSON.ev6PluggedNotCharging)
        let ev = try #require(status.evStatus)
        #expect(!ev.charging)
        #expect(ev.pluggedIn)
        #expect(ev.plugType == .acCharger)
        #expect(ev.chargeTime == .zero)
        #expect(status.gasRange == nil)
    }

    @Test("Niro EV without realTimePower still reports time remaining")
    @MainActor func testNiroEVChargingWithoutRealTimePower() throws {
        let ev = try #require(try parse(KiaUSAStatusSampleJSON.niroEVCharging).evStatus)
        #expect(ev.charging)
        #expect(ev.chargeSpeed == 0)
        #expect(ev.chargeTime == .seconds(95 * 60))
    }

    @Test("Gas car keeps its gas range")
    @MainActor func testGasCarKeepsGasRange() throws {
        let status = try parse(KiaUSAStatusSampleJSON.gasCar)
        let gas = try #require(status.gasRange)
        #expect(gas.percentage == 61)
        #expect(gas.range.length == 342)
        #expect(status.evStatus == nil)
    }

    // MARK: remainingChargeMinutes entry selection

    private func entries(_ pairs: [(type: Int, minutes: Int)]) throws -> Any {
        let json = "[" + pairs.map {
            #"{"remainChargeType":\#($0.type),"timeInterval":{"value":\#($0.minutes),"unit":4}}"#
        }.joined(separator: ",") + "]"
        return try JSONSerialization.jsonObject(with: Data(json.utf8))
    }

    @Test("A single entry is the active session, whatever its type")
    @MainActor func testSingleEntryIsUsed() throws {
        #expect(remainingChargeMinutes(in: try entries([(4, 225)])) == 225)
        #expect(remainingChargeMinutes(in: try entries([(3, 95)])) == 95)
    }

    @Test("Several entries: take the type-4 session entry, never guess by array order")
    @MainActor func testMultipleEntries() throws {
        // Synthetic — no captured charging payload lists several entries.
        let withSession = try entries([(1, 20), (4, 75), (3, 120)])
        #expect(remainingChargeMinutes(in: withSession) == 75)

        // Only what-if estimates: which one applies is unknowable, so no ETA.
        let estimates = try entries([(1, 20), (2, 900), (3, 120)])
        #expect(remainingChargeMinutes(in: estimates) == 0)
    }

    @Test("Missing or malformed remainChargeTime yields no ETA")
    @MainActor func testMissingRemainChargeTime() throws {
        #expect(remainingChargeMinutes(in: nil) == 0)
        #expect(remainingChargeMinutes(in: try entries([])) == 0)
        // The pre-fix parser read a flat `value`; every captured Kia USA
        // entry nests it under `timeInterval`.
        let flat = try JSONSerialization.jsonObject(with: Data(#"[{"value":90}]"#.utf8))
        #expect(remainingChargeMinutes(in: flat) == 0)
    }
}
