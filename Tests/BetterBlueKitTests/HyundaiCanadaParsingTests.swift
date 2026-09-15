//
//  HyundaiCanadaParsingTests.swift
//  BetterBlueKit
//
//  Regression coverage for Hyundai Canada status parsing. Payload shapes are
//  taken from a real Palisade debug export (BetterBlue#98).
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Hyundai Canada Parsing")
struct HyundaiCanadaParsingTests {

    @MainActor
    private func makeClient() -> HyundaiCanadaAPIClient {
        let config = APIClientConfiguration(
            region: .canada,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "1234",
            accountId: UUID()
        )
        return HyundaiCanadaAPIClient(configuration: config)
    }

    /// Build the dictionary the way production does — through
    /// `JSONSerialization`, so numbers arrive as `NSNumber` and booleans as
    /// `__NSCFBoolean`. Swift literal dictionaries don't bridge the same way
    /// and would exercise a code path the app never takes.
    private func json(_ raw: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    }

    private func makeVehicle(fuelType: FuelType, odometer: Double? = nil) -> Vehicle {
        Vehicle(
            vin: "TESTVIN0000000000",
            regId: "reg",
            model: "PALISADE",
            accountId: UUID(),
            fuelType: fuelType,
            generation: 2,
            odometer: odometer.map { Distance(length: $0, units: .kilometers) }
                ?? Distance(length: 42000, units: .kilometers)
        )
    }

    // MARK: - Fuel type detection

    /// A Canadian gas vehicle exposes its powertrain only as `fuelKindCode`.
    /// Before #98 this fell through to the `.electric` default, which hid the
    /// fuel range and gave a Palisade a phantom CCS1 charge port.
    @Test("fuelKindCode G is detected as gas, not electric")
    @MainActor func testGasVehicleDetectedFromFuelKindCode() throws {
        let vehicleData = try json(
            #"{"fuelKindCode": "G", "genType": "G1", "mainBatteryType": false, "modelName": "PALISADE"}"#
        )
        #expect(makeClient().detectFuelType(from: vehicleData) == .gas)
    }

    @Test("fuelKindCode E and P map to electric and phev")
    @MainActor func testElectricAndPhevFromFuelKindCode() throws {
        let client = makeClient()
        #expect(client.detectFuelType(from: try json(#"{"fuelKindCode": "E"}"#)) == .electric)
        #expect(client.detectFuelType(from: try json(#"{"fuelKindCode": "P"}"#)) == .phev)
    }

    /// `evStatus` is the older, more specific signal and must keep winning.
    @Test("evStatus still takes precedence over fuelKindCode")
    @MainActor func testEvStatusWinsOverFuelKindCode() throws {
        let vehicleData = try json(#"{"evStatus": "E", "fuelKindCode": "G"}"#)
        #expect(makeClient().detectFuelType(from: vehicleData) == .electric)
    }

    // MARK: - Gas range (DTE)

    /// Canada sends `dte`, not `distanceToEmpty`, and reports the unit as a
    /// JSON boolean. Reading the wrong key meant gas vehicles showed no range
    /// at all even though the value was present (#98).
    @Test("Gas range parses Canada's dte block with a boolean unit")
    @MainActor func testGasRangeFromDte() throws {
        let statusData = try json(#"{"fuelLevel": 59, "dte": {"unit": true, "value": 314}}"#)

        let range = try #require(
            makeClient().parseCanadaGasRange(from: statusData, vehicle: makeVehicle(fuelType: .gas))
        )
        #expect(range.range.length == 314)
        #expect(range.range.units == .kilometers) // unit: true == km in this region
        #expect(range.percentage == 59)
    }

    @Test("Gas range still accepts the distanceToEmpty spelling")
    @MainActor func testGasRangeFallbackKey() throws {
        let statusData = try json(#"{"fuelLevel": 40, "distanceToEmpty": {"unit": 1, "value": 210}}"#)

        let range = try #require(
            makeClient().parseCanadaGasRange(from: statusData, vehicle: makeVehicle(fuelType: .gas))
        )
        #expect(range.range.length == 210)
        #expect(range.range.units == .kilometers)
    }

    @Test("Gas range is nil for an electric vehicle")
    @MainActor func testGasRangeSkippedForEV() throws {
        let statusData = try json(#"{"fuelLevel": 59, "dte": {"unit": true, "value": 314}}"#)
        #expect(makeClient().parseCanadaGasRange(from: statusData, vehicle: makeVehicle(fuelType: .electric)) == nil)
    }

    // MARK: - Odometer parsing

    /// Odometer readings arrive in the status payload only because the
    /// client injects them from `nxtsvc`; the shape is `{value, unit}`.
    @Test("Status odometer is parsed when present")
    @MainActor func testStatusOdometerParsed() throws {
        let vehicle = makeVehicle(fuelType: .gas, odometer: 0)
        let data = Data(#"{"responseHeader": {"responseCode": 0}, "result": {"status": {"odometer": {"value": 45000, "unit": 1}}}}"#.utf8)
        let status = try makeClient().parseCanadaVehicleStatusResponse(data, for: vehicle)
        #expect(status.odometer?.length == 45000)
        #expect(status.odometer?.units == .kilometers)
    }

    @Test("Status odometer honours a miles unit code")
    @MainActor func testStatusOdometerMilesUnit() throws {
        let vehicle = makeVehicle(fuelType: .gas, odometer: 0)
        let data = Data(#"{"responseHeader": {"responseCode": 0}, "result": {"status": {"odometer": {"value": 12000, "unit": 3}}}}"#.utf8)
        let status = try makeClient().parseCanadaVehicleStatusResponse(data, for: vehicle)
        #expect(status.odometer?.length == 12000)
        #expect(status.odometer?.units == .miles)
    }

    /// A zero, null, or missing odometer means the server didn't report
    /// one. The parser must return nil — not 0 km, and not a guess — so the
    /// host keeps the last reading it stored (BetterBlue#107).
    @Test("Zero status odometer parses as nil", arguments: [
        #"{"responseHeader": {"responseCode": 0}, "result": {"status": {"odometer": 0}}}"#,
        #"{"responseHeader": {"responseCode": 0}, "result": {"status": {"odometer": {"value": 0, "unit": 1}}}}"#,
        #"{"responseHeader": {"responseCode": 0}, "result": {"status": {"odometer": null}}}"#,
        #"{"responseHeader": {"responseCode": 0}, "result": {"status": {"fuelLevel": 60}}}"#
    ])
    @MainActor func testUnreportedStatusOdometerIsNil(raw: String) throws {
        let vehicle = makeVehicle(fuelType: .gas, odometer: 42000)
        let status = try makeClient().parseCanadaVehicleStatusResponse(Data(raw.utf8), for: vehicle)
        #expect(status.odometer == nil)
    }

    // MARK: - Next service (nxtsvc)

    /// Shape from hyundai_kia_connect_api's `_get_next_service`: the
    /// odometer sits in `result.maintenanceInfo.currentOdometer` with its
    /// unit code alongside. None of the Canada status endpoints carry it.
    @Test("Next-service odometer parses from maintenanceInfo")
    @MainActor func testNextServiceOdometerParsed() throws {
        let data = Data(#"""
        {"responseHeader": {"responseCode": 0, "responseDesc": "Success"},
         "result": {"maintenanceInfo": {
            "currentOdometer": 45123, "currentOdometerUnit": 1,
            "imatServiceOdometer": 48000, "imatServiceOdometerUnit": 1,
            "msopServiceOdometer": 40000, "msopServiceOdometerUnit": 1}}}
        """#.utf8)
        let odometer = try makeClient().parseCanadaNextServiceOdometer(data)
        #expect(odometer?.length == 45123)
        #expect(odometer?.units == .kilometers)
    }

    @Test("Next-service odometer is nil when maintenanceInfo is absent or zero", arguments: [
        #"{"responseHeader": {"responseCode": 0}, "result": {}}"#,
        #"{"responseHeader": {"responseCode": 0}, "result": {"maintenanceInfo": {"currentOdometer": 0}}}"#
    ])
    @MainActor func testNextServiceOdometerMissing(raw: String) throws {
        #expect(try makeClient().parseCanadaNextServiceOdometer(Data(raw.utf8)) == nil)
    }

    /// The injected reading must land where both the status parser and the
    /// location gate look: `result.status.odometer` as `{value, unit}`.
    @Test("Injected next-service odometer round-trips through the status parser")
    @MainActor func testInjectedOdometerRoundTrips() throws {
        let client = makeClient()
        let statusData = Data(#"{"responseHeader": {"responseCode": 0}, "result": {"status": {"fuelLevel": 60, "doorLock": true}}}"#.utf8)
        let injected = client.injectOdometer(Distance(length: 45123, units: .kilometers), into: statusData)
        let status = try client.parseCanadaVehicleStatusResponse(injected, for: makeVehicle(fuelType: .gas))
        #expect(status.odometer?.length == 45123)
        #expect(status.odometer?.units == .kilometers)
        #expect(status.lockStatus == .locked)
    }

    @Test("Injecting a nil odometer leaves the payload untouched")
    @MainActor func testInjectNilOdometerIsNoop() throws {
        let statusData = Data(#"{"responseHeader": {"responseCode": 0}, "result": {"status": {"fuelLevel": 60}}}"#.utf8)
        #expect(makeClient().injectOdometer(nil, into: statusData) == statusData)
    }
}
