//
//  GenesisUSATests.swift
//  BetterBlueKit
//
//  Genesis USA rides on HyundaiUSAAPIClient (same HATA backend). These
//  cover what differs from Hyundai — factory wiring, `brandIndicator`,
//  the cached-status 502 fallback, the advertised features — and parse
//  a real Genesis payload: a 2025 GV70 EV from kia_uvo#1455, as committed
//  to hyundai_kia_connect_api's fixtures (VIN, regid, and coordinates
//  already anonymized there), trimmed to the fields the parser reads.
//

import Foundation
import Testing
@testable import BetterBlueKit

// MARK: - Sample JSON

enum GenesisUSASampleJSON {

    /// `ac/v2/enrollment/details/<user>` — kia_uvo#1455, trimmed.
    static let gv70Enrollment = """
    {
      "enrolledVehicleDetails": [
        {
          "vehicleDetails": {
            "vin": "TESTVIN0000000001",
            "regid": "VEHICLE-1",
            "nickName": "2025 GV70 EV",
            "modelCode": "GV70 EV",
            "modelYear": "2025",
            "evStatus": "E",
            "vehicleGeneration": "2",
            "brandIndicator": "G",
            "odometer": "17332",
            "enrollmentStatus": "ACTIVE"
          }
        }
      ]
    }
    """

    /// `ac/v2/rcs/rvs/vehicleStatus` — kia_uvo#1455, trimmed (charge
    /// schedules dropped).
    static let gv70Status = """
    {
      "hataTID": "XXX",
      "vehicleStatus": {
        "dateTime": "2025-12-28T17:51:42Z",
        "doorLock": false,
        "doorOpen": { "frontRight": 0, "frontLeft": 0, "backLeft": 0, "backRight": 0 },
        "trunkOpen": false,
        "hoodOpen": false,
        "airCtrlOn": false,
        "defrost": false,
        "steerWheelHeat": 0,
        "battery": { "batSoc": 88, "batState": 0 },
        "vehicleLocation": { "coord": { "alt": 0, "lon": 13.405, "type": 0, "lat": 52.52 } },
        "tirePressureLamp": {
          "tirePressureWarningLampAll": 0,
          "tirePressureWarningLampFrontLeft": 0,
          "tirePressureWarningLampFrontRight": 0,
          "tirePressureWarningLampRearLeft": 0,
          "tirePressureWarningLampRearRight": 0
        },
        "evStatus": {
          "batteryFstChrgPower": 0.0,
          "batteryStndChrgPower": 0.0,
          "batteryPlugin": 0,
          "batteryCharge": false,
          "batteryStatus": 85,
          "remainTime": [],
          "remainTime2": {
            "etc3": { "unit": 1, "value": 95 },
            "etc2": { "unit": 1, "value": 640 }
          },
          "drvDistance": [
            {
              "rangeByFuel": {
                "totalAvailableRange": { "unit": 3, "value": 192.0 },
                "evModeRange": { "unit": 3, "value": 192.0 }
              },
              "type": 2
            }
          ],
          "reservChargeInfos": {
            "targetSOClist": [
              { "plugType": 0, "targetSOClevel": 100 },
              { "plugType": 1, "targetSOClevel": 100 }
            ]
          }
        }
      }
    }
    """

    /// The cached-read failure Genesis USA has returned since ~May 2026
    /// (hyundai_kia_connect_api 681ef99 / kia_uvo#1651).
    static let cachedStatus502 = """
    {"errorCode":502,"errorSubCode":"GEN","systemName":"HATA","functionName":"remoteVehicleStatus"}
    """
}

// MARK: - Tests

// `.serialized` because the URLProtocol stub keeps process-wide state.
@Suite("Genesis USA", .serialized)
@MainActor
struct GenesisUSATests {

    private func configuration(brand: Brand) -> APIClientConfiguration {
        APIClientConfiguration(
            region: .usa,
            brand: brand,
            username: "test@example.com",
            password: "password123",
            pin: "1234",
            accountId: UUID()
        )
    }

    private var token: AuthToken {
        AuthToken(accessToken: "token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600))
    }

    private var gv70: Vehicle {
        Vehicle(
            vin: "TESTVIN0000000001",
            regId: "VEHICLE-1",
            model: "2025 GV70 EV",
            accountId: UUID(),
            fuelType: .electric,
            generation: 2,
            odometer: Distance(length: 17332, units: .miles)
        )
    }

    // MARK: Wiring

    @Test func `Factory builds a Hyundai USA client for Genesis USA`() throws {
        let client = try #require(
            try createBetterBlueKitAPIClient(configuration: configuration(brand: .genesis)) as? HyundaiUSAAPIClient
        )
        #expect(client.apiName == "GenesisUSA")
        #expect(client.baseURL == "https://api.telematics.hyundaiusa.com")
        #expect(supportedRegions(for: .genesis).contains(.usa))
        #expect(betaRegions(for: .genesis).contains(.usa))
    }

    @Test func `Genesis sends brandIndicator G, Hyundai keeps H`() {
        let genesis = HyundaiUSAAPIClient(configuration: configuration(brand: .genesis))
        let hyundai = HyundaiUSAAPIClient(configuration: configuration(brand: .hyundai))

        #expect(genesis.authorizedHeaders(authToken: token, vehicle: gv70)["brandIndicator"] == "G")
        #expect(hyundai.authorizedHeaders(authToken: token, vehicle: gv70)["brandIndicator"] == "H")
        #expect(hyundai.apiName == "HyundaiUSA")
    }

    @Test func `Genesis doesn't advertise surround view`() {
        let genesis = HyundaiUSAAPIClient(configuration: configuration(brand: .genesis))
        #expect(genesis.optionalFeaturesSupported() == [.evTripSummary])
    }

    // MARK: Parsing

    @Test func `Parses the GV70 EV enrollment`() throws {
        let client = HyundaiUSAAPIClient(configuration: configuration(brand: .genesis))
        let vehicles = try client.parseVehiclesResponse(Data(GenesisUSASampleJSON.gv70Enrollment.utf8))

        let vehicle = try #require(vehicles.first)
        #expect(vehicles.count == 1)
        #expect(vehicle.vin == "TESTVIN0000000001")
        #expect(vehicle.regId == "VEHICLE-1")
        #expect(vehicle.fuelType == .electric)
        #expect(vehicle.generation == 2)
        #expect(vehicle.odometer.length == 17332)
    }

    @Test func `Parses the GV70 EV status`() throws {
        let client = HyundaiUSAAPIClient(configuration: configuration(brand: .genesis))
        let status = try client.parseVehicleStatusResponse(Data(GenesisUSASampleJSON.gv70Status.utf8), for: gv70)

        let ev = try #require(status.evStatus)
        #expect(ev.evRange.percentage == 85)
        #expect(ev.evRange.range.length == 192)
        #expect(ev.evRange.range.units == .miles)
        #expect(ev.charging == false)
        #expect(status.lockStatus == .unlocked)
        #expect(status.battery12V == 88)
        #expect(status.location.latitude == 52.52)
    }

    // MARK: Cached-status fallback

    @Test func `Genesis cached-status 502 GEN retries live`() async throws {
        StubProtocol.reset([
            (502, GenesisUSASampleJSON.cachedStatus502),
            (200, GenesisUSASampleJSON.gv70Status)
        ])
        let client = HyundaiUSAAPIClient(configuration: configuration(brand: .genesis), urlSession: stubSession())

        let status = try await client.fetchVehicleStatus(for: gv70, authToken: token, cached: true)

        #expect(status.evStatus?.evRange.percentage == 85)
        #expect(StubProtocol.refreshHeaders == ["false", "true"])
    }

    @Test func `Hyundai cached-status 502 is not retried`() async throws {
        StubProtocol.reset([
            (502, GenesisUSASampleJSON.cachedStatus502),
            (200, GenesisUSASampleJSON.gv70Status)
        ])
        let client = HyundaiUSAAPIClient(configuration: configuration(brand: .hyundai), urlSession: stubSession())

        await #expect(throws: APIError.self) {
            _ = try await client.fetchVehicleStatus(for: gv70, authToken: token, cached: true)
        }
        #expect(StubProtocol.refreshHeaders == ["false"])
    }

    @Test func `Genesis live-status 502 is not retried`() async throws {
        StubProtocol.reset([
            (502, GenesisUSASampleJSON.cachedStatus502),
            (200, GenesisUSASampleJSON.gv70Status)
        ])
        let client = HyundaiUSAAPIClient(configuration: configuration(brand: .genesis), urlSession: stubSession())

        await #expect(throws: APIError.self) {
            _ = try await client.fetchVehicleStatus(for: gv70, authToken: token, cached: false)
        }
        #expect(StubProtocol.refreshHeaders == ["true"])
    }

    // MARK: Stub

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// Answers every request from a queue, in order, and records each
    /// request's `refresh` header.
    private final class StubProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var queue: [(Int, String)] = []
        nonisolated(unsafe) static var refreshHeaders: [String] = []

        static func reset(_ responses: [(Int, String)]) {
            queue = responses
            refreshHeaders = []
        }

        override class func canInit(with _: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.refreshHeaders.append(request.value(forHTTPHeaderField: "refresh") ?? "")
            let answer = Self.queue.isEmpty ? (404, "{}") : Self.queue.removeFirst()

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: answer.0,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(answer.1.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }
}
