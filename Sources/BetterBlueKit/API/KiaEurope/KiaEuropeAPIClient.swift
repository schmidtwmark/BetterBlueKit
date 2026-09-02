//
//  KiaEuropeAPIClient.swift
//  BetterBlueKit
//
//  Kia Europe API Client
//  Based on KiaUvoApiEU from hyundai_kia_connect_api (PR #1123, v4.12.0).
//
//  All the client flows (login ladder, device registration, status fetch,
//  command routing) are shared with Hyundai EU via `EuropeCCSPClient` —
//  this file carries only the brand constants and the response parsers in
//  the sibling extension files.
//

import Foundation

// MARK: - Kia Europe API Client

@MainActor
public final class KiaEuropeAPIClient: APIClientBase, APIClientProtocol, EuropeCCSPClient {

    // MARK: - Constants

    static let brandSpec = EuropeCCSPBrandSpec(
        clientId: "fdc85c00-0a2f-4c64-bcb4-2cfb1500730a",
        clientSecret: "secret",
        appId: "a2b8469b-30a3-4361-8e13-6fceea8fbe74",
        authCfb: "wLTVxwidmH8CfJYBWSnHD6E0huk0ozdiuygB4hLkM5XCgzAL1Dk5sE36d/bx5PFMbZs=",
        pushType: "APNS",
        cciConfig: .kia
    )
    var euBrandSpec: EuropeCCSPBrandSpec { Self.brandSpec }

    var commandToken: String = ""
    var commandTokenExpiration: Date = Date()

    var baseURL: String {
        region.apiBaseURL(for: .kia)
    }
    var authBaseURL: String { "https://idpconnect-eu.kia.com" }
    var apiHost = Brand.kiaBaseUrl(region: Region.europe).replacing(/https:\/\//, with: "")

    public override var apiName: String { "KiaEurope" }

    // MARK: - Overrides

    // `login`, `fetchVehicles`, `fetchVehicleStatus`, and `sendCommand`
    // come from the shared EuropeCCSPClient extension. `registerDevice`
    // must live here because it overrides the APIClientBase default.
    public override func registerDevice() async throws -> String? {
        try await euRegisterDevice()
    }

    public func fetchEVTripSummary(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripSummary]? {
        nil
    }
}
