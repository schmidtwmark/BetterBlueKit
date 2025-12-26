//
//  CoreEnumsTests.swift
//  BetterBlueKit
//
//  Core enums and utility function tests
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("CoreEnums Tests")
struct CoreEnumsTests {

    // MARK: - Brand Tests

    @Test("Brand display names are correct")
    func testBrandDisplayNames() {
        #expect(Brand.hyundai.displayName == "Hyundai")
        #expect(Brand.kia.displayName == "Kia")
        #expect(Brand.fake.displayName == "Fake (Testing)")
    }

    @Test("Brand availableBrands returns all brands in DEBUG")
    func testAvailableBrandsDebug() {
        // In DEBUG mode, should return all brands
        #if DEBUG
        let brands = Brand.availableBrands()
        #expect(brands.count == 3)
        #expect(brands.contains(.hyundai))
        #expect(brands.contains(.kia))
        #expect(brands.contains(.fake))
        #endif
    }

    @Test("Brand availableBrands returns production brands for normal users")
    func testAvailableBrandsProduction() {
        let brands = Brand.availableBrands(for: "normal@example.com", password: "password")
        #if DEBUG
        // In debug, still returns all brands
        #expect(brands.count == 3)
        #else
        // In release, returns only production brands
        #expect(brands.count == 2)
        #expect(brands.contains(.hyundai))
        #expect(brands.contains(.kia))
        #expect(!brands.contains(.fake))
        #endif
    }

    @Test("Brand availableBrands returns all brands for test account")
    func testAvailableBrandsTestAccount() {
        let brands = Brand.availableBrands(for: "testaccount@betterblue.com", password: "betterblue")
        #expect(brands.count == 3)
        #expect(brands.contains(.hyundai))
        #expect(brands.contains(.kia))
        #expect(brands.contains(.fake))
    }

    @Test("Brand Hyundai base URLs are correct")
    func testHyundaiBaseUrls() {
        #expect(Brand.hyundaiBaseUrl(region: .usa) == "https://api.telematics.hyundaiusa.com")
        #expect(Brand.hyundaiBaseUrl(region: .canada) == "https://mybluelink.ca")
        #expect(Brand.hyundaiBaseUrl(region: .europe) == "https://prd.eu-ccapi.hyundai.com:8080")
        #expect(Brand.hyundaiBaseUrl(region: .australia) == "https://au-apigw.ccs.hyundai.com.au:8080")
        #expect(Brand.hyundaiBaseUrl(region: .china) == "https://prd.cn-ccapi.hyundai.com")
        #expect(Brand.hyundaiBaseUrl(region: .india) == "https://prd.in-ccapi.hyundai.connected-car.io:8080")
    }

    @Test("Brand Kia base URLs are correct")
    func testKiaBaseUrls() {
        #expect(Brand.kiaBaseUrl(region: .usa) == "https://api.owners.kia.com")
        #expect(Brand.kiaBaseUrl(region: .canada) == "https://kiaconnect.ca")
        #expect(Brand.kiaBaseUrl(region: .europe) == "https://prd.eu-ccapi.kia.com:8080")
        #expect(Brand.kiaBaseUrl(region: .australia) == "https://au-apigw.ccs.kia.com.au:8082")
        #expect(Brand.kiaBaseUrl(region: .china) == "https://prd.cn-ccapi.kia.com")
        #expect(Brand.kiaBaseUrl(region: .india) == "https://prd.in-ccapi.kia.connected-car.io:8080")
    }

    // MARK: - Region Tests

    @Test("Region apiBaseURL returns correct URLs for Hyundai")
    func testRegionApiBaseURLHyundai() {
        #expect(Region.usa.apiBaseURL(for: .hyundai) == "https://api.telematics.hyundaiusa.com")
        #expect(Region.canada.apiBaseURL(for: .hyundai) == "https://mybluelink.ca")
        #expect(Region.europe.apiBaseURL(for: .hyundai) == "https://prd.eu-ccapi.hyundai.com:8080")
    }

    @Test("Region apiBaseURL returns correct URLs for Kia")
    func testRegionApiBaseURLKia() {
        #expect(Region.usa.apiBaseURL(for: .kia) == "https://api.owners.kia.com")
        #expect(Region.canada.apiBaseURL(for: .kia) == "https://kiaconnect.ca")
        #expect(Region.europe.apiBaseURL(for: .kia) == "https://prd.eu-ccapi.kia.com:8080")
    }

    @Test("Region apiBaseURL returns fake URL for fake brand")
    func testRegionApiBaseURLFake() {
        #expect(Region.usa.apiBaseURL(for: .fake) == "https://fake.api.testing.com")
        #expect(Region.canada.apiBaseURL(for: .fake) == "https://fake.api.testing.com")
    }

    // MARK: - FuelType Tests

    @Test("FuelType initialization from number")
    func testFuelTypeFromNumber() {
        #expect(FuelType(number: 0) == .gas)
        #expect(FuelType(number: 2) == .electric)
        #expect(FuelType(number: 5) == .gas) // default case
        #expect(FuelType(number: -1) == .gas) // default case
    }

    @Test("FuelType all cases exist")
    func testFuelTypeAllCases() {
        let allCases = FuelType.allCases
        #expect(allCases.count == 2)
        #expect(allCases.contains(.gas))
        #expect(allCases.contains(.electric))
    }

    // MARK: - Utility Function Tests

    @Test("isTestAccount identifies test account correctly")
    func testIsTestAccount() {
        #expect(isTestAccount(username: "testaccount@betterblue.com", password: "betterblue") == true)
        #expect(isTestAccount(username: "TESTACCOUNT@BETTERBLUE.COM", password: "betterblue") == true)
        #expect(isTestAccount(username: "testaccount@betterblue.com", password: "wrongpassword") == false)
        #expect(isTestAccount(username: "normal@example.com", password: "betterblue") == false)
        #expect(isTestAccount(username: "normal@example.com", password: "password") == false)
    }

    // MARK: - Codable Tests

    @Test("Brand is Codable")
    func testBrandCodable() throws {
        let brands: [Brand] = [.hyundai, .kia, .fake]

        for brand in brands {
            let encoded = try JSONEncoder().encode(brand)
            let decoded = try JSONDecoder().decode(Brand.self, from: encoded)
            #expect(decoded == brand)
        }
    }

    @Test("Region is Codable")
    func testRegionCodable() throws {
        let regions: [Region] = [.usa, .canada, .europe, .australia, .china, .india]

        for region in regions {
            let encoded = try JSONEncoder().encode(region)
            let decoded = try JSONDecoder().decode(Region.self, from: encoded)
            #expect(decoded == region)
        }
    }

    @Test("FuelType is Codable")
    func testFuelTypeCodable() throws {
        let fuelTypes: [FuelType] = [.gas, .electric]

        for fuelType in fuelTypes {
            let encoded = try JSONEncoder().encode(fuelType)
            let decoded = try JSONDecoder().decode(FuelType.self, from: encoded)
            #expect(decoded == fuelType)
        }
    }
}
