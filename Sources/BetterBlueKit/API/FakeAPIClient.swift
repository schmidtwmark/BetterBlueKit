//
//  FakeAPIClient.swift
//  BetterBlueKit
//
//  SwiftData-based Fake API Client for Testing and Development
//

import Foundation

// MARK: - Fake API Client

@MainActor
public class FakeAPIClient: APIClientProtocol {
    private let region: Region
    private let username: String
    private let password: String
    private let pin: String
    private let accountId: UUID
    private let vehicleProvider: FakeVehicleProvider

    public init(
        configuration: APIClientConfiguration,
        vehicleProvider: FakeVehicleProvider,
    ) {
        region = configuration.region
        username = configuration.username
        password = configuration.password
        pin = configuration.pin
        accountId = configuration.accountId
        self.vehicleProvider = vehicleProvider

        print("🔧 [FakeAPIClient] Initialized for user '\(configuration.username)' with custom vehicle provider")
    }

    // MARK: - APIClientProtocol Implementation

    public func login() async throws -> AuthToken {
        // Check for debug credential validation failure across all fake vehicles for this account
        if try await vehicleProvider.shouldFailCredentialValidation(accountId: accountId) {
            print("🔴 [FakeAPI] Debug: Simulating credential validation failure")
            let message = try await vehicleProvider.getCustomCredentialErrorMessage(accountId: accountId)
            throw HyundaiKiaAPIError.invalidCredentials(message, apiName: "FakeAPI")
        }

        // Check for debug login failure
        if try await vehicleProvider.shouldFailLogin(accountId: accountId) {
            print("🔴 [FakeAPI] Debug: Simulating login failure")
            throw HyundaiKiaAPIError.logError("Debug: Simulated login failure", code: 500, apiName: "FakeAPI")
        }

        print("🟢 [FakeAPI] Login successful for user '\(username)'")
        return AuthToken(
            accessToken: "fake_access_token_\(UUID().uuidString)",
            refreshToken: "fake_refresh_token_\(UUID().uuidString)",
            expiresAt: Date().addingTimeInterval(3600),
            pin: pin,
        )
    }

    public func fetchVehicles(authToken _: AuthToken) async throws -> [Vehicle] {
        // Check for debug vehicle fetch failure
        if try await vehicleProvider.shouldFailVehicleFetch(accountId: accountId) {
            print("🔴 [FakeAPI] Debug: Simulating vehicle fetch failure")
            throw HyundaiKiaAPIError.logError("Debug: Simulated vehicle fetch failure", code: 500, apiName: "FakeAPI")
        }

        print("🚗 [FakeAPI] Fetching vehicles for user '\(username)'...")
        let vehicles = try await vehicleProvider.getFakeVehicles(for: username, accountId: accountId)
        print("🟢 [FakeAPI] Fetched \(vehicles.count) fake vehicles for user '\(username)': " +
            "[\(vehicles.map(\.vin).joined(separator: ", "))]")
        return vehicles
    }

    public func fetchVehicleStatus(for vehicle: Vehicle, authToken _: AuthToken) async throws -> VehicleStatus {
        // Check for debug status fetch failure
        if try await vehicleProvider.shouldFailStatusFetch(for: vehicle.vin, accountId: accountId) {
            print("🔴 [FakeAPI] Debug: Simulating status fetch failure")
            throw HyundaiKiaAPIError.logError("Debug: Simulated status fetch failure", code: 500, apiName: "FakeAPI")
        }

        let status = try await vehicleProvider.getVehicleStatus(for: vehicle.vin, accountId: accountId)
        print("🟢 [FakeAPI] Fetched vehicle status for fake vehicle '\(vehicle.vin)'")
        return status
    }

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken _: AuthToken) async throws {
        // Check for debug PIN validation failure
        if try await vehicleProvider.shouldFailPinValidation(for: vehicle.vin, accountId: accountId) {
            print("🔴 [FakeAPI] Debug: Simulating PIN validation failure")
            let errorMessage = try await vehicleProvider.getCustomPinErrorMessage(
                for: vehicle.vin,
                accountId: accountId,
            )
            throw HyundaiKiaAPIError.invalidPin(errorMessage, apiName: "FakeAPI")
        }

        // Check for debug command-specific failures
        if try await vehicleProvider.shouldFailCommand(command, for: vehicle.vin, accountId: accountId) {
            let commandName = String(describing: command).components(separatedBy: "(").first ?? "command"
            print("🔴 [FakeAPI] Debug: Simulating \(commandName) failure")
            throw HyundaiKiaAPIError.logError("Debug: Simulated \(commandName) failure", code: 500, apiName: "FakeAPI")
        }

        try await vehicleProvider.executeCommand(command, for: vehicle.vin, accountId: accountId)
        print("🟢 [FakeAPI] Command completed successfully for fake vehicle '\(vehicle.vin)'")
    }
}

// MARK: - Vehicle Provider Protocol

@MainActor
public protocol FakeVehicleProvider {
    func getFakeVehicles(for username: String, accountId: UUID) async throws -> [Vehicle]
    func getVehicleStatus(for vin: String, accountId: UUID) async throws -> VehicleStatus
    func executeCommand(_ command: VehicleCommand, for vin: String, accountId: UUID) async throws

    // Debug configuration checks
    func shouldFailCredentialValidation(accountId: UUID) async throws -> Bool
    func shouldFailLogin(accountId: UUID) async throws -> Bool
    func shouldFailVehicleFetch(accountId: UUID) async throws -> Bool
    func shouldFailStatusFetch(for vin: String, accountId: UUID) async throws -> Bool
    func shouldFailPinValidation(for vin: String, accountId: UUID) async throws -> Bool
    func shouldFailCommand(_ command: VehicleCommand, for vin: String, accountId: UUID) async throws -> Bool
    func getCustomCredentialErrorMessage(accountId: UUID) async throws -> String
    func getCustomPinErrorMessage(for vin: String, accountId: UUID) async throws -> String
}
