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

    public static func hyundaiBaseUrl(region: Region) -> String {
        switch region {
        case .usa: return "https://api.telematics.hyundaiusa.com"
        case .canada: return "https://mybluelink.ca"
        case .europe: return "https://prd.eu-ccapi.hyundai.com:8080"
        case .australia: return "https://au-apigw.ccs.hyundai.com.au:8080"
        case .china: return "https://prd.cn-ccapi.hyundai.com"
        case .india: return "https://prd.in-ccapi.hyundai.connected-car.io:8080"
        }
    }

    public static func kiaBaseUrl(region: Region) -> String {
        switch region {
        case .usa: return "https://api.owners.kia.com"
        case .canada: return "https://kiaconnect.ca"
        case .europe: return "https://prd.eu-ccapi.kia.com:8080"
        case .australia: return "https://au-apigw.ccs.kia.com.au:8082"
        case .china: return "https://prd.cn-ccapi.kia.com"
        case .india: return "https://prd.in-ccapi.kia.connected-car.io:8080"
        }
    }
}

public func isTestAccount(username: String, password: String) -> Bool {
    username.lowercased() == "testaccount@betterblue.com" && password == "betterblue"
}

public enum FuelType: String, CaseIterable, Codable {
    case gas
    case electric

    init(number: Int) {
        self = switch number {
        case 0: .gas
        case 2: .electric
        default: .gas
        }
    }
}

public enum Region: String, CaseIterable, Codable {
    case usa = "US", canada = "CA", europe = "EU"
    case australia = "AU", china = "CN", india = "IN"

    public func apiBaseURL(for brand: Brand) -> String {
        switch brand {
        case .hyundai:
            return Brand.hyundaiBaseUrl(region: self)
        case .kia:
            return Brand.kiaBaseUrl(region: self)
        case .fake:
            return "https://fake.api.testing.com"
        }
    }
}
