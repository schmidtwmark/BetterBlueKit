//
//  HyundaiUSASurroundViewTests.swift
//  BetterBlueKit
//
//  Parsing coverage for Hyundai USA "Find My Car SVM". The payload shape
//  is taken from the MyHyundai app's own bundled sample response
//  (assets/hma/SVMDetails.json) and hyundai_kia_connect_api#1203:
//  `svmDetails[].svmDetail` with a base64 `svmImage`, an `imageSize`
//  array, nested `gpsDetail.coord`, and 0/1 door flags.
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Hyundai USA Surround View")
struct HyundaiUSASurroundViewTests {

    /// Bytes that merely look like a JPEG — the decoder splits on markers
    /// and never parses the image itself.
    private func fakeJPEG(marker: UInt8, padding: Int = 8) -> Data {
        var data = Data([0xFF, 0xD8, 0xFF, 0xE0])
        data.append(contentsOf: Array(repeating: marker, count: padding))
        data.append(contentsOf: [0xFF, 0xD9])
        return data
    }

    @MainActor
    private func makeClient() -> HyundaiUSAAPIClient {
        HyundaiUSAAPIClient(configuration: APIClientConfiguration(
            region: .usa,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "1234",
            accountId: UUID()
        ))
    }

    private func makeVehicle() -> Vehicle {
        Vehicle(
            vin: "TESTVIN0000000000",
            regId: "reg",
            model: "PALISADE",
            accountId: UUID(),
            fuelType: .gas,
            generation: 3,
            odometer: Distance(length: 0, units: .kilometers)
        )
    }

    /// One `svmDetail` shaped like the app's real sample: nested
    /// coordinates, 0/1 doors, the timestamp under `gpsDetail.time` (the
    /// real payload has no top-level `time`), and the real 4472×720
    /// imageSize.
    private func makePayload(entries: [(time: String, marker: UInt8)]) -> Data {
        let details = entries.map { entry in
            """
            {"svmDetail": {
              "sidemirrorOpen": false,
              "trunkOpen": false,
              "doorOpen": {"frontLeft": 0, "frontRight": 1, "backLeft": 0, "backRight": 0},
              "imageSize": [4472, 720, 960, 720, 632, 720],
              "gpsDetail": {
                "coord": {"lat": 42.271284, "alt": 254, "lon": -83.625744, "type": 0},
                "speed": {"value": 0, "unit": 1}, "time": "\(entry.time)", "head": 93
              },
              "svmImage": "\(fakeJPEG(marker: entry.marker).base64EncodedString())"
            }}
            """
        }.joined(separator: ",")

        return Data("""
        {"svmDetails": [\(details)]}
        """.utf8)
    }

    @Test("A capture's imagery and metadata parse")
    @MainActor func testParsesCapture() throws {
        let captures = try makeClient().parseUSASurroundViewResponse(
            makePayload(entries: [(time: "20260826003935", marker: 0x11)]),
            for: makeVehicle()
        )

        let capture = try #require(captures.first)
        #expect(capture.vin == "TESTVIN0000000000")
        #expect(capture.frames.count == 1)
        #expect(capture.tiles.count == 5) // four fisheye + bird's-eye
        #expect(capture.heading == 93)
        #expect(capture.sideMirrorOpen == false)
        #expect(capture.trunkOpen == false)
        #expect(capture.doorOpen?.frontRight == true)
        #expect(capture.doorOpen?.frontLeft == false)
        #expect(capture.location?.latitude == 42.271284)
        #expect(capture.location?.longitude == -83.625744)
    }

    /// The `time` has no timezone in it — reading it as local time would
    /// shift every capture by the user's offset.
    @Test("gpsDetail.time is read as UTC")
    @MainActor func testTimestampIsUTC() throws {
        let capture = try #require(try makeClient().parseUSASurroundViewResponse(
            makePayload(entries: [(time: "20260826003935", marker: 0x11)]),
            for: makeVehicle()
        ).first)

        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 26
        components.hour = 0; components.minute = 39; components.second = 35
        components.timeZone = TimeZone(identifier: "UTC")

        let expected = try #require(Calendar(identifier: .gregorian).date(from: components))
        #expect(capture.capturedAt == expected)
    }

    /// A capture taken without a GPS fix may drop `gpsDetail` entirely; the
    /// timestamp then has to come from a top-level `time`, or every such
    /// capture collapses onto the same "unknown" id and loses its order.
    @Test("Timestamp falls back to a top-level time when gpsDetail is absent")
    @MainActor func testTimestampFallsBackToTopLevel() throws {
        let payload = Data("""
        {"svmDetails": [{"svmDetail": {
          "time": "20260826003935",
          "svmImage": "\(fakeJPEG(marker: 0x11).base64EncodedString())"
        }}]}
        """.utf8)

        let capture = try #require(
            try makeClient().parseUSASurroundViewResponse(payload, for: makeVehicle()).first
        )
        #expect(capture.capturedAt != nil)
        #expect(capture.location == nil)
    }

    @Test("Captures are returned newest first")
    @MainActor func testSortedNewestFirst() throws {
        let captures = try makeClient().parseUSASurroundViewResponse(
            makePayload(entries: [
                (time: "20260713192923", marker: 0x11),
                (time: "20260826003935", marker: 0x22),
                (time: "20260806221826", marker: 0x33)
            ]),
            for: makeVehicle()
        )

        #expect(captures.count == 3)
        let timestamps = captures.compactMap(\.capturedAt)
        #expect(timestamps == timestamps.sorted(by: >))
    }

    /// Doors and flags may arrive as 0/1 or as booleans; both must read.
    @Test("Door and trunk flags tolerate numbers and booleans")
    @MainActor func testFlagsTolerant() throws {
        let payload = Data("""
        {"svmDetails": [{"svmDetail": {
          "time": "20260826003935",
          "trunkOpen": 1,
          "sidemirrorOpen": true,
          "doorOpen": {"frontLeft": true, "frontRight": 0, "backLeft": 1, "backRight": false},
          "svmImage": "\(fakeJPEG(marker: 0x11).base64EncodedString())"
        }}]}
        """.utf8)

        let capture = try #require(
            try makeClient().parseUSASurroundViewResponse(payload, for: makeVehicle()).first
        )
        #expect(capture.trunkOpen == true)
        #expect(capture.sideMirrorOpen == true)
        #expect(capture.doorOpen?.frontLeft == true)
        #expect(capture.doorOpen?.frontRight == false)
        #expect(capture.doorOpen?.backLeft == true)
        #expect(capture.doorOpen?.backRight == false)
    }

    @Test("An entry with unusable imagery is skipped, not fatal")
    @MainActor func testSkipsUndecodableEntry() throws {
        let payload = Data("""
        {"svmDetails": [{"svmDetail": {"time": "20260826003935", "svmImage": "bm90LWEtanBlZw=="}}]}
        """.utf8)
        #expect(try makeClient().parseUSASurroundViewResponse(payload, for: makeVehicle()).isEmpty)
    }

    @Test("A response without svmDetails throws")
    @MainActor func testMissingDetailsThrows() {
        let payload = Data(#"{"status": "ok"}"#.utf8)
        #expect(throws: APIError.self) {
            try makeClient().parseUSASurroundViewResponse(payload, for: makeVehicle())
        }
    }

    @Test("Hyundai USA advertises surround view")
    @MainActor func testCapabilityDeclared() {
        #expect(makeClient().supportsSurroundView())
    }

    /// The BLODS refusal for camera-less vehicles (BetterBlue#105):
    /// `validateHTTPResponse` folds the 502 body into a `.serverError`,
    /// and the client remaps that to `.featureNotSupported` so the UI can
    /// explain the missing hardware instead of showing a generic error.
    @Test("The 'does not support' 502 remaps to featureNotSupported")
    @MainActor func testUnsupportedRemap() {
        let refusal = APIError.serverError(
            #"Server error (502): {"errorCode":502,"errorMessage":"Your vehicle does not support this feature.","errorSubCode":"GEN","errorSubMessage":"Feature Status is OFF"}"#,
            apiName: "HyundaiUSA"
        )
        #expect(makeClient().mapUnsupportedSurroundViewError(refusal).errorType == .featureNotSupported)

        // Any other 502 passes through untouched.
        let other = APIError.serverError("Server error (502): upstream broke", apiName: "HyundaiUSA")
        #expect(makeClient().mapUnsupportedSurroundViewError(other).errorType == .serverError)
    }
}
