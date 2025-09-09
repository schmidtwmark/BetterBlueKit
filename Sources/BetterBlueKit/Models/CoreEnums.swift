//
//  CoreEnums.swift
//  BetterBlueKit
//
//  Core enums and utility functions
//

import Foundation

// MARK: - Core Enums

public enum Brand: String, Codable, CaseIterable {
    case hyundai, kia, fake

    public var displayName: String {
        switch self {
        case .hyundai: "Hyundai"
        case .kia: "Kia"
        case .fake: "Fake (Testing)"
        }
    }

    public static func availableBrands(for username: String = "", password: String = "") -> [Brand] {
        #if DEBUG
            return Brand.allCases
        #else
            if isTestAccount(username: username, password: password) {
                return Brand.allCases
            }
            return [.hyundai, .kia]
        #endif
    }
}

public func isTestAccount(username: String, password: String) -> Bool {
    username.lowercased() == "testaccount@betterblue.com" && password == "betterblue"
}

public enum Region: String, CaseIterable, Codable {
    case usa = "US", canada = "CA", europe = "EU"
    case australia = "AU", china = "CN", india = "IN"

    public func apiBaseURL(for brand: Brand) -> String {
        switch (self, brand) {
        case (.usa, .hyundai): "https://api.telematics.hyundaiusa.com"
        case (.usa, .kia): "https://prd.us-ccapi.kia.com:8080"
        case (.canada, _): "https://prd.ca-ccapi.kia.com:8080"
        case (.europe, _): "https://prd.eu-ccapi.kia.com:8080"
        case (.australia, _): "https://prd.au-ccapi.kia.com:8080"
        case (.china, _): "https://prd.cn-ccapi.kia.com:8080"
        case (.india, _): "https://prd.in-ccapi.kia.com:8080"
        case (_, .fake): "https://fake.api.testing.com"
        }
    }
}
