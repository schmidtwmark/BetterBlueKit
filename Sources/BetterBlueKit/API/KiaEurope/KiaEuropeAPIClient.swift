//
//  KiaEuropeAPIClient.swift
//  BetterBlueKit
//
//  Kia Europe API Client
//  Based on KiaUvoApiEU from hyundai_kia_connect_api (PR #1123, v4.12.0)
//  which integrates a headless IDPConnect login flow and drops curl_cffi
//  by appending `_CCS_APP_AOS` to the User-Agent.
//

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
    /// How long to wait after waking a CCS2 car before reading `/latest`,
    /// in nanoseconds. 25s matches hyundai_kia_connect_api's sleep in
    /// `_force_refresh_vehicle_state_ccs2`.
    static let ccs2ForceRefreshDelay: UInt64 = 25 * 1_000_000_000

    /// The `_CCS_APP_AOS` suffix is what gets past Cloudflare on
    /// `idpconnect-eu.kia.com` — without it, the authorize endpoint
    /// returns 400. Discovered in hyundai_kia_connect_api PR #1123.
    static let mobileUserAgent =
        "Mozilla/5.0 (Linux; Android 4.1.1; Galaxy Nexus Build/JRO03C) " +
        "AppleWebKit/535.19 (KHTML, like Gecko) " +
        "Chrome/18.0.1025.166 Mobile Safari/535.19_CCS_APP_AOS"

    var commandToken: String = ""
    var commandTokenExpiration: Date = Date()

    var baseURL: String {
        region.apiBaseURL(for: .kia)
    }
    var authBaseURL: String { "https://idpconnect-eu.kia.com" }
    var apiHost = Brand.kiaBaseUrl(region: Region.europe).replacing(/https:\/\//, with: "")

    var oauthRedirectURI: String { "\(baseURL)/api/v1/user/oauth2/redirect" }

    public override var apiName: String { "KiaEurope" }

    // MARK: - Login

    public func login() async throws -> AuthToken {
        if let stored = configuration.refreshToken,
           let set = CCITokenSet.decodeFromStorage(stored) {
            BBLogger.info(.auth, "KiaEurope: Starting login flow (CCI token refresh)")
            do {
                return try await cciRefreshLogin(config: .kia, set: set)
            } catch {
                guard !password.isEmpty else { throw error }
                BBLogger.info(.auth, "KiaEurope: CCI refresh failed, falling back to password login")
                configuration = configuration.with(refreshToken: "")
            }
        } else if let refreshToken = configuration.refreshToken, !refreshToken.isEmpty {
            // Pre-CCI refresh token — the legacy oauth2/token refresh grant
            // still works for these, so don't force a fresh password login.
            BBLogger.info(.auth, "KiaEurope: Starting login flow (legacy refresh token)")
            do {
                let token = try await getAccessTokenFromRefreshToken()
                // The IDP may rotate the refresh token on this grant —
                // keep the configuration (and the host's persistence,
                // via the returned AuthToken) on the fresh one.
                configuration = configuration.with(refreshToken: token.refreshToken)
                BBLogger.info(.auth, "KiaEurope: Login completed successfully")
                return token
            } catch {
                guard let apiError = error as? APIError,
                      apiError.errorType == .invalidCredentials,
                      !password.isEmpty else { throw error }
                configuration = configuration.with(refreshToken: "")
            }
        }

        // Password login runs the OneApp/CCI flow — the legacy signin has
        // been WAF-blocked ("abusing request") since 2026-08-11.
        BBLogger.info(.auth, "KiaEurope: using username/password login (OneApp/CCI)")
        let token = try await cciPasswordLogin(config: .kia)
        configuration = configuration.with(refreshToken: token.refreshToken)
        BBLogger.info(.auth, "KiaEurope: Login completed successfully")
        return token
    }

    // Auth flow (signin / token exchange / refresh) lives in
    // KiaEuropeAPIClient+Auth.swift to keep this class file under
    // the type-body-length threshold and so the multi-step signin
    // can be split into focused helpers.

    // MARK: - Device registration

    public override func registerDevice() async throws -> String? {
        let stamp = generateStamp()
        let body = [
            // A fresh random push handle per registration, matching
            // upstream's 64-hex `pushRegId` (this used to send the Stamp,
            // which encodes the app id + timestamp instead).
            "pushRegId": Self.randomPushRegId(),
            "pushType": Self.pushType,
            "uuid": UUID().uuidString
        ]

        let headers = [
            "ccsp-service-id": Self.clientId,
            "ccsp-application-id": Self.appId,
            "Stamp": stamp,
            "Content-Type": "application/json;charset=UTF-8",
            "Host": apiHost,
            "Connection": "Keep-Alive",
            "Accept-Encoding": "gzip",
            "User-Agent": "okhttp/3.14.9"
        ]

        let (_, json, _) = try await performJSONRequest(
            url: "\(baseURL)/api/v1/spa/notifications/register",
            method: .POST,
            headers: headers,
            body: body,
            requestType: .login
        )
        guard let resMsg = json["resMsg"] as? [String: Any],
              let devId = resMsg["deviceId"] as? String else {
            throw APIError(message: "Failed to get device id", apiName: apiName)
        }
        configuration = configuration.with(deviceId: devId)
        return devId
    }

    // MARK: - Vehicles

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        try await withDeviceIdRecovery {
            let (data, _, _) = try await performJSONRequest(
                url: "\(baseURL)/api/v1/spa/vehicles",
                method: .GET,
                headers: authorizedHeaders(authToken: authToken),
                requestType: .fetchVehicles
            )
            return try parseVehiclesResponse(data)
        }
    }

    public func fetchVehicleStatus(
        for vehicle: Vehicle,
        authToken: AuthToken,
        cached: Bool
    ) async throws -> VehicleStatus {
        try await withDeviceIdRecovery {
            try await fetchVehicleStatusOnce(for: vehicle, authToken: authToken, cached: cached)
        }
    }

    private func fetchVehicleStatusOnce(
        for vehicle: Vehicle,
        authToken: AuthToken,
        cached: Bool
    ) async throws -> VehicleStatus {
        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false

        // A manual / post-command refresh (`cached == false`) must wake the
        // car — the `/latest` snapshot is a passive cache and won't reflect a
        // just-sent command until the vehicle reports in. Mirrors
        // hyundai_kia_connect_api's force_refresh_vehicle_state: the CCS2
        // wake is async (ack + wait), the legacy `GET /status` is
        // synchronous and refreshes the server cache before we read it.
        if !cached {
            if ccs2 {
                try await forceRefreshCCS2(for: vehicle, authToken: authToken)
            } else {
                _ = try await performJSONRequest(
                    url: "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)/status",
                    method: .GET,
                    headers: authorizedHeaders(authToken: authToken, ccs2: false),
                    requestType: .fetchVehicleStatus,
                    vin: vehicle.vin
                )
            }
        }

        let endpoint: String = ccs2 ? "/ccs2/carstatus/latest" : "/status/latest"

        let (statusData, _, _) = try await performJSONRequest(
            url: "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)\(endpoint)",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken, ccs2: ccs2),
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        )

        // `/location/park` frequently refuses with `5921 No Data Found`;
        // upstream swallows every error here, so a park failure must not
        // take down the whole status fetch — the parser falls back to
        // the location embedded in the status payload.
        let parkData = try? await performJSONRequest(
            url: "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)/location/park",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken, ccs2: ccs2),
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        ).0

        return try parseVehicleStatusResponse(statusData, parkData, for: vehicle)
    }

    // MARK: - Command token (PIN exchange)

    private func setCommandToken(authToken: AuthToken) async throws {
        // controlTokens expire after `expiresTime` seconds; refresh ~5 min early.
        if Date() < commandTokenExpiration.addingTimeInterval(-300) && !commandToken.isEmpty {
            return
        }

        let body = ["deviceId": configuration.deviceId ?? "", "pin": pin]

        // Route through performJSONRequest so the PIN/control-token
        // request is captured in the HTTP logs and its CCSP envelope is
        // decoded — a raw URLSession call surfaced every failure as the
        // generic "check PIN" message. (Hyundai's sibling was fixed the
        // same way earlier.)
        let (_, json, _) = try await performJSONRequest(
            url: "\(baseURL)/api/v1/user/pin?token=",
            method: .PUT,
            headers: authorizedHeaders(authToken: authToken),
            body: body,
            requestType: .sendCommand
        )

        guard let token = json["controlToken"] as? String,
              let expires = json["expiresTime"] as? Int else {
            throw APIError(message: "Failed to get command token (check PIN)", apiName: apiName)
        }

        commandToken = token
        commandTokenExpiration = Date().addingTimeInterval(TimeInterval(expires))
    }

    /// Wake a CCS2 vehicle so the subsequent `/latest` read returns current
    /// state. `GET /ccs2/carstatus` (no `/latest`) triggers the wake and
    /// returns an async ack envelope — its body is discarded, but errors
    /// propagate so we never fall through to applying a stale snapshot.
    /// Ports hyundai_kia_connect_api's `_force_refresh_vehicle_state_ccs2`.
    func forceRefreshCCS2(for vehicle: Vehicle, authToken: AuthToken) async throws {
        _ = try await performJSONRequest(
            url: "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)/ccs2/carstatus",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken, ccs2: true),
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        )
        // The car reports back asynchronously; give it time before reading
        // `/latest` (~20s live-measured on a reachable EU CCS2 car).
        try await Task.sleep(nanoseconds: Self.ccs2ForceRefreshDelay)
    }

    // MARK: - Commands

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        try await withDeviceIdRecovery {
            try await sendCommandOnce(for: vehicle, command: command, authToken: authToken)
        }
    }

    private func sendCommandOnce(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        let ccs2 = vehicle.marketOptions?.ccs2Supported ?? false
        // "R" only for the mile-based RHD markets (UK/Ireland); everything
        // else — including km-based continental EU — is "L". Mirrors
        // hyundai_kia_connect_api's `_get_drv_seat_loc`.
        let drvSeatLoc = vehicle.odometer.units == .miles ? "R" : "L"
        let (path, body) = commandPathAndBody(for: command, ccs2: ccs2, drvSeatLoc: drvSeatLoc)

        // `charge/target` is a v1 + access-token endpoint for every
        // vehicle — upstream never versions it or fetches a control
        // token for it, even on CCS2 cars.
        let isChargeTarget: Bool = {
            if case .setTargetSOC = command { return true }
            return false
        }()
        let url = "\(baseURL)/api/\(ccs2 && !isChargeTarget ? "v2" : "v1")"
            + "/spa/vehicles/\(vehicle.regId)/\(path)"
        let headers: [String: String]
        if ccs2 && !isChargeTarget {
            try await setCommandToken(authToken: authToken)
            headers = commandHeaders(authToken: authToken, ccs2: ccs2)
        } else {
            headers = authorizedHeaders(authToken: authToken, ccs2: ccs2)
        }

        _ = try await performJSONRequest(
            url: url,
            method: .POST,
            headers: headers,
            body: body,
            requestType: .sendCommand,
            vin: vehicle.vin
        )
    }

    public func fetchEVTripSummary(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripSummary]? {
        nil
    }
}
