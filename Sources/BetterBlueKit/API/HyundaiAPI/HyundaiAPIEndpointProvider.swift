//
//  HyundaiAPIEndpointProvider.swift
//  BetterBlueKit
//
//  Hyundai API Endpoint Provider Base Class
//

import Foundation

// MARK: - Hyundai API Endpoint Provider Base

/// Base class for Hyundai API endpoint providers.
/// Subclasses should override endpoint methods for region-specific URLs.
/// Parsing methods are shared across all regions.
@MainActor
open class HyundaiAPIEndpointProviderBase: APIEndpointProvider {
    public let username: String
    public let password: String
    public let pin: String
    public let accountId: UUID
    public let region: Region

    public init(configuration: APIClientConfiguration) {
        username = configuration.username
        password = configuration.password
        pin = configuration.pin
        accountId = configuration.accountId
        region = configuration.region
    }

    // MARK: - Common Constants (can be overridden)

    open var clientId: String {
        "m66129Bb-em93-SPAHYN-bZ91-am4540zp19920"
    }

    open var clientSecret: String {
        "v558o935-6nne-423i-baa8"
    }

    open var apiHost: String {
        "api.telematics.hyundaiusa.com"
    }

    // MARK: - Common Header Helpers

    open func getHeaders() -> [String: String] {
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

    open func getAuthorizedHeaders(authToken: AuthToken, vehicle: Vehicle? = nil) -> [String: String] {
        var headers = getHeaders()
        headers["accessToken"] = authToken.accessToken
        headers["language"] = "0"
        headers["to"] = "ISS"
        headers["encryptFlag"] = "false"
        headers["from"] = "SPA"
        headers["offset"] = "-5"
        if let vehicle {
            headers["gen"] = String(vehicle.generation)
            headers["registrationId"] = vehicle.regId
            headers["vin"] = vehicle.vin
            headers["APPCLOUD-VIN"] = vehicle.vin
        }
        headers["brandIndicator"] = "H"
        headers["origin"] = "https://\(apiHost)"
        headers["referer"] = "https://\(apiHost)/login"
        headers["sec-fetch-dest"] = "empty"
        headers["sec-fetch-mode"] = "cors"
        headers["sec-fetch-site"] = "same-origin"
        headers["username"] = username
        headers["blueLinkServicePin"] = pin
        headers["refresh"] = "false"

        // Generate current timestamp in the required format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = dateFormatter.string(from: Date())
        headers["payloadGenerated"] = timestamp
        headers["includeNonConnectedVehicles"] = "Y"

        return headers
    }

    // MARK: - APIEndpointProvider Protocol (Overridable Endpoints)

    /// Subclasses must override to provide region-specific login endpoint
    open func loginEndpoint() -> APIEndpoint {
        fatalError("Subclasses must override loginEndpoint()")
    }

    /// Subclasses must override to provide region-specific vehicles endpoint
    open func fetchVehiclesEndpoint(authToken: AuthToken) -> APIEndpoint {
        fatalError("Subclasses must override fetchVehiclesEndpoint(authToken:)")
    }

    /// Subclasses must override to provide region-specific status endpoint
    open func fetchVehicleStatusEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
        fatalError("Subclasses must override fetchVehicleStatusEndpoint(for:authToken:)")
    }

    /// Subclasses must override to provide region-specific command endpoint
    open func sendCommandEndpoint(
        for vehicle: Vehicle,
        command: VehicleCommand,
        authToken: AuthToken
    ) -> APIEndpoint {
        fatalError("Subclasses must override sendCommandEndpoint(for:command:authToken:)")
    }

    /// Override to provide region-specific command body if needed
    open func getBodyForCommand(command: VehicleCommand, vehicle: Vehicle) -> [String: Any] {
        var body: [String: Any] = [:]
        if case let .startClimate(options) = command {
            if vehicle.isElectric {
                body = ["airCtrl": options.climate ? 1 : 0,
                        "airTemp": ["value": String(Int(options.temperature.value)),
                                    "unit": options.temperature.units.integer()],
                        "defrost": options.defrost, "heating1": options.heatValue]
                if vehicle.generation >= 3 {
                    body["igniOnDuration"] = options.duration
                    body["seatHeaterVentInfo"] = options.getSeatHeaterVentInfo()
                }
            } else {
                body = ["Ims": 0, "airCtrl": options.climate ? 1 : 0,
                        "airTemp": ["unit": options.temperature.units.integer(),
                                    "value": Int(options.temperature.value)],
                        "defrost": options.defrost, "heating1": options.heatValue,
                        "igniOnDuration": options.duration,
                        "seatHeaterVentInfo": options.getSeatHeaterVentInfo(),
                        "username": username, "vin": vehicle.vin]
            }
        } else if case .startCharge = command {
            body["chargeRatio"] = 100
        } else if case let .setTargetSOC(acLevel, dcLevel) = command {
            body["targetSOClist"] = [
                ["targetSOClevel": acLevel, "plugType": 1],
                ["targetSOClevel": dcLevel, "plugType": 0]
            ]
        }
        return body
    }

    // MARK: - EV Trip Details (Optional Feature - Override in subclass)

    open func supportsEVTripDetails() -> Bool {
        false
    }

    open func evTripDetailsEndpoint(for vehicle: Vehicle, authToken: AuthToken) -> APIEndpoint {
        fatalError("evTripDetailsEndpoint not implemented for this region")
    }

    open func parseEVTripDetailsResponse(_ data: Data) throws -> [EVTripDetail] {
        fatalError("parseEVTripDetailsResponse not implemented for this region")
    }
}
