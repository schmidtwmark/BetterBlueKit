//
//  GenesisCanada+SurroundView.swift
//  BetterBlueKit
//
//  Genesis Canada Surround View Monitor (SVM)
//

import Foundation

extension GenesisCanadaAPIClient {

    // MARK: - APIClientProtocol

    public func requestSurroundViewCapture(for vehicle: Vehicle, authToken: AuthToken) async throws {
        throw APIError.featureNotSupported(
            "Surround view capture is not yet supported for Genesis in BetterBlueKit.", apiName: apiName
        )
    }

    public func fetchSurroundViewCaptures(
        for vehicle: Vehicle,
        authToken: AuthToken
    ) async throws -> [SurroundViewCapture] {
        throw APIError.featureNotSupported(
            "Surround view retrieval is not yet supported for Genesis in BetterBlueKit.", apiName: apiName
        )
    }
}
