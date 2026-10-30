//
//  UpstreamParityFixesTests.swift
//  BetterBlueKit
//
//  Tests for the hyundai_kia_connect_api parity fixes: the Canada
//  model-year temperature scale, the EU CCS2 flag parse, and the
//  Canada errorCode classification.
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Canada model-year temperature scale")
struct CanadaTemperatureScaleTests {

    @Test("MY2020+ uses the 14.0°C base up to 31.5°C")
    func testNewScale() {
        #expect(Temperature.encodeCanadaAirTempToHEX(celsiusValue: 14.0, modelYear: 2022) == "00H")
        #expect(Temperature.encodeCanadaAirTempToHEX(celsiusValue: 22.0, modelYear: 2022) == "10H")
        // The old shared encoder clamped everything above 29.5°C; the
        // new-scale table runs to index 35 (0x23) = 31.5°C.
        #expect(Temperature.encodeCanadaAirTempToHEX(celsiusValue: 31.5, modelYear: 2022) == "23H")
        #expect(Temperature.encodeCanadaAirTempToHEX(celsiusValue: 40.0, modelYear: 2022) == "23H")
    }

    @Test("Pre-2020 uses the 16.0°C base")
    func testOldScale() {
        #expect(Temperature.encodeCanadaAirTempToHEX(celsiusValue: 16.0, modelYear: 2019) == "00H")
        // 20°C on the old scale is index 8, not 12 — the off-by-2°C the
        // single-table encoder produced on pre-2020 cars.
        #expect(Temperature.encodeCanadaAirTempToHEX(celsiusValue: 20.0, modelYear: 2019) == "08H")
        #expect(Temperature.encodeCanadaAirTempToHEX(celsiusValue: 31.5, modelYear: 2019) == "1FH")
    }

    @Test("Unknown model year matches upstream's default (old scale)")
    func testUnknownYear() {
        #expect(Temperature.encodeCanadaAirTempToHEX(celsiusValue: 20.0, modelYear: nil) == "08H")
    }

    @Test("Decode is the inverse of encode on both scales")
    func testDecodeRoundTrip() {
        for year in [2019, 2024] {
            for celsius in stride(from: 17.0, through: 29.5, by: 0.5) {
                let hex = Temperature.encodeCanadaAirTempToHEX(celsiusValue: celsius, modelYear: year)
                let index = Int(hex.dropLast(), radix: 16)!
                #expect(Temperature.decodeCanadaAirTempHEX(index: index, modelYear: year) == celsius)
            }
        }
    }
}

@Suite("EU CCS2 flag parse")
struct EuCCS2FlagTests {

    @Test("Any non-zero value means CCS2, matching upstream's != 0")
    func testFlagShapes() {
        #expect(APIClientBase.parseCCS2Flag(1) == true)
        #expect(APIClientBase.parseCCS2Flag(2) == true)
        #expect(APIClientBase.parseCCS2Flag(0) == false)
        #expect(APIClientBase.parseCCS2Flag(true) == true)
        #expect(APIClientBase.parseCCS2Flag(false) == false)
        #expect(APIClientBase.parseCCS2Flag("2") == true)
        #expect(APIClientBase.parseCCS2Flag("0") == false)
        #expect(APIClientBase.parseCCS2Flag(nil) == false)
    }
}

@MainActor
@Suite("Canada errorCode classification")
struct CanadaErrorCodeTests {
    private func makeClient() -> HyundaiCanadaAPIClient {
        HyundaiCanadaAPIClient(
            configuration: APIClientConfiguration(
                region: .canada,
                brand: .hyundai,
                username: "test@example.com",
                password: "password123",
                pin: "0000",
                accountId: UUID()
            )
        )
    }

    private func response(code: String, desc: String) -> Data {
        Data("""
        {"responseHeader":{"responseCode":1,"responseDesc":"Failure"},
        "error":{"errorCode":"\(code)","errorDesc":"\(desc)"}}
        """.utf8)
    }

    @Test("Credential-class codes map to invalidCredentials regardless of wording")
    func testCredentialCodes() {
        // A French errorDesc defeats the old substring matching; the
        // code must carry the classification.
        for code in ["7402", "7403", "7404", "7549", "7602", "7606"] {
            let data = response(code: code, desc: "Les informations de connexion sont incorrectes.")
            do {
                _ = try makeClient().parseCanadaResponse(data, context: "test")
                Issue.record("expected throw for code \(code)")
            } catch let error as APIError {
                #expect(error.errorType == .invalidCredentials, "code \(code)")
            } catch {
                Issue.record("unexpected error type for code \(code)")
            }
        }
    }

    @Test("Unmapped codes stay generic errors")
    func testGenericCode() {
        let data = response(code: "7999", desc: "We apologize, but your request could not be processed.")
        do {
            _ = try makeClient().parseCanadaResponse(data, context: "test")
            Issue.record("expected throw")
        } catch let error as APIError {
            #expect(error.errorType == .general)
        } catch {
            Issue.record("unexpected error type")
        }
    }
}
