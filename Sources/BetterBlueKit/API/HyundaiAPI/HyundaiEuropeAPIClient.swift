//
//  HyundaiEuropeAPIClient.swift
//  BetterBlueKit
//
//  Hyundai Europe API Client
//  Based on: https://github.com/andyfase/egmp-bluelink-scriptable
//

import CryptoKit
import Foundation

// MARK: - Hyundai Europe API Client

// swiftlint:disable type_body_length
@MainActor
public final class HyundaiEuropeAPIClient: APIClientBase, APIClientProtocol {

    // MARK: - Constants

    private static let apiDomain = "prd.eu-ccapi.hyundai.com"
    private static let apiPort = 8080
    private static let authHost = "eu-account.hyundai.com"
    private static let clientId = "6d477c38-3ca4-4cf3-9557-2a1929a94654"
    private static let authClientId = "64621b96-0f0d-11ec-82a8-0242ac130003"
    private static let appId = "014d2225-8495-4735-812d-2616334fd15d"
    private static let authCfb = "RFtoRq/vDXJmRndoZaZQyfOot7OrIqGVFj96iY2WL3yyH5Z/pUvlUhqmCxD2t+D65SQ="
    private static let authBasicCredentials = "6d477c38-3ca4-4cf3-9557-2a1929a94654:KUy49XxPzLpLuoK0xhBC77W6VXhmtQR9iQhmIFjjoY4IpxsV"

    private let deviceId = UUID().uuidString

    private var baseURL: String { "https://\(Self.apiDomain):\(Self.apiPort)" }
    private var authBaseURL: String { "https://\(Self.authHost)" }
    private var apiHost: String { "\(Self.apiDomain):\(Self.apiPort)" }

    public override var apiName: String { "HyundaiEurope" }

    // MARK: - Headers

    private func authorizedHeaders(authToken: AuthToken) -> [String: String] {
        [
            "Authorization": "Bearer \(authToken.accessToken)",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "okhttp/3.14.9",
            "ccsp-service-id": Self.clientId,
            "ccsp-application-id": Self.appId,
            "ccsp-device-id": deviceId,
            "Host": apiHost,
            "Connection": "Keep-Alive",
            "Accept-Encoding": "gzip",
            "Stamp": generateStamp()
        ]
    }

    private func generateStamp() -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let message = "\(Self.appId):\(timestamp)"
        guard let cfbData = Data(base64Encoded: Self.authCfb) else { return message }
        let key = SymmetricKey(data: cfbData.prefix(32))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(signature).base64EncodedString()
    }

    // MARK: - Login (OAuth2 Flow)

    public func login() async throws -> AuthToken {
        BBLogger.info(.auth, "HyundaiEurope: Starting OAuth2 login flow")

        // Step 1: Get integration info
        let (intUserId, serviceId) = try await getIntegrationInfo()

        // Step 2: Initialize login and get session cookies
        let (cookies, actionUrl) = try await initializeLogin(intUserId: intUserId, serviceId: serviceId)

        // Step 3: Submit credentials
        let authCode = try await submitCredentials(actionUrl: actionUrl, cookies: cookies)

        // Step 4: Exchange auth code for tokens
        let token = try await exchangeCodeForToken(authCode: authCode)

        BBLogger.info(.auth, "HyundaiEurope: Login completed successfully")
        return token
    }

    private func getIntegrationInfo() async throws -> (String, String) {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/user/integrationinfo")!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("okhttp/3.14.9", forHTTPHeaderField: "User-Agent")
        request.setValue(Self.clientId, forHTTPHeaderField: "ccsp-service-id")
        request.setValue(Self.appId, forHTTPHeaderField: "ccsp-application-id")
        request.setValue(deviceId, forHTTPHeaderField: "ccsp-device-id")
        request.setValue(apiHost, forHTTPHeaderField: "Host")
        request.setValue(generateStamp(), forHTTPHeaderField: "Stamp")

        let (data, _) = try await urlSession.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let intUserId = json["userId"] as? String,
              let serviceId = json["serviceId"] as? String else {
            throw APIError(message: "Failed to parse integration info", apiName: apiName)
        }

        return (intUserId, serviceId)
    }

    private func initializeLogin(intUserId: String, serviceId: String) async throws -> ([HTTPCookie], String) {
        var components = URLComponents(string: "\(authBaseURL)/auth/realms/euhyundaiidm/protocol/openid-connect/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.authClientId),
            URLQueryItem(name: "scope", value: "openid profile email phone"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "hkid_session_reset", value: "true"),
            URLQueryItem(name: "redirect_uri", value: "\(baseURL)/api/v1/user/integration/redirect/login"),
            URLQueryItem(name: "ui_locales", value: "en"),
            URLQueryItem(name: "state", value: serviceId),
            URLQueryItem(name: "intUserId", value: intUserId)
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        let session = URLSession(configuration: config)

        var currentRequest = request
        var cookies: [HTTPCookie] = []
        var actionUrl: String?

        for _ in 0..<10 {
            let (data, response) = try await session.data(for: currentRequest)

            if let httpResponse = response as? HTTPURLResponse {
                if let url = httpResponse.url,
                   let headerFields = httpResponse.allHeaderFields as? [String: String] {
                    cookies.append(contentsOf: HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url))
                }

                if (300..<400).contains(httpResponse.statusCode),
                   let location = httpResponse.value(forHTTPHeaderField: "Location"),
                   let redirectUrl = URL(string: location, relativeTo: currentRequest.url) {
                    currentRequest = URLRequest(url: redirectUrl)
                    currentRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                    continue
                }

                if let html = String(data: data, encoding: .utf8) {
                    actionUrl = extractFormActionURL(from: html, baseURL: currentRequest.url)
                }
            }
            break
        }

        guard let formActionUrl = actionUrl else {
            throw APIError(message: "Failed to find login form action URL", apiName: apiName)
        }

        return (cookies, formActionUrl)
    }

    private func extractFormActionURL(from html: String, baseURL: URL?) -> String? {
        let pattern = #"<form[^>]*action=["\']([^"\']+)["\']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }

        let actionPath = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")

        if actionPath.hasPrefix("http") { return actionPath }
        if let base = baseURL { return URL(string: actionPath, relativeTo: base)?.absoluteString }
        return nil
    }

    private func submitCredentials(actionUrl: String, cookies: [HTTPCookie]) async throws -> String {
        guard let url = URL(string: actionUrl) else {
            throw APIError(message: "Invalid login form URL", apiName: apiName)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")

        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? password
        request.httpBody = "username=\(encodedUsername)&password=\(encodedPassword)&credentialId=".data(using: .utf8)

        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: config)

        var currentRequest = request

        for _ in 0..<10 {
            let (_, response) = try await session.data(for: currentRequest)

            if let httpResponse = response as? HTTPURLResponse {
                if let location = httpResponse.value(forHTTPHeaderField: "Location") {
                    if let redirectUrl = URL(string: location),
                       let components = URLComponents(url: redirectUrl, resolvingAgainstBaseURL: false),
                       let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                        return code
                    }

                    if let redirectUrl = URL(string: location, relativeTo: currentRequest.url) {
                        currentRequest = URLRequest(url: redirectUrl)
                        currentRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                        continue
                    }
                }

                if httpResponse.statusCode == 200 {
                    throw APIError.invalidCredentials("Login failed - check username and password", apiName: apiName)
                }
            }
            break
        }

        throw APIError(message: "Failed to get authorization code", apiName: apiName)
    }

    private func exchangeCodeForToken(authCode: String) async throws -> AuthToken {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/user/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(Data(Self.authBasicCredentials.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")

        let redirectUri = "\(baseURL)/api/v1/user/integration/redirect/login"
        request.httpBody = "grant_type=authorization_code&code=\(authCode)&redirect_uri=\(redirectUri)".data(using: .utf8)

        let (data, _) = try await urlSession.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw APIError(message: "Failed to parse token response", apiName: apiName)
        }

        return AuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            pin: pin
        )
    }

    // MARK: - Vehicles

    public func fetchVehicles(authToken: AuthToken) async throws -> [Vehicle] {
        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/api/v1/spa/vehicles",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken),
            requestType: .fetchVehicles
        )

        return try parseVehiclesResponse(data)
    }

    // MARK: - Vehicle Status

    public func fetchVehicleStatus(for vehicle: Vehicle, authToken: AuthToken) async throws -> VehicleStatus {
        let (data, _, _) = try await performJSONRequest(
            url: "\(baseURL)/api/v1/spa/vehicles/\(vehicle.regId)/ccs2/carstatus/latest",
            method: .GET,
            headers: authorizedHeaders(authToken: authToken),
            requestType: .fetchVehicleStatus
        )

        return try parseVehicleStatusResponse(data, for: vehicle)
    }

    // MARK: - Commands

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        let (path, body) = commandPathAndBody(for: command)
        let url = "\(baseURL)/api/v2/spa/vehicles/\(vehicle.regId)/\(path)"

        _ = try await performJSONRequest(
            url: url,
            method: .POST,
            headers: authorizedHeaders(authToken: authToken),
            body: body,
            requestType: .sendCommand
        )
    }

    private func commandPathAndBody(for command: VehicleCommand) -> (String, [String: Any]) {
        switch command {
        case .lock:
            return ("ccs2/control/door", ["command": "close"])
        case .unlock:
            return ("ccs2/control/door", ["command": "open"])
        case .startClimate(let options):
            let tempCelsius = options.temperature.units == .celsius
                ? options.temperature.value
                : (options.temperature.value - 32.0) * 5.0 / 9.0
            return ("ccs2/control/temperature", [
                "command": "start",
                "hvacInfo": [
                    "airCtrl": options.climate ? 1 : 0,
                    "defrost": options.defrost,
                    "heating1": options.heatValue,
                    "airTemp": ["value": String(format: "%.1f", tempCelsius), "unit": 0]
                ]
            ])
        case .stopClimate:
            return ("ccs2/control/temperature", ["command": "stop"])
        case .startCharge:
            return ("ccs2/control/charge", ["command": "start"])
        case .stopCharge:
            return ("ccs2/control/charge", ["command": "stop"])
        case .setTargetSOC(let acLevel, let dcLevel):
            return ("charge/target", [
                "targetSOClist": [
                    ["targetSOClevel": acLevel, "plugType": 0],
                    ["targetSOClevel": dcLevel, "plugType": 1]
                ]
            ])
        }
    }
}

// MARK: - Response Parsing

extension HyundaiEuropeAPIClient {

    private func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resMsg = json["resMsg"] as? [String: Any],
              let vehicleArray = resMsg["vehicles"] as? [[String: Any]] else {
            throw APIError.logError("Invalid vehicles response", apiName: apiName)
        }

        return vehicleArray.compactMap { vehicleData -> Vehicle? in
            guard let vehicleId = vehicleData["vehicleId"] as? String,
                  let vin = vehicleData["vin"] as? String,
                  let nickname = vehicleData["nickname"] as? String ?? vehicleData["vehicleName"] as? String else {
                return nil
            }

            let fuelKindCode = vehicleData["fuelKindCode"] as? String ?? ""
            let isElectric = fuelKindCode == "E" || fuelKindCode == "EV"
            let masterInfo = vehicleData["master"] as? [String: Any] ?? [:]
            let generation = masterInfo["carGeneration"] as? Int ?? 2

            return Vehicle(
                vin: vin,
                regId: vehicleId,
                model: nickname,
                accountId: accountId,
                isElectric: isElectric,
                generation: generation,
                odometer: Distance(length: 0, units: .kilometers)
            )
        }
    }

    private func parseVehicleStatusResponse(_ data: Data, for vehicle: Vehicle) throws -> VehicleStatus {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resMsg = json["resMsg"] as? [String: Any] else {
            throw APIError.logError("Invalid status response", apiName: apiName)
        }

        let state = resMsg["state"] as? [String: Any] ?? [:]
        let vehicleState = state["Vehicle"] as? [String: Any] ?? [:]
        let green = vehicleState["Green"] as? [String: Any] ?? [:]
        let drivetrain = green["Drivetrain"] as? [String: Any] ?? [:]
        let evInfo = drivetrain["BatteryManagement"] as? [String: Any] ?? [:]

        let chassis = vehicleState["Chassis"] as? [String: Any] ?? [:]
        let doorLockState = chassis["DoorLock"] as? [String: Any] ?? [:]
        let isLocked = (doorLockState["DoorLockStatus"] as? String ?? "").lowercased() == "locked"

        let hvac = vehicleState["HVAC"] as? [String: Any] ?? [:]
        let airConOn = hvac["AirConOn"] as? Bool ?? false
        let targetTemp = hvac["TargetTemperature"] as? Double ?? 20.0

        var evStatus: VehicleStatus.EVStatus?
        if vehicle.isElectric {
            let batterySOC = evInfo["BatterySOC"] as? Double ?? 0
            let chargingStatus = evInfo["ChargingStatus"] as? String ?? ""
            let isCharging = chargingStatus.lowercased().contains("charging")
            let pluggedIn = evInfo["PluggedIn"] as? Bool ?? false
            let estimatedRange = evInfo["EstimatedRange"] as? Double ?? 0

            evStatus = VehicleStatus.EVStatus(
                charging: isCharging,
                chargeSpeed: 0,
                evRange: VehicleStatus.FuelRange(
                    range: Distance(length: estimatedRange, units: .kilometers),
                    percentage: batterySOC
                ),
                plugType: pluggedIn ? .acCharger : .unplugged,
                chargeTime: .seconds(0),
                targetSocAC: nil,
                targetSocDC: nil
            )
        }

        let location = resMsg["coord"] as? [String: Any] ?? [:]
        let syncDate = (resMsg["lastUpdateTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }

        return VehicleStatus(
            vin: vehicle.vin,
            gasRange: nil,
            evStatus: evStatus,
            location: VehicleStatus.Location(
                latitude: location["lat"] as? Double ?? 0,
                longitude: location["lon"] as? Double ?? 0
            ),
            lockStatus: VehicleStatus.LockStatus(locked: isLocked),
            climateStatus: VehicleStatus.ClimateStatus(
                defrostOn: false,
                airControlOn: airConOn,
                steeringWheelHeatingOn: false,
                temperature: Temperature(value: targetTemp, units: .celsius)
            ),
            odometer: vehicle.odometer,
            syncDate: syncDate,
            battery12V: nil,
            doorOpen: nil,
            trunkOpen: nil,
            hoodOpen: nil,
            tirePressureWarning: nil
        )
    }
}
// swiftlint:enable type_body_length
