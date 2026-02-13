//
//  APIClientFactory.swift
//  BetterBlueKit
//
//  Factory for creating region and brand-specific API clients
//

import Foundation

// MARK: - Unsupported Region Error

public enum RegionSupportError: Error, LocalizedError {
    case unsupportedRegion(brand: Brand, region: Region)

    public var errorDescription: String? {
        switch self {
        case .unsupportedRegion(let brand, let region):
            return "\(brand.displayName) is not yet supported in \(region.rawValue). " +
                   "This region is coming soon."
        }
    }
}

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
        throw RegionSupportError.unsupportedRegion(brand: .fake, region: configuration.region)
    }
}

// MARK: - Hyundai Client Creation

@MainActor
private func createHyundaiClient(configuration: APIClientConfiguration) throws -> any APIClientProtocol {
    switch configuration.region {
    case .usa:
        return HyundaiUSAAPIClient(configuration: configuration)
    case .europe:
        return HyundaiEuropeAPIClient(configuration: configuration)
    case .canada, .australia, .china, .india:
        throw RegionSupportError.unsupportedRegion(brand: .hyundai, region: configuration.region)
    }
}

// MARK: - Kia Client Creation

@MainActor
private func createKiaClient(configuration: APIClientConfiguration) throws -> any APIClientProtocol {
    switch configuration.region {
    case .usa:
        return KiaUSAAPIClient(configuration: configuration)
    case .canada, .europe, .australia, .china, .india:
        throw RegionSupportError.unsupportedRegion(brand: .kia, region: configuration.region)
    }
}

// MARK: - Region Support Queries

/// Returns whether a brand/region combination is currently supported.
public func isRegionSupported(brand: Brand, region: Region) -> Bool {
    switch brand {
    case .hyundai, .kia:
        switch region {
        case .usa, .europe:
            return true
        case .canada, .australia, .china, .india:
            return false
        }
    case .fake:
        return false
    }
}

/// Returns the list of supported regions for a given brand.
public func supportedRegions(for brand: Brand) -> [Region] {
    switch brand {
    case .hyundai, .kia:
        return [.usa, .europe]  // Only fully implemented regions
    case .fake:
        return []
    }
}
