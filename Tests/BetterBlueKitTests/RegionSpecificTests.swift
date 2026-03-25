//
//  RegionSpecificTests.swift
//  BetterBlueKit
//
//  Region-specific API behavior and data format tests
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Region Specific Tests")
struct RegionSpecificTests {

    // MARK: - API Endpoint Regional Differences

    @Test("USA region API endpoint validation")
    func testUSARegionAPIEndpoints() {
        let region = Region.usa

        let kiaURL = region.apiBaseURL(for: .kia)
        let hyundaiURL = region.apiBaseURL(for: .hyundai)

        // Verify USA-specific URLs (checking actual URL patterns)
        #expect(kiaURL.contains("api.owners.kia.com") || kiaURL.contains("usa") || kiaURL.contains("us"))
        #expect(hyundaiURL.contains("ccapi.hyundai") || hyundaiURL.contains("usa") || hyundaiURL.contains("us"))

        // Verify HTTPS
        #expect(kiaURL.hasPrefix("https://"))
        #expect(hyundaiURL.hasPrefix("https://"))

        // Verify URLs are different for different brands
        #expect(kiaURL != hyundaiURL)
    }

    @Test("Europe region API endpoint validation")
    func testEuropeRegionAPIEndpoints() {
        let region = Region.europe

        let kiaURL = region.apiBaseURL(for: .kia)
        let hyundaiURL = region.apiBaseURL(for: .hyundai)

        // Verify Europe-specific URLs
        #expect(kiaURL.contains("eu") || kiaURL.contains("europe"))
        #expect(hyundaiURL.contains("eu") || hyundaiURL.contains("europe"))

        // Verify HTTPS
        #expect(kiaURL.hasPrefix("https://"))
        #expect(hyundaiURL.hasPrefix("https://"))

        // Verify URLs are different from USA
        let usaKiaURL = Region.usa.apiBaseURL(for: .kia)
        #expect(kiaURL != usaKiaURL)
    }

    @Test("Canada region API endpoint validation")
    func testCanadaRegionAPIEndpoints() {
        let region = Region.canada

        let kiaURL = region.apiBaseURL(for: .kia)
        let hyundaiURL = region.apiBaseURL(for: .hyundai)

        // Verify Canada-specific URLs (might share NA infrastructure)
        #expect(kiaURL.hasPrefix("https://"))
        #expect(hyundaiURL.hasPrefix("https://"))

        // URLs should be valid and accessible
        #expect(URL(string: kiaURL) != nil)
        #expect(URL(string: hyundaiURL) != nil)
    }

    // MARK: - Regional Data Format Tests

    @Test("Temperature unit preferences by region")
    func testTemperatureUnitPreferencesByRegion() {
        // USA typically uses Fahrenheit
        let usaTemp = Temperature(units: 1, value: "72") // unit: 1 = Fahrenheit
        #expect(usaTemp.units == .fahrenheit)
        #expect(usaTemp.value == 72.0)

        // Europe typically uses Celsius
        let europeTemp = Temperature(units: 0, value: "22") // unit: 0 = Celsius
        #expect(europeTemp.units == .celsius)
        #expect(europeTemp.value == 22.0)

        // Verify conversion works both ways
        let convertedToF = europeTemp.units.format(europeTemp.value, to: .fahrenheit)
        let convertedToC = usaTemp.units.format(usaTemp.value, to: .celsius)

        // Parse the numeric values from the formatted strings
        let fahrenheitValue = Double(convertedToF.replacingOccurrences(of: "°F", with: "")) ?? 0
        let celsiusValue = Double(convertedToC.replacingOccurrences(of: "°C", with: "")) ?? 0

        #expect(abs(fahrenheitValue - 72.0) < 1.0) // 22°C ≈ 72°F
        #expect(abs(celsiusValue - 22.0) < 1.0) // 72°F ≈ 22°C
    }

    @Test("Distance unit preferences by region")
    func testDistanceUnitPreferencesByRegion() {
        // USA typically uses miles
        let usaDistance = Distance(length: 100.0, units: .miles)
        #expect(usaDistance.units == .miles)
        #expect(usaDistance.length == 100.0)

        // Europe typically uses kilometers
        let europeDistance = Distance(length: 160.0, units: .kilometers)
        #expect(europeDistance.units == .kilometers)
        #expect(europeDistance.length == 160.0)

        // Verify conversion works
        let milesFromKm = europeDistance.units.format(europeDistance.length, to: .miles)
        let kmFromMiles = usaDistance.units.format(usaDistance.length, to: .kilometers)

        // Parse the numeric values from the formatted strings
        let milesValue = Double(milesFromKm.replacingOccurrences(of: " mi", with: "")) ?? 0
        let kmValue = Double(kmFromMiles.replacingOccurrences(of: " km", with: "")) ?? 0

        #expect(abs(milesValue - 99.42) < 1.0) // 160 km ≈ 99.42 miles
        #expect(abs(kmValue - 160.93) < 1.0) // 100 miles ≈ 160.93 km
    }

    // MARK: - Regional Error Message Tests

    @Test("Regional error message consistency")
    func testRegionalErrorMessageConsistency() {
        let errorTypes: [APIError.ErrorType] = [
            .invalidCredentials,
            .invalidVehicleSession,
            .serverError,
            .concurrentRequest,
            .failedRetryLogin,
            .invalidPin
        ]

        for _ in errorTypes {
            let error1 = APIError.logError("Test error", code: 123, apiName: "USAAPI")
            let error2 = APIError.logError("Test error", code: 123, apiName: "EuropeAPI")

            // Error structure should be consistent across regions
            #expect(error1.errorType == error2.errorType)
        }
    }

    // MARK: - Brand and Region Combination Tests

    @Test("All brand-region combinations are supported")
    func testAllBrandRegionCombinationsSupported() {
        let regions: [Region] = [.usa, .europe, .canada]
        let brands: [Brand] = [.kia, .hyundai]

        for region in regions {
            for brand in brands {
                let baseURL = region.apiBaseURL(for: brand)

                // Should return a valid URL for all combinations
                #expect(baseURL.hasPrefix("https://"))
                #expect(baseURL.count > 10)

                let url = URL(string: baseURL)
                #expect(url != nil)
                #expect(url?.scheme == "https")
                #expect(url?.host != nil)
                #expect(url?.host?.isEmpty == false)
            }
        }
    }

    @Test("Regional API client configuration validation")
    func testRegionalAPIClientConfigurationValidation() {
        let regions: [Region] = [.usa, .europe, .canada]
        let brands: [Brand] = [.kia, .hyundai]

        for region in regions {
            for brand in brands {
                let config = APIClientConfiguration(
                    region: region,
                    brand: brand,
                    username: "test@example.com",
                    password: "password123",
                    pin: "0000",
                    accountId: UUID()
                )

                #expect(config.region == region)
                #expect(config.brand == brand)
                #expect(config.username == "test@example.com")
                #expect(config.password == "password123")
                #expect(config.pin == "0000")
            }
        }
    }

    // MARK: - Date and Time Format Tests

    @Test("Regional date format handling")
    func testRegionalDateFormatHandling() {
        // Test parsing of date strings that might vary by region
        let dateStrings = [
            "20251003012955", // Standard format: yyyyMMddHHmmss
            "2025-10-03T01:29:55Z", // ISO format
            "2025/10/03 01:29:55" // Alternative format
        ]

        let standardFormatter = DateFormatter()
        standardFormatter.dateFormat = "yyyyMMddHHmmss"
        standardFormatter.timeZone = TimeZone(identifier: "UTC")

        for dateString in dateStrings {
            if dateString == "20251003012955" {
                // This format should parse successfully
                let date = standardFormatter.date(from: dateString)
                #expect(date != nil)

                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "UTC")!
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date!)

                #expect(components.year == 2025)
                #expect(components.month == 10)
                #expect(components.day == 3)
                #expect(components.hour == 1)
                #expect(components.minute == 29)
                #expect(components.second == 55)
            }
        }
    }

    // MARK: - Canada parsing extras

    @MainActor @Test("Canada status parsing includes engine/acc/remote flags")
    func testCanadaStatusParsingExtraFlags() throws {
        let status: [String: Any] = [
            "engine": true,
            "acc": false,
            "remoteIgnition": true,
            "transCond": false,
            "sleepModeCheck": true,
            "doorLock": true,
            "doorOpen": ["frontLeft": 0, "frontRight": 0, "backLeft": 0, "backRight": 0],
            "trunkOpen": false,
            "hoodOpen": true,
            "tirePressureLamp": ["all": 0, "frontLeft": 1, "frontRight": 0, "rearLeft": 0, "rearRight": 0],
            "battery": ["batSoc": 75],
            "airTemp": ["value": "22", "unit": 0],
            "defrost": false,
            "airCtrlOn": false,
            "steerWheelHeat": 1,
            "lastStatusDate": "20260221195224",
            "washerFluidStatus": true
        ]
        let json: [String: Any] = [
            "responseHeader": ["responseCode": 0],
            "result": ["status": status]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let config = APIClientConfiguration(
            region: .canada,
            brand: .hyundai,
            username: "",
            password: "",
            pin: "",
            accountId: UUID()
        )
        let client = HyundaiCanadaAPIClient(configuration: config)
        let vehicle = Vehicle(
            vin: "TESTVIN",
            regId: "REG",
            model: "MODEL",
            accountId: UUID(),
            isElectric: false,
            generation: 1,
            odometer: Distance(length: 0, units: .kilometers)
        )

        let statusResult = try client.parseCanadaVehicleStatusResponse(data, for: vehicle)
        #expect(statusResult.engineOn == true)
        #expect(statusResult.accessoryOn == false)
        #expect(statusResult.remoteIgnition == true)
        #expect(statusResult.transmissionCondition == false)
        #expect(statusResult.sleepMode == true)
        #expect(statusResult.washerFluidLow == true)
    }

    @MainActor @Test("Canada location response parsing reads fndmcr coordinates")
    func testCanadaLocationResponseParsing() throws {
        let json: [String: Any] = [
            "responseHeader": ["responseCode": 0],
            "result": [
                "coord": [
                    "lat": 43.6532,
                    "lon": -79.3832
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let config = APIClientConfiguration(
            region: .canada,
            brand: .hyundai,
            username: "",
            password: "",
            pin: "",
            accountId: UUID()
        )
        let client = HyundaiCanadaAPIClient(configuration: config)

        let location = try client.parseCanadaLocationResponse(data)
        #expect(location.latitude == 43.6532)
        #expect(location.longitude == -79.3832)
    }

    @MainActor @Test("Canada status parsing uses injected vehicle location coordinates")
    func testCanadaStatusParsingInjectedLocation() throws {
        let status: [String: Any] = [
            "doorLock": true,
            "airTemp": ["value": "22", "unit": 0],
            "defrost": false,
            "airCtrlOn": false,
            "steerWheelHeat": 0,
            "lastStatusDate": "20260221195224",
            "vehicleLocation": [
                "coord": [
                    "lat": 43.6532,
                    "lon": -79.3832
                ]
            ]
        ]
        let json: [String: Any] = [
            "responseHeader": ["responseCode": 0],
            "result": ["status": status]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let config = APIClientConfiguration(
            region: .canada,
            brand: .hyundai,
            username: "",
            password: "",
            pin: "",
            accountId: UUID()
        )
        let client = HyundaiCanadaAPIClient(configuration: config)
        let vehicle = Vehicle(
            vin: "TESTVIN",
            regId: "REG",
            model: "MODEL",
            accountId: UUID(),
            isElectric: false,
            generation: 1,
            odometer: Distance(length: 0, units: .kilometers)
        )

        let statusResult = try client.parseCanadaVehicleStatusResponse(data, for: vehicle)
        #expect(statusResult.location.latitude == 43.6532)
        #expect(statusResult.location.longitude == -79.3832)
    }

    // MARK: - API Client Creation Tests

    @Test("API client creation for supported regions")
    @MainActor func testAPIClientCreationForSupportedRegions() throws {
        // Hyundai USA should create successfully
        let hyundaiUSAConfig = APIClientConfiguration(
            region: .usa,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )
        let hyundaiUSAClient = try createBetterBlueKitAPIClient(configuration: hyundaiUSAConfig)
        #expect(hyundaiUSAClient is HyundaiUSAAPIClient)

        // Kia USA should create successfully
        let kiaUSAConfig = APIClientConfiguration(
            region: .usa,
            brand: .kia,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )
        let kiaUSAClient = try createBetterBlueKitAPIClient(configuration: kiaUSAConfig)
        #expect(kiaUSAClient is KiaUSAAPIClient)

        // Hyundai Europe should create successfully
        let hyundaiEuropeConfig = APIClientConfiguration(
            region: .europe,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )
        let hyundaiEuropeClient = try createBetterBlueKitAPIClient(configuration: hyundaiEuropeConfig)
        #expect(hyundaiEuropeClient is HyundaiEuropeAPIClient)

        // Hyundai Canada should create successfully
        let hyundaiCanadaConfig = APIClientConfiguration(
            region: .canada,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID()
        )
        let hyundaiCanadaClient = try createBetterBlueKitAPIClient(configuration: hyundaiCanadaConfig)
        #expect(hyundaiCanadaClient is HyundaiCanadaAPIClient)
    }

    @Test("API client creation for unsupported regions throws")
    @MainActor func testAPIClientCreationForUnsupportedRegions() {
        let unsupportedConfigs: [(Region, Brand)] = [
            (.canada, .kia),
            (.australia, .hyundai),
            (.australia, .kia),
            (.europe, .kia)  // Kia Europe not yet implemented
        ]

        for (region, brand) in unsupportedConfigs {
            let config = APIClientConfiguration(
                region: region,
                brand: brand,
                username: "test@example.com",
                password: "password123",
                pin: "0000",
                accountId: UUID()
            )

            do {
                _ = try createBetterBlueKitAPIClient(configuration: config)
                Issue.record("Expected APIError for \(brand) in \(region)")
            } catch let error as APIError {
                #expect(error.errorType == .regionNotSupported)
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }
}
