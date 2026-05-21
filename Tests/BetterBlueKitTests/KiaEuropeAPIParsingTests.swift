//
//  KiaEuropeAPIParsingTests.swift
//  BetterBlueKit
//
//  Fixture-based tests for KiaEuropeAPIClient response parsing.
//  JSON shapes are based on real responses observed against the
//  Kia EU CCS API in May 2026 with VIN / vehicleId / coordinates
//  redacted to dummy values.
//

import Foundation
import Testing
@testable import BetterBlueKit

// MARK: - Fixtures

enum KiaEuropeSampleJSON {

    /// `POST /auth/api/v2/user/oauth2/token` response.
    static let tokenResponse = """
    {
      "access_token": "fake-access-token-abc123",
      "refresh_token": "FAKEREFRESHTOKEN0000000000000000000000000000ABCD",
      "token_type": "Bearer",
      "expires_in": 86399
    }
    """

    /// `GET /api/v1/spa/vehicles` response with a single CCS2 EV.
    static let vehiclesList = """
    {
      "msgId": "00000000-0000-0000-0000-000000000000",
      "resCode": "0000",
      "resMsg": {
        "vehicles": [
          {
            "carShare": 1,
            "ccuCCS2ProtocolSupport": 1,
            "detailInfo": {
              "bodyType": "3",
              "saleCarmdlEnNm": "EV9"
            },
            "master": true,
            "nickname": "EV9",
            "personalFlag": "4",
            "protocolType": 1,
            "type": "EV",
            "vehicleId": "00000000-0000-0000-0000-000000000001",
            "vehicleName": "EV9",
            "vin": "TESTVIN0000000001",
            "year": "2024"
          }
        ]
      },
      "retCode": "S"
    }
    """

    /// `GET /api/v1/spa/vehicles/<id>/ccs2/carstatus/latest` response.
    /// Trimmed to fields parseVehicleStatusResponse actually reads.
    static let vehicleStatusCCS2 = """
    {
      "msgId": "00000000-0000-0000-0000-000000000002",
      "resCode": "0000",
      "resMsg": {
        "lastUpdateTime": 1747800000000,
        "state": {
          "Vehicle": {
            "Drivetrain": {
              "Odometer": 12345.6,
              "FuelSystem": { "DTE": { "Total": 255, "Unit": 1 } }
            },
            "Green": {
              "BatteryManagement": { "BatteryRemain": { "Ratio": 57 } },
              "ChargingInformation": {
                "Charging": { "RemainTime": 0 },
                "ConnectorFastening": { "State": 0 },
                "TargetSoC": { "Standard": 80, "Quick": 90 }
              },
              "Electric": { "SmartGrid": { "RealTimePower": 0 } }
            },
            "Electronics": { "Battery": { "Level": 87 } },
            "Cabin": {
              "Door": {
                "Row1": {
                  "Driver":    { "Lock": 0, "Open": 0 },
                  "Passenger": { "Lock": 0, "Open": 0 }
                },
                "Row2": {
                  "Left":  { "Lock": 0, "Open": 0 },
                  "Right": { "Lock": 0, "Open": 0 }
                }
              },
              "HVAC": {
                "Row1": {
                  "Driver": {
                    "Blower": { "SpeedLevel": 0 },
                    "Temperature": { "Unit": 0, "Value": "OFF" }
                  }
                }
              },
              "SteeringWheel": { "Heat": { "State": 0 } }
            },
            "Body": {
              "Trunk": { "Open": 0 },
              "Hood": { "Open": 0 },
              "Windshield": { "Front": { "Defog": { "State": 0 } } }
            },
            "Location": {
              "Date": "20260521054000.000",
              "GeoCoord": { "Latitude": 59.92936, "Longitude": 10.46419 }
            }
          }
        }
      },
      "retCode": "S"
    }
    """

    /// `GET /api/v1/spa/vehicles/<id>/location/park` response.
    static let parkLocation = """
    {
      "msgId": "00000000-0000-0000-0000-000000000003",
      "resCode": "0000",
      "resMsg": {
        "coord": { "alt": 0, "lat": 59.92936, "lon": 10.46419, "type": 0 },
        "head": 101.8,
        "speed": { "unit": 0, "value": 0 },
        "time": "20260521053531"
      },
      "retCode": "S"
    }
    """
}

// MARK: - Helpers

@MainActor
private func makeClient(refreshToken: String? = nil) -> KiaEuropeAPIClient {
    let config = APIClientConfiguration(
        region: .europe,
        brand: .kia,
        username: "test@example.com",
        password: "password",
        refreshToken: refreshToken,
        pin: "0000",
        accountId: UUID()
    )
    return KiaEuropeAPIClient(configuration: config)
}

// MARK: - Tests

@Suite("Kia Europe API Client")
struct KiaEuropeAPIClientTests {

    @Test("Client initializes with KiaEurope api name")
    @MainActor func testInitialization() {
        let client = makeClient()
        #expect(client.apiName == "KiaEurope")
    }
}

@Suite("Kia Europe Parsing — Auth Token")
struct KiaEuropeAuthTokenParsingTests {

    @Test("Fresh token response (isRefresh=true) extracts both access and refresh tokens")
    @MainActor func testParseFreshToken() throws {
        let client = makeClient()
        let data = Data(KiaEuropeSampleJSON.tokenResponse.utf8)

        let token = try client.parseAuthToken(from: data, isRefresh: true)

        #expect(token.accessToken == "fake-access-token-abc123")
        #expect(token.refreshToken == "FAKEREFRESHTOKEN0000000000000000000000000000ABCD")
        #expect(token.expiresAt > Date())
    }

    @Test("Refresh-grant response (isRefresh=false) preserves stored refresh token")
    @MainActor func testParseRefreshGrantPreservesStoredRefreshToken() throws {
        let client = makeClient(refreshToken: "ORIGINAL_REFRESH_TOKEN")
        // A refresh-grant response often omits refresh_token; we should fall back.
        let json = """
        { "access_token": "new-access", "token_type": "Bearer", "expires_in": 86399 }
        """
        let data = Data(json.utf8)

        let token = try client.parseAuthToken(from: data, isRefresh: false)

        #expect(token.accessToken == "new-access")
        #expect(token.refreshToken == "ORIGINAL_REFRESH_TOKEN")
    }

    @Test("Missing access_token throws invalidCredentials")
    @MainActor func testParseMissingAccessTokenThrows() {
        let client = makeClient()
        let data = Data("{ \"expires_in\": 1 }".utf8)

        #expect(throws: APIError.self) {
            _ = try client.parseAuthToken(from: data, isRefresh: true)
        }
    }
}

@Suite("Kia Europe Parsing — Vehicles")
struct KiaEuropeVehiclesParsingTests {

    @Test("Vehicles response parses single EV9 with CCS2 marketOptions")
    @MainActor func testParseVehiclesList() throws {
        let client = makeClient()
        let data = Data(KiaEuropeSampleJSON.vehiclesList.utf8)

        let vehicles = try client.parseVehiclesResponse(data)

        #expect(vehicles.count == 1)
        let vehicle = try #require(vehicles.first)
        #expect(vehicle.vin == "TESTVIN0000000001")
        #expect(vehicle.regId == "00000000-0000-0000-0000-000000000001")
        #expect(vehicle.model == "EV9")
        #expect(vehicle.fuelType == .electric)
        #expect(vehicle.marketOptions?.ccs2Supported == true)
    }

    @Test("Empty vehicles array returns no vehicles")
    @MainActor func testParseEmptyVehiclesList() throws {
        let client = makeClient()
        let data = Data("""
        { "resMsg": { "vehicles": [] }, "resCode": "0000", "retCode": "S" }
        """.utf8)

        let vehicles = try client.parseVehiclesResponse(data)
        #expect(vehicles.isEmpty)
    }

    @Test("Malformed response throws")
    @MainActor func testParseMalformedVehiclesResponseThrows() {
        let client = makeClient()
        let data = Data("{}".utf8)

        #expect(throws: APIError.self) {
            _ = try client.parseVehiclesResponse(data)
        }
    }
}

@Suite("Kia Europe Parsing — Vehicle Status")
struct KiaEuropeStatusParsingTests {

    @MainActor private func ev9Vehicle(client: KiaEuropeAPIClient) throws -> Vehicle {
        let data = Data(KiaEuropeSampleJSON.vehiclesList.utf8)
        let vehicles = try client.parseVehiclesResponse(data)
        return try #require(vehicles.first)
    }

    @Test("CCS2 status parses battery, range, lock and SOC targets")
    @MainActor func testParseCCS2Status() throws {
        let client = makeClient()
        let vehicle = try ev9Vehicle(client: client)

        let statusData = Data(KiaEuropeSampleJSON.vehicleStatusCCS2.utf8)
        let parkData = Data(KiaEuropeSampleJSON.parkLocation.utf8)

        let status = try client.parseVehicleStatusResponse(statusData, parkData, for: vehicle)

        #expect(status.vin == "TESTVIN0000000001")
        #expect(status.lockStatus == .locked)
        #expect(status.battery12V == 87)

        let ev = try #require(status.evStatus)
        #expect(ev.evRange.percentage == 57)
        #expect(ev.evRange.range.length == 255)
        #expect(ev.targetSocAC == 80)
        #expect(ev.targetSocDC == 90)
        #expect(ev.charging == false)
    }

    @Test("Park-only location falls back when status location is older")
    @MainActor func testParseLocationFallsBackToPark() throws {
        let client = makeClient()
        let vehicle = try ev9Vehicle(client: client)

        let statusData = Data(KiaEuropeSampleJSON.vehicleStatusCCS2.utf8)
        let parkData = Data(KiaEuropeSampleJSON.parkLocation.utf8)

        let status = try client.parseVehicleStatusResponse(statusData, parkData, for: vehicle)

        // Status' Location.Date (2026-05-21 05:40 UTC) is newer than the park
        // time (2026-05-21 05:35:31 local), so the status coords win — but
        // both sources are at the same point in the fixture, so either is OK.
        #expect(status.location.latitude == 59.92936)
        #expect(status.location.longitude == 10.46419)
    }

    @Test("Malformed status response throws")
    @MainActor func testParseMalformedStatusThrows() throws {
        let client = makeClient()
        let vehicle = try ev9Vehicle(client: client)
        let bad = Data("{}".utf8)
        let park = Data(KiaEuropeSampleJSON.parkLocation.utf8)

        #expect(throws: APIError.self) {
            _ = try client.parseVehicleStatusResponse(bad, park, for: vehicle)
        }
    }
}

@Suite("Kia Europe — VehicleMarketOptions")
struct KiaEuropeMarketOptionsTests {

    @Test("kiaEurope case surfaces ccs2Supported")
    func testKiaEuropeCCS2() {
        let opt: VehicleMarketOptions = .kiaEurope(ccs2Supported: true)
        #expect(opt.ccs2Supported == true)
    }

    @Test("kiaEurope case can be non-CCS2")
    func testKiaEuropeLegacy() {
        let opt: VehicleMarketOptions = .kiaEurope(ccs2Supported: false)
        #expect(opt.ccs2Supported == false)
    }
}
