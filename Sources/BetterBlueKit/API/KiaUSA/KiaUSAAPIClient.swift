//
//  KiaUSAAPIClient.swift
//  BetterBlueKit
//
//  Kia USA API Client
//

import CryptoKit
import Foundation

// MARK: - Kia USA API Client

@MainActor
public final class KiaUSAAPIClient: APIClientBase, APIClientProtocol {

    // MARK: - Constants

    var baseURL: String {
        region.apiBaseURL(for: .kia)
    }

    var apiURL: String {
        "\(baseURL)/apigw/v1/"
    }

    // Device ID is a simple uppercase UUID (matches Python: str(uuid.uuid4()).upper())
    // Use persisted device ID from configuration if available, so the server recognizes
    // the same device across re-authentications and the rmToken remains valid.
    let deviceId: String

    // Client UUID is a UUID5 hash of device_id using DNS namespace
    var clientUUID: String {
        let namespaceUUID = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        return generateUUID5(namespace: namespaceUUID, name: deviceId).uuidString.lowercased()
    }

    public override init(configuration: APIClientConfiguration, urlSession: URLSession = .shared) {
        self.deviceId = configuration.deviceId ?? UUID().uuidString.uppercased()
        super.init(configuration: configuration, urlSession: urlSession)
    }

    public override var apiName: String { "KiaUSA" }

    // MARK: - Headers

    func headers() -> [String: String] {
        let offset = TimeZone.current.secondsFromGMT() / 3600
        let hostName = baseURL.replacingOccurrences(of: "https://", with: "")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "GMT")
        let dateString = dateFormatter.string(from: Date())

        return [
            "content-type": "application/json;charset=utf-8",
            "accept": "application/json",
            "accept-encoding": "gzip, deflate, br",
            "accept-language": "en-US,en;q=0.9",
            "accept-charset": "utf-8",
            "apptype": "L",
            "appversion": "7.22.0",
            "clientid": "SPACL716-APL",
            "clientuuid": clientUUID,
            "from": "SPA",
            "host": hostName,
            "language": "0",
            "offset": String(offset),
            "ostype": "iOS",
            "osversion": "15.8.5",
            "phonebrand": "iPhone",
            "secretkey": "sydnat-9kykci-Kuhtep-h5nK",
            "to": "APIGW",
            "tokentype": "A",
            "user-agent": "KIAPrimo_iOS/37 CFNetwork/1335.0.3.4 Darwin/21.6.0",
            "date": dateString,
            "deviceid": deviceId
        ]
    }

    func authorizedHeaders(authToken: AuthToken, vehicleKey: String? = nil) -> [String: String] {
        var result = headers()
        result["sid"] = authToken.accessToken
        if let key = vehicleKey {
            result["vinkey"] = key
        }
        return result
    }

    // MARK: - APIClientProtocol Implementation

    public func supportsMFA() -> Bool {
        true
    }

    public func login() async throws -> AuthToken {
        try await loginWithMFA(sid: nil, rmToken: configuration.rememberMeToken)
    }

    func loginWithMFA(sid: String?, rmToken: String?) async throws -> AuthToken {
        BBLogger.info(.auth, "KiaUSA: Attempting login for \(username)")

        var loginHeaders = headers()
        if let token = rmToken {
            loginHeaders["rmtoken"] = token
        }
        if let sid {
            loginHeaders["sid"] = sid
        }

        let loginData: [String: Any] = [
            "deviceKey": deviceId,
            "deviceType": 2,
            "tncFlag": 1,
            "userCredential": [
                "userId": username,
                "password": password
            ]
        ]

        let (data, _, response) = try await performJSONRequest(
            url: "\(apiURL)prof/authUser",
            method: .POST,
            headers: loginHeaders,
            body: loginData,
            requestType: .login
        )

        return try parseLoginResponse(data, headers: extractResponseHeaders(from: response))
    }

    public func sendMFACode(xid: String, otpKey: String, method: MFAMethod) async throws {
        BBLogger.info(.mfa, "KiaUSA: Sending OTP via \(method)")

        var otpHeaders = headers()
        otpHeaders["otpkey"] = otpKey
        otpHeaders["notifytype"] = method == .email ? "EMAIL" : "SMS"
        otpHeaders["xid"] = xid

        let (data, _, _) = try await performJSONRequest(
            url: "\(apiURL)cmm/sendOTP",
            method: .POST,
            headers: otpHeaders,
            body: [:],
            requestType: .sendMFA
        )

        try checkForKiaErrors(data: data)
        BBLogger.info(.mfa, "KiaUSA: OTP sent successfully")
    }

    public func verifyMFACode(
        xid: String,
        otpKey: String,
        code: String
    ) async throws -> (rememberMeToken: String, sid: String) {
        BBLogger.info(.mfa, "KiaUSA: Verifying OTP")

        var verifyHeaders = headers()
        verifyHeaders["otpkey"] = otpKey
        verifyHeaders["xid"] = xid

        let (data, _, response) = try await performJSONRequest(
            url: "\(apiURL)cmm/verifyOTP",
            method: .POST,
            headers: verifyHeaders,
            body: ["otp": code],
            requestType: .verifyMFA
        )

        try checkForKiaErrors(data: data)

        let responseHeaders = extractResponseHeaders(from: response)
        guard let rmToken = responseHeaders["rmToken"] ?? responseHeaders["rmtoken"] ?? responseHeaders["RmToken"],
              let sessionId = responseHeaders["sid"] ?? responseHeaders["Sid"] ?? responseHeaders["SID"] else {
            BBLogger.warning(.mfa, "KiaUSA verifyOTP response headers: \(responseHeaders)")
            throw APIError.logError("Verify OTP response missing tokens", apiName: apiName)
        }

        BBLogger.info(.mfa, "KiaUSA OTP verified - rmToken: \(rmToken.prefix(10))..., sid: \(sessionId)")
        return (rmToken, sessionId)
    }

    public func completeMFALogin(sid: String, rmToken: String) async throws -> AuthToken {
        BBLogger.info(.auth, "KiaUSA: Completing MFA login")
        return try await loginWithMFA(sid: sid, rmToken: rmToken)
    }

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        let (data, _, _) = try await performJSONRequest(
            url: "\(apiURL)ownr/gvl",
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
        let vehicleKeyLog = vehicle.vehicleKey ?? "nil"
        BBLogger.debug(
            .api,
            "KiaUSA: Fetching status for VIN: \(vehicle.vin), vehicleKey: \(vehicleKeyLog), cached: \(cached)"
        )

        // When the caller asks for a real-time reading, hit `rems/rvs` first
        // to make Kia's backend poll the vehicle modem (same endpoint the
        // Kia Access app's pull-to-refresh uses). It's an async server call
        // that blocks until the vehicle responds (20–60 s typical). After
        // it returns we fall through to `cmm/gvi`, which now returns the
        // freshly-refreshed cached snapshot. If the real-time call fails
        // we log and continue — a stale snapshot beats surfacing an error.
        if !cached {
            try await triggerRealTimeStatusRefresh(for: vehicle, authToken: authToken)
        }

        // `cmm/gvi` only accepts `vehicleStatus: "1"`. Sending anything else
        // returns the server-side 9001 "Incorrect request payload format".
        let body: [String: Any] = [
            "vehicleConfigReq": [
                "airTempRange": "0",
                "maintenance": "1",
                "seatHeatCoolOption": "0",
                "vehicle": "1",
                "vehicleFeature": "0"
            ],
            "vehicleInfoReq": [
                "drivingActivty": "0",
                "dtc": "1",
                "enrollment": "1",
                "functionalCards": "0",
                "location": "1",
                "vehicleStatus": "1",
                "weather": "0"
            ],
            "vinKey": [vehicle.vehicleKey ?? ""]
        ]

        let (data, _, _) = try await performJSONRequest(
            url: "\(apiURL)cmm/gvi",
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicleKey: vehicle.vehicleKey),
            body: body,
            requestType: .fetchVehicleStatus,
            vin: vehicle.vin
        )

        return try parseVehicleStatusResponse(data, for: vehicle)
    }

    /// Asks Kia's backend to poll the vehicle's telematics modem for fresh
    /// data. The response comes back once the modem replies — usually within
    /// ~30 seconds. Errors are logged but swallowed so the caller still gets
    /// a (possibly stale) snapshot from the follow-up `cmm/gvi` call.
    private func triggerRealTimeStatusRefresh(
        for vehicle: Vehicle,
        authToken: AuthToken
    ) async throws {
        BBLogger.info(.api, "KiaUSA: Requesting real-time status refresh for VIN \(vehicle.vin)")

        do {
            let (data, _, _) = try await performJSONRequest(
                url: "\(apiURL)rems/rvs",
                method: .POST,
                headers: authorizedHeaders(authToken: authToken, vehicleKey: vehicle.vehicleKey),
                body: ["requestType": 0],
                requestType: .fetchVehicleStatus,
                vin: vehicle.vin
            )
            try checkForKiaErrors(data: data)
        } catch let error as APIError where error.errorType == .invalidCredentials {
            // Bubble auth failures up — the caller (BBAccount) knows how to
            // re-authenticate. Swallowing would mask a session that really
            // needs refreshing.
            throw error
        } catch {
            // Swallow everything else: the user-visible UX is "refresh took
            // a while and maybe the data is 30 s stale", not a failure.
            BBLogger.warning(.api, "KiaUSA: rems/rvs real-time refresh failed, falling back to cached: \(error)")
        }
    }

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        let url = commandURL(for: command)
        let body = commandBody(for: command, vehicle: vehicle)
        let method = commandMethod(for: command)

        let (data, _, _) = try await performJSONRequest(
            url: url,
            method: method,
            headers: authorizedHeaders(authToken: authToken, vehicleKey: vehicle.vehicleKey),
            body: method == .GET ? nil : body,
            requestType: .sendCommand,
            vin: vehicle.vin
        )

        try checkForKiaErrors(data: data)
    }

    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        // Kia USA doesn't support EV trip details
        nil
    }

    // MARK: - UUID5 Generation

    func generateUUID5(namespace: UUID, name: String) -> UUID {
        let nsUUID = namespace.uuid
        var data = Data([
            nsUUID.0, nsUUID.1, nsUUID.2, nsUUID.3,
            nsUUID.4, nsUUID.5, nsUUID.6, nsUUID.7,
            nsUUID.8, nsUUID.9, nsUUID.10, nsUUID.11,
            nsUUID.12, nsUUID.13, nsUUID.14, nsUUID.15
        ])
        data.append(contentsOf: name.utf8)

        let digest = Insecure.SHA1.hash(data: data)
        var hash = Array(digest)

        hash[6] = (hash[6] & 0x0F) | 0x50  // Version 5
        hash[8] = (hash[8] & 0x3F) | 0x80  // Variant

        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
    }
}
