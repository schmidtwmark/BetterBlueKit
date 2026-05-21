//
//  KiaEuropeAPIClient+Parsing.swift
//  BetterBlueKit
//
//  Response parsing for the Kia Europe client.
//

import Foundation

extension KiaEuropeAPIClient {

    package func parseAuthToken(from data: Data, isRefresh: Bool) throws -> AuthToken {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw APIError(
                message: "Failed to parse AuthToken response",
                apiName: apiName,
                errorType: .invalidCredentials
            )
        }

        let refreshToken: String = isRefresh
            ? (json["refresh_token"] as? String ?? configuration.refreshToken ?? "")
            : (configuration.refreshToken ?? "")

        return AuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    // parseVehiclesResponse / parseVehicleStatusResponse land here in Fase 3.
}
