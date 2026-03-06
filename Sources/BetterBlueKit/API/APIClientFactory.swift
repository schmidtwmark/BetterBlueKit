//
//  APIClientFactory.swift
//  BetterBlueKit
//
//  Factory for creating region and brand-specific API clients
//

import Foundation

// MARK: - API Client Factory

/// Creates the appropriate API client for a given brand and region.
/// This factory handles the core Hyundai/Kia clients but NOT:
/// - Fake/testing clients (app-specific)
/// - Caching wrappers (app-specific)
/// Those should be handled by the consuming application.
@MainActor
public func createBetterBlueKitAPIClient(
    configuration: APIClientConfiguration
) throws -> any APIClientProtocol {
    switch configuration.brand {
    case .hyundai:
        return try createHyundaiClient(configuration: configuration)
    case .kia:
        return try createKiaClient(configuration: configuration)
    case .fake:
        throw APIError.regionNotSupported(
            "Fake brand is not supported by BetterBlueKit API client factory"
        )
    }
}

// MARK: - Hyundai Client Creation

@MainActor
private func createHyundaiClient(configuration: APIClientConfiguration) throws -> any APIClientProtocol {
    switch configuration.region {
    case .usa:
        return HyundaiUSAAPIClient(configuration: configuration)
    case .canada:
        return HyundaiCanadaAPIClient(configuration: configuration)
    case .europe:
        return HyundaiEuropeAPIClient(configuration: configuration)
    case .australia, .china, .india:
        throw APIError.regionNotSupported(
            "\(Brand.hyundai.displayName) is not yet supported in \(configuration.region.rawValue)"
        )
    }
}

// MARK: - Kia Client Creation

@MainActor
private func createKiaClient(configuration: APIClientConfiguration) throws -> any APIClientProtocol {
    switch configuration.region {
    case .usa:
        return KiaUSAAPIClient(configuration: configuration)
    case .canada, .europe, .australia, .china, .india:
        throw APIError.regionNotSupported(
            "\(Brand.kia.displayName) is not yet supported in \(configuration.region.rawValue)"
        )
    }
}

// MARK: - Region Support Queries

/// Returns the list of supported regions for a given brand.
public func supportedRegions(for brand: Brand) -> [Region] {
    switch brand {
    case .hyundai:
        return [.usa, .canada, .europe]
    case .kia:
        return [.usa]
    case .fake:
        return Region.allCases
    }
}

public func betaRegions(for brand: Brand) -> [Region] {
    switch brand {
    case .hyundai:
        return [.canada, .europe]
    default: return []
    }
}
