//
//  HyundaiAPIClientFactory.swift
//  BetterBlueKit
//
//  Factory for creating region-specific Hyundai API clients
//

import Foundation

@MainActor
public enum HyundaiAPIClientFactory {
    public static func createClient(configuration: APIClientConfiguration) -> any APIClientProtocol {
        switch configuration.region {
        case .canada:
            let provider = HyundaiAPIEndpointProviderCanada(configuration: configuration)
            return HyundaiCanadaAPIClient(configuration: configuration, endpointProvider: provider)
        default:
            let provider = HyundaiAPIEndpointProviderUSA(configuration: configuration)
            return APIClient(configuration: configuration, endpointProvider: provider)
        }
    }
}
