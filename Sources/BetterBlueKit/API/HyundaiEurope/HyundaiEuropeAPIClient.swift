//
//  HyundaiEuropeAPIClient.swift
//  BetterBlueKit
//
//  Hyundai Europe API Client
//  Based on: https://github.com/andyfase/egmp-bluelink-scriptable
//
//  All the client flows (login ladder, device registration, status fetch,
//  command routing) are shared with Kia EU via `EuropeCCSPClient` — this
//  file carries only the brand constants and the response parsers in the
//  sibling extension files.
//

import Foundation

// MARK: - Hyundai Europe API Client

@MainActor
public final class HyundaiEuropeAPIClient: APIClientBase, APIClientProtocol, EuropeCCSPClient {

    // MARK: - Constants

    static let brandSpec = EuropeCCSPBrandSpec(
        clientId: "6d477c38-3ca4-4cf3-9557-2a1929a94654",
        clientSecret: "KUy49XxPzLpLuoK0xhBC77W6VXhmtQR9iQhmIFjjoY4IpxsV",
        appId: "014d2225-8495-4735-812d-2616334fd15d",
        authCfb: "RFtoRq/vDXJmRndoZaZQyfOot7OrIqGVFj96iY2WL3yyH5Z/pUvlUhqmCxD2t+D65SQ=",
        pushType: "GCM",
        cciConfig: .hyundai
    )
    var euBrandSpec: EuropeCCSPBrandSpec { Self.brandSpec }

    var commandToken: String = ""
    var commandTokenExpiration: Date = Date()

    var baseURL: String {
        region.apiBaseURL(for: .hyundai)
    }
    var authBaseURL: String { "https://idpconnect-eu.hyundai.com" }
    var apiHost = Brand.hyundaiBaseUrl(region: Region.europe).replacing(/https:\/\//, with: "")

    public override var apiName: String { "HyundaiEurope" }

    // MARK: - Overrides

    // `login`, `fetchVehicles`, `fetchVehicleStatus`, and `sendCommand`
    // come from the shared EuropeCCSPClient extension. `registerDevice`
    // must live here because it overrides the APIClientBase default.
    public override func registerDevice() async throws -> String? {
        try await euRegisterDevice()
    }

    // Trip history (fetchEVTripSummary / fetchEVTripInfo) lives in
    // `HyundaiEuropeAPIClient+TripDetails.swift`.
}
