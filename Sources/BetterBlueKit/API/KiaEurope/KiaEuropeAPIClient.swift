//
//  KiaEuropeAPIClient.swift
//  BetterBlueKit
//
//  Kia Europe API Client
//  Based on KiaUvoApiEU from hyundai_kia_connect_api (PR #1123, v4.12.0)
//  which integrates a headless IDPConnect login flow and drops curl_cffi
//  by appending `_CCS_APP_AOS` to the User-Agent.
//

import CryptoKit
import Foundation

// MARK: - Kia Europe API Client

@MainActor
public final class KiaEuropeAPIClient: APIClientBase, APIClientProtocol {

    // MARK: - Constants

    static let clientId = "fdc85c00-0a2f-4c64-bcb4-2cfb1500730a"
    static let clientSecret = "secret"
    static let appId = "a2b8469b-30a3-4361-8e13-6fceea8fbe74"
    static let basicAuthorization = "Basic ZmRjODVjMDAtMGEyZi00YzY0LWJjYjQtMmNmYjE1MDA3MzBhOnNlY3JldA=="
    static let authCfb = "wLTVxwidmH8CfJYBWSnHD6E0huk0ozdiuygB4hLkM5XCgzAL1Dk5sE36d/bx5PFMbZs="
    static let pushType = "APNS"

    var stamp = ""
    var commandToken: String = ""
    var commandTokenExpiration: Date = Date()

    var baseURL: String {
        region.apiBaseURL(for: .kia)
    }
    var authBaseURL: String { "https://idpconnect-eu.kia.com" }
    var apiHost = Brand.kiaBaseUrl(region: Region.europe).replacing(/https:\/\//, with: "")

    public override var apiName: String { "KiaEurope" }

    // MARK: - Login (stub — implemented in Fase 2)

    public func login() async throws -> AuthToken {
        throw APIError.regionNotSupported(
            "Kia Europe login flow is not yet implemented. " +
            "Tracked in branch kia-europe-support.",
            apiName: apiName
        )
    }

    // MARK: - Vehicles (stub — implemented in Fase 3)

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        throw APIError.regionNotSupported("Kia Europe is not yet implemented.", apiName: apiName)
    }

    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken,
        cached _: Bool
    ) async throws -> VehicleStatus {
        throw APIError.regionNotSupported("Kia Europe is not yet implemented.", apiName: apiName)
    }

    // MARK: - Commands (stub — implemented in Fase 4)

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        throw APIError.regionNotSupported("Kia Europe is not yet implemented.", apiName: apiName)
    }

    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        nil
    }
}
