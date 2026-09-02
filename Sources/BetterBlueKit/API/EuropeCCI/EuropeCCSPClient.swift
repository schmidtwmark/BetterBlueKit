//
//  EuropeCCSPClient.swift
//  BetterBlueKit
//
//  The shared client flows for the European CCSP backends. Hyundai EU and
//  Kia EU are the same platform behind different hosts and OAuth clients —
//  hyundai_kia_connect_api serves both brands from a single implementation,
//  and before this file existed the two Swift clients were line-for-line
//  clones that had to be fixed in pairs (the PIN/control-token logging fix
//  landed twice; the 2026-08 WAF response landed twice). Everything that
//  varies per brand rides in `EuropeCCSPBrandSpec`; everything that doesn't
//  lives here once.
//

import Foundation

// MARK: - Brand spec

/// Brand-varying constants for the shared EU CCSP flows.
struct EuropeCCSPBrandSpec {
    /// Legacy `ccsp-service-id` OAuth client (pre-CCI refresh grant + headers).
    let clientId: String
    let clientSecret: String
    /// `ccsp-application-id` header value and stamp message prefix.
    let appId: String
    /// Base64 XOR pad for `generateStamp()`.
    let authCfb: String
    /// `pushType` sent during device registration.
    let pushType: String
    /// OneApp/CCI login parameters.
    let cciConfig: EuropeCCIConfig
}

// MARK: - Protocol

/// A European CCSP client: supplies the brand constants and response
/// parsers; inherits every shared flow (login ladder, device registration,
/// status fetch, command routing) from the extension below.
@MainActor
protocol EuropeCCSPClient: APIClientBase {
    var euBrandSpec: EuropeCCSPBrandSpec { get }
    var baseURL: String { get }
    var authBaseURL: String { get }
    var apiHost: String { get }
    var commandToken: String { get set }
    var commandTokenExpiration: Date { get set }

    func parseVehiclesResponse(_ data: Data) throws -> [Vehicle]
    func parseVehicleStatusResponse(_ data: Data, _ parkData: Data?, for vehicle: Vehicle) throws -> VehicleStatus
}

// MARK: - Shared flows

extension EuropeCCSPClient {

    /// How long to wait after waking a CCS2 car before reading `/latest`,
    /// in nanoseconds. 25s matches hyundai_kia_connect_api's sleep in
    /// `_force_refresh_vehicle_state_ccs2`.
    var ccs2ForceRefreshDelay: UInt64 { 25 * 1_000_000_000 }

    // MARK: Headers

    func authorizedHeaders(authToken: AuthToken, ccs2: Bool = false) -> [String: String] {
        [
            "Authorization": "Bearer \(authToken.accessToken)",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "okhttp/3.14.9",
            "ccsp-service-id": euBrandSpec.clientId,
            "ccsp-application-id": euBrandSpec.appId,
            "ccsp-device-id": configuration.deviceId ?? "",
            "Ccuccs2protocolsupport": ccs2 ? "1" : "0",
            "Host": apiHost,
            "Connection": "Keep-Alive",
            "Accept-Encoding": "gzip",
            // Fresh stamp per request — the server validates the embedded
            // timestamp window (see `generateStamp()`).
            "Stamp": generateStamp()
        ]
    }

    func commandHeaders(authToken: AuthToken, ccs2: Bool = false) -> [String: String] {
        var result = authorizedHeaders(authToken: authToken, ccs2: ccs2)
        result["Authorization"] = "Bearer \(commandToken)"
        result["AuthorizationCCSP"] = "Bearer \(commandToken)"
        return result
    }

    /// CCSP `Stamp`: base64 of `authCfb ⊕ "<appId>:<unixSeconds>"`, where the
    /// XOR runs over the shorter of the two byte strings (the message here).
    ///
    /// Ports the canonical scheme from Home Assistant's
    /// `hyundai_kia_connect_api` (`_get_stamp`) / bluelinky. The previous
    /// HMAC-SHA256-over-ISO8601 form was accepted on read endpoints but
    /// rejected with HTTP 403 on the control endpoints, so remote actions
    /// failed across Europe.
    func generateStamp() -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let message = Array("\(euBrandSpec.appId):\(timestamp)".utf8)
        guard let cfbData = Data(base64Encoded: euBrandSpec.authCfb) else {
            return Data(message).base64EncodedString()
        }
        let cfb = Array(cfbData)
        let count = min(cfb.count, message.count)
        var xored = [UInt8]()
        xored.reserveCapacity(count)
        for index in 0 ..< count {
            xored.append(cfb[index] ^ message[index])
        }
        return Data(xored).base64EncodedString()
    }

    // MARK: Login (CCI token set, legacy refresh token, or password)

    public func login() async throws -> AuthToken {
        if let stored = configuration.refreshToken,
           let set = CCITokenSet.decodeFromStorage(stored) {
            BBLogger.info(.auth, "\(apiName): Starting login flow (CCI token refresh)")
            do {
                let token = try await cciRefreshLogin(config: euBrandSpec.cciConfig, set: set)
                // The refresh rotates the CCI set. A long-lived client
                // instance must present the rotated set on its next
                // refresh, not the one it just spent — the host's
                // persistence gets the same value via the returned
                // AuthToken.
                configuration = configuration.with(refreshToken: token.refreshToken)
                BBLogger.info(.auth, "\(apiName): Login completed successfully")
                return token
            } catch {
                guard !password.isEmpty else { throw error }
                BBLogger.info(.auth, "\(apiName): CCI refresh failed, falling back to password login")
                configuration = configuration.with(refreshToken: "")
            }
        } else if let refreshToken = configuration.refreshToken, !refreshToken.isEmpty {
            // Pre-CCI refresh token — the legacy oauth2/token refresh grant
            // still works for these, so don't force a fresh password login.
            BBLogger.info(.auth, "\(apiName): Starting login flow (legacy refresh token)")
            do {
                let token = try await legacyRefreshGrant()
                // The IDP may rotate the refresh token on this grant —
                // keep the configuration on the fresh one.
                configuration = configuration.with(refreshToken: token.refreshToken)
                BBLogger.info(.auth, "\(apiName): Login completed successfully")
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
        BBLogger.info(.auth, "\(apiName): using username/password login (OneApp/CCI)")
        let token = try await cciPasswordLogin(config: euBrandSpec.cciConfig)
        configuration = configuration.with(refreshToken: token.refreshToken)
        BBLogger.info(.auth, "\(apiName): Login completed successfully")
        return token
    }

    /// Legacy refresh grant: trade the stored refresh_token for a fresh
    /// access token. Form-encoded, no `redirect_uri` — matching upstream.
    private func legacyRefreshGrant() async throws -> AuthToken {
        let fields: [(String, String)] = [
            ("grant_type", "refresh_token"),
            ("refresh_token", configuration.refreshToken ?? ""),
            ("client_id", euBrandSpec.clientId),
            ("client_secret", euBrandSpec.clientSecret)
        ]
        var request = URLRequest(url: URL(string: "\(authBaseURL)/auth/api/v2/user/oauth2/token")!)
        request.httpMethod = "POST"
        // The Cloudflare-clearing identity — idpconnect sits behind the
        // same WAF as the signin endpoints.
        request.setValue(APIClientBase.euMobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)
        do {
            let (data, _) = try await performLoggedRequest(request, requestType: .login)
            return try parseLegacyAuthToken(from: data)
        } catch let error as APIError where error.code == 400 {
            // OAuth `invalid_grant` arrives as a plain HTTP 400 with no
            // CCSP envelope. Surface it as a credential failure so the
            // login ladder clears the dead token and falls back to a
            // password login instead of erroring forever.
            throw APIError.invalidCredentials(
                "Refresh token rejected (HTTP 400) — a fresh sign-in is required.",
                apiName: apiName
            )
        }
    }

    /// Parse an `oauth2/token` response. Adopts a rotated `refresh_token`
    /// whenever the IDP sends one (upstream does) — re-presenting the old
    /// token after a rotation would be a dead credential — and falls back
    /// to the stored token when the response omits it (refresh grants
    /// often do).
    func parseLegacyAuthToken(from data: Data) throws -> AuthToken {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw APIError(
                message: "Failed to parse AuthToken response",
                apiName: apiName,
                errorType: .invalidCredentials
            )
        }
        let refreshToken: String =
            json["refresh_token"] as? String ?? configuration.refreshToken ?? ""
        return AuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    // MARK: Device registration

    func euRegisterDevice() async throws -> String? {
        let body = [
            // A fresh random push handle per registration, matching
            // upstream's 64-hex `pushRegId`.
            "pushRegId": APIClientBase.randomPushRegId(),
            "pushType": euBrandSpec.pushType,
            "uuid": UUID().uuidString
        ]

        let headers = [
            "ccsp-service-id": euBrandSpec.clientId,
            "ccsp-application-id": euBrandSpec.appId,
            "Stamp": generateStamp(),
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

    // MARK: Vehicles

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

    /// Fuel-kind code from the EU vehicle list: "GN"/"EV"/"PHEV"/"HV"/"PE"
    /// (per hyundai_kia_connect_api). Plain hybrids fall to .gas since the
    /// model has no HEV case.
    static func parseEuropeFuelType(_ code: String) -> FuelType {
        switch code {
        case "E", "EV": .electric
        case "P", "PE", "PHEV": .phev
        default: .gas
        }
    }

    // MARK: Vehicle status

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

        // The `/latest` endpoint is a passive cache — it won't reflect a
        // just-sent command until the car next reports in on its own. A
        // manual / post-command refresh (`cached == false`) therefore has
        // to wake the car first. Mirrors hyundai_kia_connect_api's
        // force_refresh_vehicle_state: the CCS2 wake is async (ack + wait),
        // the legacy `GET /status` is synchronous.
        if !cached {
            if ccs2 {
                // Errors propagate on purpose: a failed CCS2 wake means
                // `/latest` is definitely stale, and applying a stale
                // snapshot after a command misreports the command result.
                try await forceRefreshCCS2(for: vehicle, authToken: authToken)
            } else {
                // Best-effort: upstream parses this response body directly,
                // but our parser is built for the `/latest` envelope, so the
                // wake's job here is only refreshing the server cache. A
                // slow modem (the synchronous poll can outlive URLSession's
                // timeout) or a transient failure must not take down the
                // whole refresh — legacy cars never had a wake before this
                // and hosts re-poll via the status-waiting pattern anyway.
                do {
                    _ = try await performJSONRequest(
                        url: "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)/status",
                        method: .GET,
                        headers: authorizedHeaders(authToken: authToken, ccs2: false),
                        requestType: .fetchVehicleStatus,
                        vin: vehicle.vin
                    )
                } catch {
                    BBLogger.debug(.api, "\(apiName): legacy wake GET /status failed: \(error)")
                }
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
        // `/latest`.
        try await Task.sleep(nanoseconds: ccs2ForceRefreshDelay)
    }

    // MARK: Command token (PIN exchange)

    private func setCommandToken(authToken: AuthToken) async throws {
        // controlTokens expire after `expiresTime` seconds; refresh ~5 min early.
        if Date() < commandTokenExpiration.addingTimeInterval(-300) && !commandToken.isEmpty {
            return
        }

        let body = ["deviceId": configuration.deviceId ?? "", "pin": pin]

        // Routed through performJSONRequest so the PIN/control-token
        // request is captured in the HTTP logs and its CCSP envelope is
        // decoded — a raw URLSession call surfaced every failure as a
        // generic "check PIN" message.
        let (_, json, _) = try await performJSONRequest(
            url: "\(baseURL)/api/v1/user/pin?token=",
            method: .PUT,
            headers: authorizedHeaders(authToken: authToken),
            body: body,
            requestType: .sendCommand
        )

        guard let token = json["controlToken"] as? String,
              let expires = json["expiresTime"] as? Int else {
            throw APIError(
                message: "PIN verification failed — check that the account PIN is correct.",
                apiName: apiName
            )
        }

        commandToken = token
        commandTokenExpiration = Date().addingTimeInterval(TimeInterval(expires))
    }

    // MARK: Commands

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        try await withDeviceIdRecovery {
            try await sendCommandOnce(for: vehicle, command: command, authToken: authToken)
        }
    }

    private func sendCommandOnce(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken
    ) async throws {
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

        // CCS2 (Gen5W) cars authenticate commands with a PIN-derived
        // control token; legacy cars use the normal access token and
        // have no PIN step at all.
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
}
