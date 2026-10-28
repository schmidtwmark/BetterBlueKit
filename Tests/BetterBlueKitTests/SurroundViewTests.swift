//
//  SurroundViewTests.swift
//  BetterBlueKit
//
//  Surround View Monitor decoding and Hyundai Canada payload parsing.
//  Geometry values come from a real Canadian capture: a 4472x720 strip
//  holding four 960-wide fisheye views plus a 632-wide bird's-eye view.
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Surround View")
struct SurroundViewTests {

    /// Bytes that merely *look* like a JPEG — the decoder splits on
    /// markers and never parses the image itself.
    private func fakeJPEG(marker: UInt8, padding: Int = 8) -> Data {
        var data = Data([0xFF, 0xD8, 0xFF, 0xE0])
        data.append(contentsOf: Array(repeating: marker, count: padding))
        data.append(contentsOf: [0xFF, 0xD9])
        return data
    }

    // MARK: - Frame extraction

    @Test("A single composite frame comes back whole")
    func testSingleFrame() {
        let frame = fakeJPEG(marker: 0x11)
        let frames = SurroundViewDecoder.extractJPEGFrames(from: frame)

        #expect(frames.count == 1)
        #expect(frames[0] == frame)
    }

    @Test("Concatenated frames are split apart")
    func testConcatenatedFrames() {
        let first = fakeJPEG(marker: 0x11)
        let second = fakeJPEG(marker: 0x22, padding: 12)
        let frames = SurroundViewDecoder.extractJPEGFrames(from: first + second)

        #expect(frames.count == 2)
        #expect(frames[0] == first)
        #expect(frames[1] == second)
    }

    @Test("Trailing padding after the end marker is dropped")
    func testTrailingPaddingTrimmed() {
        let frame = fakeJPEG(marker: 0x11)
        let frames = SurroundViewDecoder.extractJPEGFrames(from: frame + Data([0x00, 0x00, 0x00]))

        #expect(frames == [frame])
    }

    /// An embedded thumbnail carries its own 0xFFD9. Cutting at the first
    /// one would truncate the real image, so frames are split on start
    /// markers instead.
    @Test("An embedded end marker does not truncate the frame")
    func testEmbeddedEndMarkerKeepsFrameIntact() {
        var frame = Data([0xFF, 0xD8, 0xFF, 0xE1])
        frame.append(contentsOf: [0xFF, 0xD9])
        frame.append(contentsOf: Array(repeating: 0x33, count: 32))
        frame.append(contentsOf: [0xFF, 0xD9])

        let frames = SurroundViewDecoder.extractJPEGFrames(from: frame)

        #expect(frames.count == 1)
        #expect(frames[0].count == frame.count)
    }

    @Test("Data without a start marker yields no frames")
    func testNoFrames() {
        #expect(SurroundViewDecoder.extractJPEGFrames(from: Data([0x01, 0x02, 0x03])).isEmpty)
    }

    // MARK: - Tile geometry

    @Test("A 4472x720 strip slices into four cameras plus the top-down view")
    func testCompositeStripTiles() {
        let tiles = SurroundViewDecoder.tiles(
            imageSize: [4472, 720, 960, 720, 632, 720],
            frameCount: 1
        )

        #expect(tiles.map(\.position) == [.front, .rear, .left, .right, .topDown])
        #expect(tiles.allSatisfy { $0.frameIndex == 0 })
        #expect(tiles[0].crop == SurroundViewCrop(originX: 0, originY: 0, width: 960, height: 720))
        #expect(tiles[3].crop == SurroundViewCrop(originX: 2880, originY: 0, width: 960, height: 720))
        #expect(tiles[4].crop == SurroundViewCrop(originX: 3840, originY: 0, width: 632, height: 720))

        // The tiles must exactly cover the strip.
        let covered = tiles.compactMap(\.crop).reduce(0) { $0 + $1.width }
        #expect(covered == 4472)
    }

    @Test("An unrecognized layout falls back to the whole frame")
    func testUnknownLayoutFallsBackToWholeFrame() {
        // Widths that don't divide evenly, and a truncated array: both
        // should still produce something displayable.
        for imageSize in [[4472, 720, 700, 720, 632, 720], [4472, 720]] {
            let tiles = SurroundViewDecoder.tiles(imageSize: imageSize, frameCount: 1)
            #expect(tiles.count == 1)
            #expect(tiles[0].position == .composite)
            #expect(tiles[0].crop == nil)
        }
    }

    @Test("One JPEG per camera needs no slicing")
    func testMultiFrameTiles() {
        let tiles = SurroundViewDecoder.tiles(imageSize: [], frameCount: 4)

        #expect(tiles.map(\.position) == [.front, .rear, .left, .right])
        #expect(tiles.map(\.frameIndex) == [0, 1, 2, 3])
        #expect(tiles.allSatisfy { $0.crop == nil })
    }

    @Test("No frames means no tiles")
    func testNoTilesWithoutFrames() {
        #expect(SurroundViewDecoder.tiles(imageSize: [4472, 720, 960, 720, 632, 720], frameCount: 0).isEmpty)
    }

    // MARK: - Hyundai Canada payload

    @MainActor
    private func makeClient(brand: Brand = .hyundai, urlSession: URLSession = .shared) -> HyundaiCanadaAPIClient {
        HyundaiCanadaAPIClient(configuration: APIClientConfiguration(
            region: .canada,
            brand: brand,
            username: "test@example.com",
            password: "password123",
            pin: "1234",
            accountId: UUID()
        ), urlSession: urlSession)
    }

    @MainActor
    @Test(arguments: [false, true]) func `Genesis surround view rejects unsupported calls`(capture: Bool) async {
        let session = URLSession(configuration: .ephemeral)

        // An invalidated session prevents requests to the live service if this guard regresses.
        session.invalidateAndCancel()
        let client = makeClient(brand: .genesis, urlSession: session)
        let token = AuthToken(accessToken: "test", refreshToken: "", expiresAt: .distantFuture)
        do {
            if capture {
                try await client.requestSurroundViewCapture(for: makeVehicle(), authToken: token)
            } else {
                _ = try await client.fetchSurroundViewCaptures(for: makeVehicle(), authToken: token)
            }
            Issue.record("Expected an unsupported-feature error")
        } catch let error as APIError {
            #expect(error.errorType == .featureNotSupported)
            #expect(error.apiName == "GenesisCanada")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeVehicle() -> Vehicle {
        Vehicle(
            vin: "TESTVIN0000000000",
            regId: "reg",
            model: "TUCSON",
            accountId: UUID(),
            fuelType: .gas,
            generation: 2,
            odometer: Distance(length: 0, units: .kilometers)
        )
    }

    private func makePayload(entries: [(utcTime: String, marker: UInt8)]) -> Data {
        let locations = entries.map { entry in
            """
            {
              "sidemirrorOpen": true,
              "offset": -5,
              "utcTime": "\(entry.utcTime)",
              "trunkOpen": false,
              "doorOpen": {"frontLeft": 0, "frontRight": 1, "backLeft": 0, "backRight": 0},
              "imageSize": [4472, 720, 960, 720, 632, 720],
              "gpsDetail": {
                "speed": 0, "time": "\(entry.utcTime)", "coordType": 0, "head": 93,
                "coordLat": 43.653226, "coordLon": -79.383184, "speedUnit": 0
              },
              "svmImage": "\(fakeJPEG(marker: entry.marker).base64EncodedString())"
            }
            """
        }.joined(separator: ",")

        return Data("""
        {
          "responseHeader": {"responseDesc": "Success", "responseCode": 0},
          "result": {"svmLocations": [\(locations)]}
        }
        """.utf8)
    }

    @Test("A capture's imagery and metadata are parsed")
    @MainActor func testParsesCapture() throws {
        let captures = try makeClient().parseCanadaSurroundViewResponse(
            makePayload(entries: [(utcTime: "20260826003935", marker: 0x11)]),
            for: makeVehicle()
        )

        let capture = try #require(captures.first)
        #expect(capture.vin == "TESTVIN0000000000")
        #expect(capture.frames.count == 1)
        #expect(capture.tiles.count == 5)
        #expect(capture.heading == 93)
        #expect(capture.sideMirrorOpen == true)
        #expect(capture.trunkOpen == false)
        #expect(capture.doorOpen?.frontRight == true)
        #expect(capture.doorOpen?.frontLeft == false)
        #expect(capture.location?.latitude == 43.653226)
        #expect(capture.location?.longitude == -79.383184)
    }

    /// `utcTime` has no timezone in it — reading it as local time would
    /// shift every capture by the user's offset.
    @Test("utcTime is read as UTC")
    @MainActor func testTimestampIsUTC() throws {
        let captures = try makeClient().parseCanadaSurroundViewResponse(
            makePayload(entries: [(utcTime: "20260826003935", marker: 0x11)]),
            for: makeVehicle()
        )

        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 26
        components.hour = 0
        components.minute = 39
        components.second = 35
        components.timeZone = TimeZone(identifier: "UTC")

        let expected = try #require(Calendar(identifier: .gregorian).date(from: components))
        #expect(captures.first?.capturedAt == expected)
    }

    @Test("Captures are returned newest first")
    @MainActor func testCapturesSortedNewestFirst() throws {
        let captures = try makeClient().parseCanadaSurroundViewResponse(
            makePayload(entries: [
                (utcTime: "20260713192923", marker: 0x11),
                (utcTime: "20260826003935", marker: 0x22),
                (utcTime: "20260806221826", marker: 0x33)
            ]),
            for: makeVehicle()
        )

        #expect(captures.count == 3)
        let timestamps = captures.compactMap(\.capturedAt)
        #expect(timestamps == timestamps.sorted(by: >))
    }

    @Test("An entry with unusable imagery is skipped, not fatal")
    @MainActor func testSkipsUndecodableEntry() throws {
        let payload = Data("""
        {
          "responseHeader": {"responseDesc": "Success", "responseCode": 0},
          "result": {"svmLocations": [{"utcTime": "20260826003935", "svmImage": "bm90LWEtanBlZw=="}]}
        }
        """.utf8)

        #expect(try makeClient().parseCanadaSurroundViewResponse(payload, for: makeVehicle()).isEmpty)
    }

    @Test("A response without svmLocations throws")
    @MainActor func testMissingLocationsThrows() {
        let payload = Data("""
        {"responseHeader": {"responseDesc": "Success", "responseCode": 0}, "result": {}}
        """.utf8)

        #expect(throws: APIError.self) {
            try makeClient().parseCanadaSurroundViewResponse(payload, for: makeVehicle())
        }
    }

    // MARK: - Logging

    /// HTTP logs are persisted, synced, and bundled into debug exports,
    /// so a megabyte of base64 must never reach them.
    @Test("Oversized values are elided from logged bodies")
    func testOversizedValuesElided() throws {
        let image = String(repeating: "A", count: 20_000)
        let body = #"{"utcTime":"20260826003935","svmImage":"\#(image)","head":93}"#

        let elided = try #require(SensitiveDataRedactor.elideOversizedValues(body))

        #expect(!elided.contains(image))
        #expect(elided.contains("20260826003935"))
        #expect(elided.contains("\"head\":93"))
        #expect(elided.contains("20000 characters elided"))
        #expect(try JSONSerialization.jsonObject(with: Data(elided.utf8)) is [String: Any])
    }

    @Test("Ordinary bodies pass through untouched")
    func testSmallBodiesUnchanged() {
        let body = #"{"pin":"1234","escaped":"a \" quote"}"#
        #expect(SensitiveDataRedactor.elideOversizedValues(body) == body)
    }

    // MARK: - Geometry inference

    /// A JPEG carrying a real SOF0 header, so the decoder can read its
    /// dimensions. Not a decodable image — only the header is ever parsed.
    private func sizedJPEG(width: Int, height: Int, marker: UInt8 = 0x11) -> Data {
        var data = Data([0xFF, 0xD8])
        // An APP0 segment first, so the walk has to skip a length-carrying
        // segment before it reaches the SOF.
        data.append(contentsOf: [0xFF, 0xE0, 0x00, 0x04, marker, marker])
        data.append(contentsOf: [
            0xFF, 0xC0, 0x00, 0x11, 0x08,
            UInt8(height >> 8), UInt8(height & 0xFF),
            UInt8(width >> 8), UInt8(width & 0xFF)
        ])
        data.append(contentsOf: Array(repeating: marker, count: 8))
        data.append(contentsOf: [0xFF, 0xD9])
        return data
    }

    @Test("A JPEG's dimensions are read from its SOF header")
    func testPixelSize() throws {
        let size = try #require(SurroundViewDecoder.pixelSize(ofJPEG: sizedJPEG(width: 4472, height: 720)))
        #expect(size.width == 4472)
        #expect(size.height == 720)
    }

    @Test("Bytes that only look like a JPEG report no dimensions")
    func testPixelSizeOfHeaderlessFrame() {
        #expect(SurroundViewDecoder.pixelSize(ofJPEG: fakeJPEG(marker: 0x11)) == nil)
        #expect(SurroundViewDecoder.pixelSize(ofJPEG: Data()) == nil)
        #expect(SurroundViewDecoder.pixelSize(ofJPEG: Data([0xFF, 0xD8])) == nil)
    }

    /// A real Kia capture measures 4472x720 but carries no `imageSize`,
    /// so the geometry has to come from the strip itself. The reconstructed
    /// array must match what Hyundai states outright.
    @Test("The reference strip's geometry is reconstructed from its dimensions")
    func testInferredImageSize() throws {
        let inferred = try #require(SurroundViewDecoder.inferredImageSize(width: 4472, height: 720))
        #expect(inferred == [4472, 720, 960, 720, 632, 720])
    }

    /// The remainder rule has to keep the layout divisible at any scale,
    /// including one where scaling the panel width rounds.
    @Test("A scaled strip still tiles into five panels")
    func testInferredImageSizeScales() throws {
        let inferred = try #require(SurroundViewDecoder.inferredImageSize(width: 2236, height: 360))
        #expect(inferred.count == 6)
        let tiles = SurroundViewDecoder.tiles(imageSize: inferred, frameCount: 1)
        #expect(tiles.count == 5)
        #expect(tiles.map(\.position) == [.front, .rear, .left, .right, .topDown])
    }

    /// Anything not shaped like the known layout must stay whole rather
    /// than be sliced on a guess.
    @Test("An unfamiliar aspect ratio is not tiled")
    func testUnfamiliarAspectNotInferred() {
        #expect(SurroundViewDecoder.inferredImageSize(width: 1920, height: 1080) == nil)
        #expect(SurroundViewDecoder.inferredImageSize(width: 4472, height: 1000) == nil)
        #expect(SurroundViewDecoder.inferredImageSize(width: 0, height: 720) == nil)
    }

    @Test("A capture with no imageSize is tiled from the frame itself")
    func testTilesFallBackToFrameDimensions() {
        let tiles = SurroundViewDecoder.tiles(
            imageSize: [],
            frames: [sizedJPEG(width: 4472, height: 720)]
        )

        #expect(tiles.count == 5)
        #expect(tiles.map(\.position) == [.front, .rear, .left, .right, .topDown])
        #expect(tiles[0].crop?.width == 960)
        #expect(tiles[4].crop?.width == 632)
        #expect(tiles[4].crop?.originX == 3840)
    }

    /// A payload that DOES state its geometry must keep winning — the
    /// inference is a fallback, never an override.
    @Test("A stated imageSize takes precedence over the frame's dimensions")
    func testStatedImageSizeWins() {
        let tiles = SurroundViewDecoder.tiles(
            imageSize: [4472, 720, 1120, 720, 1112, 720],
            frames: [sizedJPEG(width: 4472, height: 720)]
        )

        // Three 1120-wide panels plus a 1112-wide bird's-eye — nothing
        // like the inferred layout, which proves the stated array was used.
        #expect(tiles.count == 4)
        #expect(tiles.prefix(3).allSatisfy { $0.crop?.width == 1120 })
        #expect(tiles.last?.crop?.width == 1112)
    }

    // MARK: - Redaction

    /// SVM reports position as `coordLat`/`coordLon` rather than the
    /// `lat`/`lon` the status endpoints use. The original rule matched
    /// only the bare keys, so a capture's precise coordinates travelled
    /// verbatim into persisted logs and debug exports.
    @Test("Surround view coordinates are redacted")
    func testSurroundViewCoordinatesRedacted() throws {
        let body = #"{"gpsDetail":{"coordLat":43.653226,"coordLon":-79.383184,"head":93}}"#
        let redacted = try #require(SensitiveDataRedactor.redact(body))

        #expect(!redacted.contains("43.653226"))
        #expect(!redacted.contains("-79.383184"))
        // Heading is not a position on its own — keep it for debugging.
        #expect(redacted.contains("\"head\":93"))
    }

    @Test("Bare and quoted coordinate spellings are still redacted")
    func testCoordinateSpellingsRedacted() throws {
        let body = #"{"lat":43.65,"lon":-79.38,"latitude":"43.65","vehicleLongitude":-79.38}"#
        let redacted = try #require(SensitiveDataRedactor.redact(body))

        #expect(!redacted.contains("43.65"))
        #expect(!redacted.contains("-79.38"))
    }

    /// The prefixed form requires a capital, so ordinary words that
    /// merely end in "lat"/"lon" keep their values.
    @Test("Words ending in lat or lon are not mistaken for coordinates")
    func testInnocentKeysSurvive() throws {
        let body = #"{"flat":3,"gallon":12,"translation":7}"#
        #expect(SensitiveDataRedactor.redact(body) == body)
    }

    /// Redaction output is persisted and re-parsed, so a rule that eats
    /// an opening quote without its closing one corrupts the whole log.
    /// A value that isn't a clean number must be left alone rather than
    /// half-consumed.
    @Test("Redaction never produces malformed JSON")
    func testRedactionKeepsJSONValid() throws {
        let bodies = [
            #"{"coordLat":43.653226,"coordLon":-79.383184}"#,
            #"{"coordLat":"43.65","coordLon":"-79.38"}"#,
            #"{"lat":43.65,"lon":-79.38}"#,
            #"{"coordLat":"43.6abc"}"#,
            #"{"latitude":"","longitude":null}"#
        ]

        for body in bodies {
            let redacted = try #require(SensitiveDataRedactor.redact(body))
            #expect(
                (try? JSONSerialization.jsonObject(with: Data(redacted.utf8))) != nil,
                "redacting \(body) produced invalid JSON: \(redacted)"
            )
        }
    }

    /// Redaction runs over already-redacted text in some paths, so it has
    /// to be idempotent — a second pass must not chew into the marker.
    @Test("Redacting twice is the same as redacting once")
    func testRedactionIdempotent() throws {
        let body = #"{"gpsDetail":{"coordLat":43.653226,"coordLon":-79.383184}}"#
        let once = try #require(SensitiveDataRedactor.redact(body))
        #expect(SensitiveDataRedactor.redact(once) == once)
    }

    /// Elision runs before redaction. It must not swallow the
    /// coordinates before the redactor can reach them.
    @Test("A full SVM body is both elided and redacted")
    func testFullPayloadElidedAndRedacted() throws {
        let image = String(repeating: "A", count: 20_000)
        let body = #"{"svmImage":"\#(image)","gpsDetail":{"coordLat":43.653226,"coordLon":-79.383184}}"#

        let elided = try #require(SensitiveDataRedactor.elideOversizedValues(body))
        let redacted = try #require(SensitiveDataRedactor.redact(elided))

        #expect(!redacted.contains(image))
        #expect(!redacted.contains("43.653226"))
        #expect(!redacted.contains("-79.383184"))
        #expect(try JSONSerialization.jsonObject(with: Data(redacted.utf8)) is [String: Any])
    }

    /// Kia's "360 View" envelope is a different shape again — the fix is
    /// `location.coord.{lat,lon}` and the imagery hangs off `image`
    /// rather than `svmImage`. Elision is size-based rather than
    /// key-based, so it catches Kia's field name for free; the bare
    /// `lat`/`lon` keys are already covered by the coordinate rule. Both
    /// are asserted here so a change to either rule can't quietly
    /// un-redact a Kia capture.
    @Test("A full Kia 360 View body is both elided and redacted")
    func testKiaPayloadElidedAndRedacted() throws {
        let image = String(repeating: "A", count: 20_000)
        let body = #"{"payload":{"svmInfos":[{"svmId":501,"image":"\#(image)","#
            + #""location":{"syncDate":{"utc":"20260826003935","offset":-5},"#
            + #""coord":{"lat":43.653226,"lon":-79.383184,"alt":254}}}]}}"#

        let elided = try #require(SensitiveDataRedactor.elideOversizedValues(body))
        let redacted = try #require(SensitiveDataRedactor.redact(elided))

        #expect(!redacted.contains(image))
        #expect(!redacted.contains("43.653226"))
        #expect(!redacted.contains("-79.383184"))
        // The capture's own identity and timestamp stay readable — they
        // are what makes a log useful for triaging a missing capture.
        #expect(redacted.contains("20260826003935"))
        #expect(try JSONSerialization.jsonObject(with: Data(redacted.utf8)) is [String: Any])
    }

    // MARK: - Flag tolerance

    /// This region mixes JSON booleans and 0/1 for the same concept —
    /// `unit` is `true` under `dte` but `1` under `distanceToEmpty`
    /// (BetterBlue#98) — so the open/closed flags must accept both.
    @Test("Open/closed flags accept booleans, numbers and strings")
    @MainActor func testFlagsTolerateNumbers() throws {
        let payload = Data("""
        {
          "responseHeader": {"responseDesc": "Success", "responseCode": 0},
          "result": {"svmLocations": [{
            "utcTime": "20260826003935",
            "trunkOpen": 1,
            "sidemirrorOpen": "false",
            "doorOpen": {"frontLeft": true, "frontRight": 0, "backLeft": 1, "backRight": false},
            "svmImage": "\(fakeJPEG(marker: 0x11).base64EncodedString())"
          }]}
        }
        """.utf8)

        let capture = try #require(
            try makeClient().parseCanadaSurroundViewResponse(payload, for: makeVehicle()).first
        )
        #expect(capture.trunkOpen == true)
        #expect(capture.sideMirrorOpen == false)
        #expect(capture.doorOpen?.frontLeft == true)
        #expect(capture.doorOpen?.frontRight == false)
        #expect(capture.doorOpen?.backLeft == true)
        #expect(capture.doorOpen?.backRight == false)
    }

    /// An absent flag stays nil so the UI can hide the row, rather than
    /// claiming the trunk is closed when the payload never said.
    @Test("A missing flag stays nil rather than defaulting to false")
    @MainActor func testMissingFlagIsNil() throws {
        let payload = Data("""
        {
          "responseHeader": {"responseDesc": "Success", "responseCode": 0},
          "result": {"svmLocations": [{
            "utcTime": "20260826003935",
            "svmImage": "\(fakeJPEG(marker: 0x11).base64EncodedString())"
          }]}
        }
        """.utf8)

        let capture = try #require(
            try makeClient().parseCanadaSurroundViewResponse(payload, for: makeVehicle()).first
        )
        #expect(capture.trunkOpen == nil)
        #expect(capture.sideMirrorOpen == nil)
        #expect(capture.doorOpen == nil)
    }
}
