//
//  KiaUSAAPIClient.swift
//  BetterBlueKit
//
//  Kia USA API Client
//

import CryptoKit
import Foundation

// MARK: - Kia USA API Client

// swiftlint:disable type_body_length file_length
@MainActor
public final class KiaUSAAPIClient: APIClientBase, APIClientProtocol {

    // MARK: - Constants

    private var baseURL: String {
        region.apiBaseURL(for: .kia)
    }

    private var apiURL: String {
        "\(baseURL)/apigw/v1/"
    }

    // Device ID is a simple uppercase UUID (matches Python: str(uuid.uuid4()).upper())
    private let deviceId: String = UUID().uuidString.uppercased()

    // Client UUID is a UUID5 hash of device_id using DNS namespace
    private var clientUUID: String {
        let namespaceUUID = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        return generateUUID5(namespace: namespaceUUID, name: deviceId).uuidString.lowercased()
    }

    public override var apiName: String { "KiaUSA" }

    // MARK: - Headers

    private func headers() -> [String: String] {
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

    private func authorizedHeaders(authToken: AuthToken, vehicleKey: String? = nil) -> [String: String] {
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

    private func loginWithMFA(sid: String?, rmToken: String?) async throws -> AuthToken {
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
              let sid = responseHeaders["sid"] ?? responseHeaders["Sid"] ?? responseHeaders["SID"] else {
            BBLogger.warning(.mfa, "KiaUSA verifyOTP response headers: \(responseHeaders)")
            throw APIError.logError("Verify OTP response missing tokens", apiName: apiName)
        }

        BBLogger.info(.mfa, "KiaUSA OTP verified - rmToken: \(rmToken.prefix(10))..., sid: \(sid)")
        return (rmToken, sid)
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

    public func fetchVehicleStatus(for vehicle: Vehicle, authToken: AuthToken) async throws -> VehicleStatus {
        BBLogger.debug(.api, "KiaUSA: Fetching status for VIN: \(vehicle.vin), vehicleKey: \(vehicle.vehicleKey ?? "nil")")

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
            requestType: .fetchVehicleStatus
        )

        return try parseVehicleStatusResponse(data, for: vehicle)
    }

    public func sendCommand(for vehicle: Vehicle, command: VehicleCommand, authToken: AuthToken) async throws {
        let url = commandURL(for: command)
        let body = commandBody(for: command, vehicle: vehicle)

        let (data, _, _) = try await performJSONRequest(
            url: url,
            method: .POST,
            headers: authorizedHeaders(authToken: authToken, vehicleKey: vehicle.vehicleKey),
            body: body,
            requestType: .sendCommand
        )

        try checkForKiaErrors(data: data)
    }

    public func fetchEVTripDetails(for vehicle: Vehicle, authToken: AuthToken) async throws -> [EVTripDetail]? {
        // Kia USA doesn't support EV trip details
        nil
    }

    // MARK: - Command Helpers

    private func commandURL(for command: VehicleCommand) -> String {
        let path: String = switch command {
        case .lock: "rems/door/lock"
        case .unlock: "rems/door/unlock"
        case .startClimate: "rems/start"
        case .stopClimate: "rems/stop"
        case .startCharge: "evc/charge"
        case .stopCharge: "evc/cancel"
        case .setTargetSOC: "evc/charge/targetsoc/set"
        }
        return "\(apiURL)\(path)"
    }

    private func commandBody(for command: VehicleCommand, vehicle: Vehicle) -> [String: Any] {
        switch command {
        case .startClimate(let options):
            let heatingAccessory: [String: Int] = [
                "steeringWheel": options.steeringWheel > 0 ? 1 : 0,
                "rearWindow": options.rearDefrostEnabled ? 1 : 0,
                "sideMirror": options.rearDefrostEnabled ? 1 : 0
            ]

            var remoteClimate: [String: Any] = [
                "airCtrl": options.climate,
                "defrost": options.defrost,
                "airTemp": [
                    "value": String(Int(options.temperature.value)),
                    "unit": options.temperature.units.integer()
                ],
                "ignitionOnDuration": [
                    "unit": 4,
                    "value": options.duration
                ],
                "heatingAccessory": heatingAccessory
            ]

            let seats: [String: Int] = [
                "driverSeat": convertSeatSetting(options.frontLeftSeat, options.frontLeftVentilationEnabled),
                "passengerSeat": convertSeatSetting(options.frontRightSeat, options.frontRightVentilationEnabled),
                "rearLeftSeat": convertSeatSetting(options.rearLeftSeat, options.rearLeftVentilationEnabled),
                "rearRightSeat": convertSeatSetting(options.rearRightSeat, options.rearRightVentilationEnabled)
            ]

            remoteClimate["heatVentSeat"] = seats
            return ["remoteClimate": remoteClimate]
        case .startCharge:
            return ["chargeRatio": 100]
        case .setTargetSOC(let acLevel, let dcLevel):
            return ["targetSOClist": [
                ["targetSOClevel": acLevel, "plugType": 0],
                ["targetSOClevel": dcLevel, "plugType": 1]
            ]]
        default:
            return [:]
        }
    }

    // MARK: - UUID5 Generation

    private func generateUUID5(namespace: UUID, name: String) -> UUID {
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

// MARK: - Response Parsing

extension KiaUSAAPIClient {

    private func parseLoginResponse(_ data: Data, headers: [String: String]) throws -> AuthToken {
        try checkForKiaErrors(data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            BBLogger.error(.auth, "KiaUSA: Failed to parse login response as JSON")
            throw APIError.logError("Failed to parse login response", apiName: apiName)
        }

        // Check for MFA requirement
        if let payload = json["payload"] as? [String: Any],
           let otpKey = payload["otpKey"] as? String {
            let xid = headers["xid"] ?? headers["Xid"] ?? headers["XID"] ?? ""
            let hasEmail = payload["hasEmail"] as? Bool ?? false
            let hasPhone = payload["hasPhone"] as? Bool ?? false
            let email = payload["email"] as? String
            let phone = payload["phone"] as? String
            let rmTokenExpired = payload["rmTokenExpired"] as? Bool ?? false

            var mfaLog = "MFA required - otpKey: \(otpKey), xid: \(xid)"
            mfaLog += " | Contact options - hasEmail: \(hasEmail), hasPhone: \(hasPhone)"
            if let email { mfaLog += " | Email: \(email)" }
            if let phone { mfaLog += " | Phone: \(phone)" }
            if rmTokenExpired { mfaLog += " | rmTokenExpired: true" }
            BBLogger.info(.mfa, mfaLog)

            throw APIError.requiresMFA(
                xid: xid,
                otpKey: otpKey,
                hasEmail: hasEmail,
                hasPhone: hasPhone,
                email: email,
                phone: phone,
                rmTokenExpired: rmTokenExpired,
                apiName: apiName
            )
        }

        let sid = headers["sid"] ?? headers["Sid"] ?? headers["SID"]
        guard let sessionId = sid else {
            throw APIError.logError("Login response missing session ID header", apiName: apiName)
        }

        let validUntil = Date().addingTimeInterval(3600)
        BBLogger.info(.auth, "KiaUSA: Authentication completed successfully for user \(username)")

        return AuthToken(
            accessToken: sessionId,
            refreshToken: sessionId,
            expiresAt: validUntil,
            pin: pin
        )
    }

    private func parseVehiclesResponse(_ data: Data) throws -> [Vehicle] {
        try checkForKiaErrors(data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let vehicleSummary = payload["vehicleSummary"] as? [[String: Any]] else {
            throw APIError.logError("Invalid vehicles response", apiName: apiName)
        }

        return vehicleSummary.compactMap { entry -> Vehicle? in
            guard let vin = entry["vin"] as? String,
                  let regId = entry["vehicleIdentifier"] as? String,
                  let nickname = entry["nickName"] as? String,
                  let vehicleKey = entry["vehicleKey"] as? String,
                  let generation = entry["genType"] as? String,
                  let fuelType: Int = extractNumber(from: entry["fuelType"]) else {
                return nil
            }

            let odometer = Distance(
                length: extractNumber(from: entry["mileage"]) ?? 0,
                units: .miles
            )

            return Vehicle(
                vin: vin,
                regId: regId,
                model: nickname,
                accountId: accountId,
                isElectric: fuelType != 3,
                generation: Int(generation) ?? 1,
                odometer: odometer,
                vehicleKey: vehicleKey
            )
        }
    }

    private func parseVehicleStatusResponse(_ data: Data, for vehicle: Vehicle) throws -> VehicleStatus {
        try checkForKiaErrors(data: data)
        let lastVehicleInfo = try extractLastVehicleInfo(from: data)
        let vehicleStatus = try extractVehicleStatus(from: lastVehicleInfo)
        let (trunkOpen, hoodOpen) = parseHoodTrunk(from: vehicleStatus)

        return VehicleStatus(
            vin: vehicle.vin,
            gasRange: parseGasRange(from: vehicleStatus),
            evStatus: parseEVStatus(from: vehicleStatus),
            location: parseLocation(from: lastVehicleInfo),
            lockStatus: VehicleStatus.LockStatus(locked: vehicleStatus["doorLock"] as? Bool),
            climateStatus: parseClimateStatus(from: vehicleStatus),
            odometer: vehicle.odometer,
            syncDate: parseSyncDate(from: vehicleStatus),
            battery12V: parseBattery12V(from: vehicleStatus),
            doorOpen: parseDoorOpen(from: vehicleStatus),
            trunkOpen: trunkOpen,
            hoodOpen: hoodOpen,
            tirePressureWarning: parseTirePressure(from: vehicleStatus)
        )
    }

    private func extractLastVehicleInfo(from data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let vehicleInfoList = payload["vehicleInfoList"] as? [[String: Any]],
              let vehicleInfo = vehicleInfoList.first,
              let lastVehicleInfo = vehicleInfo["lastVehicleInfo"] as? [String: Any] else {
            throw APIError.logError("Invalid vehicle status response", apiName: apiName)
        }
        return lastVehicleInfo
    }

    private func extractVehicleStatus(from lastVehicleInfo: [String: Any]) throws -> [String: Any] {
        guard let vehicleStatusRpt = lastVehicleInfo["vehicleStatusRpt"] as? [String: Any],
              let vehicleStatus = vehicleStatusRpt["vehicleStatus"] as? [String: Any] else {
            throw APIError.logError("Invalid vehicle status response", apiName: apiName)
        }
        return vehicleStatus
    }

    private func parseEVStatus(from vehicleStatus: [String: Any]) -> VehicleStatus.EVStatus? {
        let evStatusData = vehicleStatus["evStatus"] as? [String: Any] ?? [:]
        let batteryStatus: Double = extractNumber(from: evStatusData["batteryStatus"]) ?? 0
        guard batteryStatus > 0 else { return nil }

        let drvDistance = evStatusData["drvDistance"] as? [[String: Any]] ?? []
        let rangeInfo = drvDistance.first?["rangeByFuel"] as? [String: Any] ?? [:]
        let evModeRange = rangeInfo["evModeRange"] as? [String: Any] ?? [:]
        let chargeTimes = evStatusData["remainChargeTime"] as? [[String: Any]] ?? []
        let chargeTime: Int = extractNumber(from: chargeTimes.first?["value"]) ?? 0

        let evRange = Distance(
            length: extractNumber(from: evModeRange["value"]) ?? 0,
            units: Distance.Units(extractNumber(from: evModeRange["unit"]) ?? 3)
        )

        let batteryPlugin: Int = extractNumber(from: evStatusData["batteryPlugin"]) ?? 0

        let targetSOC = evStatusData["targetSOC"] as? [[String: Any]] ?? []
        var targetSocAC: Double?, targetSocDC: Double?
        for target in targetSOC {
            if let plugType = target["plugType"] as? Int, let soc = target["targetSOClevel"] as? Double {
                if plugType == 0 { targetSocAC = soc }
                else if plugType == 1 { targetSocDC = soc }
            }
        }

        return VehicleStatus.EVStatus(
            charging: evStatusData["batteryCharge"] as? Bool ?? false,
            chargeSpeed: max(
                extractNumber(from: evStatusData["batteryStndChrgPower"]) ?? 0,
                extractNumber(from: evStatusData["batteryFstChrgPower"]) ?? 0
            ),
            evRange: VehicleStatus.FuelRange(range: evRange, percentage: batteryStatus),
            plugType: VehicleStatus.PlugType(fromBatteryPlugin: batteryPlugin),
            chargeTime: .seconds(60 * chargeTime),
            targetSocAC: targetSocAC,
            targetSocDC: targetSocDC
        )
    }

    private func parseGasRange(from vehicleStatus: [String: Any]) -> VehicleStatus.FuelRange? {
        guard let distanceToEmptyData = vehicleStatus["distanceToEmpty"] as? [String: Any],
              let gasRangeValue: Double = extractNumber(from: distanceToEmptyData["value"]),
              let gasRangeUnit: Int = extractNumber(from: distanceToEmptyData["unit"]),
              let fuelLevel: Double = extractNumber(from: vehicleStatus["fuelLevel"]) else { return nil }

        let gasRangeDistance = Distance(length: gasRangeValue, units: Distance.Units(gasRangeUnit))
        return VehicleStatus.FuelRange(range: gasRangeDistance, percentage: fuelLevel)
    }

    private func parseLocation(from lastVehicleInfo: [String: Any]) -> VehicleStatus.Location {
        let location = lastVehicleInfo["location"] as? [String: Any] ?? [:]
        let coord = location["coord"] as? [String: Any] ?? [:]
        return VehicleStatus.Location(
            latitude: extractNumber(from: coord["lat"]) ?? 0,
            longitude: extractNumber(from: coord["lon"]) ?? 0
        )
    }

    private func parseClimateStatus(from vehicleStatus: [String: Any]) -> VehicleStatus.ClimateStatus {
        let climate = vehicleStatus["climate"] as? [String: Any] ?? [:]
        let airTemp = climate["airTemp"] as? [String: Any] ?? [:]
        let heatingAccessory = climate["heatingAccessory"] as? [String: Any] ?? [:]

        return VehicleStatus.ClimateStatus(
            defrostOn: climate["defrost"] as? Bool ?? false,
            airControlOn: climate["airCtrl"] as? Bool ?? false,
            steeringWheelHeatingOn: (extractNumber(from: heatingAccessory["steeringWheel"]) ?? 0) != 0,
            temperature: Temperature(units: extractNumber(from: airTemp["unit"]), value: airTemp["value"] as? String)
        )
    }

    private func parseSyncDate(from vehicleStatus: [String: Any]) -> Date? {
        guard let syncDateData = vehicleStatus["syncDate"] as? [String: Any],
              let utcString = syncDateData["utc"] as? String else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: utcString)
    }

    private func parseHoodTrunk(from vehicleStatus: [String: Any]) -> (trunkOpen: Bool?, hoodOpen: Bool?) {
        if let doorStatus = vehicleStatus["doorStatus"] as? [String: Any] {
            let trunk: Int? = extractNumber(from: doorStatus["trunk"])
            let hood: Int? = extractNumber(from: doorStatus["hood"])
            return (trunk.map { $0 != 0 }, hood.map { $0 != 0 })
        }
        return (vehicleStatus["trunkOpen"] as? Bool, vehicleStatus["hoodOpen"] as? Bool)
    }

    private func parseBattery12V(from vehicleStatus: [String: Any]) -> Int? {
        if let batteryStatus = vehicleStatus["batteryStatus"] as? [String: Any],
           let stateOfCharge: Int = extractNumber(from: batteryStatus["stateOfCharge"]) {
            return stateOfCharge
        }
        if let batteryData = vehicleStatus["battery"] as? [String: Any],
           let batSoc: Int = extractNumber(from: batteryData["batSoc"]) {
            return batSoc
        }
        return nil
    }

    private func parseDoorOpen(from vehicleStatus: [String: Any]) -> VehicleStatus.DoorStatus? {
        let doorData: [String: Any]?
        if let status = vehicleStatus["doorStatus"] as? [String: Any] {
            doorData = status
        } else if let open = vehicleStatus["doorOpen"] as? [String: Any] {
            doorData = open
        } else {
            return nil
        }

        guard let data = doorData else { return nil }
        return VehicleStatus.DoorStatus(
            frontLeft: (extractNumber(from: data["frontLeft"]) ?? 0) != 0,
            frontRight: (extractNumber(from: data["frontRight"]) ?? 0) != 0,
            backLeft: (extractNumber(from: data["backLeft"]) ?? 0) != 0,
            backRight: (extractNumber(from: data["backRight"]) ?? 0) != 0
        )
    }

    private func parseTirePressure(from vehicleStatus: [String: Any]) -> VehicleStatus.TirePressureWarning? {
        if let tireData = vehicleStatus["tirePressure"] as? [String: Any] {
            return VehicleStatus.TirePressureWarning(
                frontLeft: (extractNumber(from: tireData["frontLeft"]) ?? 0) != 0,
                frontRight: (extractNumber(from: tireData["frontRight"]) ?? 0) != 0,
                rearLeft: (extractNumber(from: tireData["rearLeft"]) ?? 0) != 0,
                rearRight: (extractNumber(from: tireData["rearRight"]) ?? 0) != 0,
                all: (extractNumber(from: tireData["all"]) ?? 0) != 0
            )
        }
        if let tireData = vehicleStatus["tirePressureLamp"] as? [String: Any] {
            return VehicleStatus.TirePressureWarning(
                frontLeft: (extractNumber(from: tireData["tirePressureWarningLampFrontLeft"]) ?? 0) != 0,
                frontRight: (extractNumber(from: tireData["tirePressureWarningLampFrontRight"]) ?? 0) != 0,
                rearLeft: (extractNumber(from: tireData["tirePressureWarningLampRearLeft"]) ?? 0) != 0,
                rearRight: (extractNumber(from: tireData["tirePressureWarningLampRearRight"]) ?? 0) != 0,
                all: (extractNumber(from: tireData["tirePressureWarningLampAll"]) ?? 0) != 0
            )
        }
        return nil
    }

    // MARK: - Error Handling

    private func checkForKiaErrors(data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any],
              let errorCode: Int = extractNumber(from: status["errorCode"]),
              errorCode != 0 else { return }

        let errorMessage = status["errorMessage"] as? String ?? "Unknown Kia API error"
        let statusCode: Int = extractNumber(from: status["statusCode"]) ?? -1
        let errorType: Int = extractNumber(from: status["errorType"]) ?? -1
        let messageLower = errorMessage.lowercased()

        if statusCode == 1, errorType == 1, errorCode == 1,
           messageLower.contains("valid email") || messageLower.contains("invalid") ||
           messageLower.contains("credential") {
            throw APIError.invalidCredentials("Invalid username or password", apiName: apiName)
        }

        if errorCode == 1005 || errorCode == 1103 {
            throw APIError.invalidVehicleSession(errorMessage, apiName: apiName)
        }

        if errorCode == 1003,
           messageLower.contains("session key") || messageLower.contains("invalid") ||
           messageLower.contains("expired") {
            throw APIError.invalidCredentials("Session Key is either invalid or expired", apiName: apiName)
        }

        if errorCode == 9789 {
            throw APIError.kiaInvalidRequest(
                "Kia API is currently unsupported. " +
                "See https://github.com/schmidtwmark/BetterBlueKit/issues/7 for updates",
                apiName: apiName
            )
        }

        if errorCode == 429 {
            throw APIError.serverError("Rate limited", apiName: apiName)
        }

        if errorCode == 503 {
            throw APIError.serverError("Service unavailable", apiName: apiName)
        }
    }
}
// swiftlint:enable type_body_length file_length
