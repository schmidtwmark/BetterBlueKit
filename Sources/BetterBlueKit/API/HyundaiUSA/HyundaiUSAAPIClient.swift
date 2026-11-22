//
//  HyundaiUSAAPIClient.swift
//  BetterBlueKit
//
//  Hyundai USA API Client — also serves Genesis USA.
//
//  Genesis USA runs on the same HATA backend as Hyundai USA: same host,
//  client_id/secret, paths, and bodies. hyundai_kia_connect_api maps
//  (USA, Genesis) straight onto its Hyundai USA class, and the
//  ha_kia_hyundai_USA integration's Genesis client (`us_genesis.py`,
//  tested on GV60 / GV70 / G70) differs from its Hyundai one only in
//  sending `brandIndicator: G` and in the cached-status fallback below.
//

import Foundation

// MARK: - Hyundai USA API Client

@MainActor
public final class HyundaiUSAAPIClient: APIClientBase, APIClientProtocol {

    // MARK: - Constants

    private let clientId = "m66129Bb-em93-SPAHYN-bZ91-am4540zp19920"
    private let clientSecret = "v558o935-6nne-423i-baa8"

    var baseURL: String {
        region.apiBaseURL(for: .hyundai)
    }

    var apiHost: String {
        "api.telematics.hyundaiusa.com"
    }

    var isGenesis: Bool { brand == .genesis }

    public override var apiName: String { isGenesis ? "GenesisUSA" : "HyundaiUSA" }

    /// "G" for Genesis (ha_kia_hyundai_USA `us_genesis.py`), "H" for Hyundai.
    var brandIndicator: String { isGenesis ? "G" : "H" }

    // MARK: - Headers

    func headers() -> [String: String] {
        [
            "client_id": clientId,
            "clientSecret": clientSecret,
            "Host": apiHost,
            "User-Agent": "okhttp/3.12.0",
            "Content-Type": "application/json",
            "Accept": "application/json, text/plain, */*",
            "Accept-Encoding": "gzip, deflate, br",
            "Accept-Language": "en-US,en;q=0.9",
            "Connection": "Keep-Alive"
        ]
    }

    func authorizedHeaders(authToken: AuthToken, vehicle: Vehicle? = nil, refresh: Bool = false) -> [String: String] {
        var result = headers()
        result["accessToken"] = authToken.accessToken
        result["language"] = "0"
        result["to"] = "ISS"
        result["encryptFlag"] = "false"
        result["from"] = "SPA"
        result["offset"] = "-5"
        result["brandIndicator"] = brandIndicator
        result["origin"] = "https://\(apiHost)"
        result["referer"] = "https://\(apiHost)/login"
        result["username"] = username
        result["blueLinkServicePin"] = pin
        // "refresh: true" forces the backend to poll the vehicle's modem for
        // current state instead of returning the last cached snapshot. This
        // is what MyHyundai uses for pull-to-refresh.
        result["refresh"] = refresh ? "true" : "false"

        if let vehicle {
            result["gen"] = String(vehicle.generation)
            result["registrationId"] = vehicle.regId
            result["vin"] = vehicle.vin
            result["APPCLOUD-VIN"] = vehicle.vin
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        result["payloadGenerated"] = dateFormatter.string(from: Date())
        result["includeNonConnectedVehicles"] = "Y"

        return result
    }

    // MARK: - APIClientProtocol Implementation

    public func login() async throws -> AuthToken {
        BBLogger.info(.auth, "\(apiName): Attempting login for \(username)")

        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/v2/ac/oauth/token",
            method: .POST,
            headers: headers(),
            body: ["username": username, "password": password],
            requestType: .login
        )

        return try parseLoginResponse(data)
    }

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/ac/v2/enrollment/details/\(username)",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken),
            requestType: .fetchVehicles
        )

        return try parseVehiclesResponse(data)
    }

    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken,
        cached: Bool
    ) async throws -> VehicleStatus {
        let statusHeaders = authorizedHeaders(authToken: authToken, vehicle: vehicle, refresh: !cached)

        do {
            let (data, _, _) = try await performJSONRequest(
                url: "\(baseURL)/ac/v2/rcs/rvs/vehicleStatus",
                method: .GET,
                headers: statusHeaders,
                requestType: .fetchVehicleStatus,
                vin: vehicle.vin
            )

            return try parseVehicleStatusResponse(data, for: vehicle)
        } catch let error as APIError where error.errorType == .serverError && error.message.contains("HT_533") {
            // A live (`refresh: true`) status read while the vehicle is
            // still busy with a previous request — typically the command
            // we're verifying — answers HTTP 502 with errorSubCode HT_533.
            // Type it as `.concurrentRequest` so callers can retry quietly
            // instead of surfacing a raw server error.
            throw APIError.concurrentRequest(
                "The vehicle is still processing a previous request. Please wait and try again.",
                apiName: apiName
            )
        } catch let error as APIError where cached && isGenesisCachedStatusFailure(error) {
            // Genesis USA's cached read has answered HTTP 502
            // `errorSubCode: GEN` (functionName remoteVehicleStatus) since
            // ~May 2026 while the live read still works — retry it live.
            // Same fallback as hyundai_kia_connect_api 681ef99 and
            // ha_kia_hyundai_USA `us_genesis.py`.
            BBLogger.info(.api, "\(apiName): cached status failed with 502 GEN, retrying with refresh")
            return try await fetchVehicleStatus(for: vehicle, authToken: authToken, cached: false)
        }
    }

    /// Genesis-only: the cached-status 502 (`errorSubCode: GEN`), as
    /// opposed to the `HT_533` "vehicle busy" 502 handled above.
    func isGenesisCachedStatusFailure(_ error: APIError) -> Bool {
        isGenesis
            && error.errorType == .serverError
            && error.message.contains("Server error (502)")
            && error.message.contains("\"GEN\"")
    }

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        try ensureSupported(command)
        let url = commandURL(for: command, vehicle: vehicle)
        var body = commandBody(for: command, vehicle: vehicle)

        var commandHeaders = authorizedHeaders(authToken: authToken, vehicle: vehicle)
        if case .setChargingSchedule(let window) = command {
            let current = try await currentReservChargeInfos(for: vehicle, authToken: authToken)
            body = try Self.chargingScheduleBody(window: window, current: current)
            // As MyHyundai sends this write: the phone's own UTC offset
            // (the times are wall-clock), the token under its snake-case
            // name too, and the EV marker.
            commandHeaders["offset"] = Self.localOffsetHeader()
            commandHeaders["access_token"] = authToken.accessToken
            commandHeaders["loginId"] = username
            commandHeaders["evStatus"] = "E"
        }

        let (data, _, _) = try await performJSONRequest(
            url: url,
            method: .POST,
            headers: commandHeaders,
            body: body,
            requestType: .sendCommand,
            vin: vehicle.vin
        )

        try parseCommandResponse(data)
    }

    /// The car's `reservChargeInfos` from the cached status, for a schedule
    /// write to send everything but the off-peak hours back unchanged.
    /// Throws rather than write without them.
    private func currentReservChargeInfos(for vehicle: Vehicle, authToken: AuthToken) async throws -> [String: Any] {
        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/ac/v2/rcs/rvs/vehicleStatus",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken, vehicle: vehicle, refresh: false),
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        )
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let evStatus = (json?["vehicleStatus"] as? [String: Any])?["evStatus"] as? [String: Any]
        guard let infos = evStatus?["reservChargeInfos"] as? [String: Any],
              infos["offpeakPowerInfo"] != nil else {
            throw APIError.logError("The vehicle didn't report its current charging schedule", apiName: apiName)
        }
        return infos
    }

    public func optionalFeaturesSupported() -> [OptionalAPIFeature] {
        // Genesis USA: EV trip details answered for a GV70 EV in
        // kia_uvo#1455; surround view has no Genesis report either way.
        isGenesis ? [.evTripSummary] : [.evTripSummary, .surroundView, .surroundViewCapture, .chargingSchedule]
    }

    public func fetchEVTripSummary(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripSummary]? {
        var tripHeaders = authorizedHeaders(authToken: authToken, vehicle: vehicle)
        tripHeaders["userId"] = username
        tripHeaders["access_token"] = authToken.accessToken

        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/ac/v2/ts/alerts/maintenance/evTripDetails",
            method: .GET,
            headers: tripHeaders,
            requestType: .fetchEVTripSummary,
            vin: vehicle.vin
        )

        return try parseEVTripSummaryResponse(data)
    }
}
