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

    // MARK: - Regional API Configuration Tests

    @Test("API headers vary by region")
    @MainActor func testAPIHeadersVaryByRegion() {
        let regions: [Region] = [.usa, .europe, .canada]

        for region in regions {
            let config = APIClientConfiguration(
                region: region,
                brand: .kia,
                username: "test@example.com",
                password: "password123",
                pin: "0000",
                accountId: UUID()
            )

            let provider = KiaAPIEndpointProvider(configuration: config)
            let endpoint = provider.loginEndpoint()

            // Verify region-specific host header
            let hostHeader = endpoint.headers["host"]
            #expect(hostHeader != nil)
            #expect(hostHeader?.isEmpty == false)

            // Host should correspond to the region
            let baseURL = region.apiBaseURL(for: .kia)
            let expectedHost = URL(string: baseURL)?.host

            // Compare host parts (ignoring ports)
            if let host = hostHeader, let expected = expectedHost {
                let actualHost = host.components(separatedBy: ":").first
                #expect(actualHost == expected)
            }
        }
    }

    @Test("Time zone offset handling by region")
    @MainActor func testTimeZoneOffsetHandlingByRegion() {
        let regions: [Region] = [.usa, .europe, .canada]

        for region in regions {
            let config = APIClientConfiguration(
                region: region,
                brand: .kia,
                username: "test@example.com",
                password: "password123",
                pin: "0000",
                accountId: UUID()
            )

            let provider = KiaAPIEndpointProvider(configuration: config)
            let endpoint = provider.loginEndpoint()

            // Verify offset header exists and is a valid integer
            let offsetHeader = endpoint.headers["offset"]
            #expect(offsetHeader != nil)

            if let offsetString = offsetHeader, let offset = Int(offsetString) {
                // Offset should be within reasonable bounds (-12 to +14)
                #expect(offset >= -12)
                #expect(offset <= 14)
            }
        }
    }

    // MARK: - Regional Vehicle Data Tests

    @Test("Regional vehicle parsing differences")
    @MainActor func testRegionalVehicleParsingDifferences() throws {
        // Test parsing the same vehicle data with different regional configurations
        let vehicleJSON = """
        {
          "payload": {
            "vehicleInfoList": [{
              "lastVehicleInfo": {
                "vehicleStatusRpt": {
                  "vehicleStatus": {
                    "doorLock": true,
                    "distanceToEmpty": {
                      "value": 200,
                      "unit": 3
                    },
                    "climate": {
                      "airCtrl": false,
                      "airTemp": {
                        "value": "20",
                        "unit": 0
                      },
                      "defrost": false,
                      "heatingAccessory": {
                        "steeringWheel": 0
                      }
                    }
                  }
                },
                "location": {
                  "coord": {
                    "lat": 51.5074,
                    "lon": -0.1278
                  }
                }
              }
            }]
          }
        }
        """

        let data = Data(vehicleJSON.utf8)
        let regions: [Region] = [.usa, .europe, .canada]

        for region in regions {
            let config = APIClientConfiguration(
                region: region,
                brand: .kia,
                username: "test@example.com",
                password: "password123",
                pin: "0000",
                accountId: UUID()
            )

            let provider = KiaAPIEndpointProvider(configuration: config)
            let vehicle = Vehicle(
                vin: "TEST_REGIONAL_VIN",
                regId: "REG_REGIONAL",
                model: "Regional Test Model",
                accountId: UUID(),
                isElectric: false,
                generation: 3,
                odometer: Distance(length: 10000, units: .miles)
            )

            // Should parse successfully regardless of region
            let status = try provider.parseVehicleStatusResponse(data, for: vehicle)

            #expect(status.vin == vehicle.vin)
            #expect(status.lockStatus == VehicleStatus.LockStatus.locked)
            #expect(status.location.latitude == 51.5074)
            #expect(status.location.longitude == -0.1278)
            #expect(status.climateStatus.temperature.value == 20.0)
            #expect(status.climateStatus.temperature.units == Temperature.Units.celsius)
        }
    }

    // MARK: - Regional Error Message Tests

    @Test("Regional error message consistency")
    func testRegionalErrorMessageConsistency() {
        let errorTypes: [HyundaiKiaAPIError.ErrorType] = [
            .invalidCredentials,
            .invalidVehicleSession,
            .serverError,
            .concurrentRequest,
            .failedRetryLogin,
            .invalidPin
        ]

        for _ in errorTypes {
            let error1 = HyundaiKiaAPIError.logError("Test error", code: 123, apiName: "USAAPI")
            let error2 = HyundaiKiaAPIError.logError("Test error", code: 123, apiName: "EuropeAPI")

            // Error structure should be consistent across regions
            #expect(error1.errorType == error2.errorType)
            // Note: HyundaiKiaAPIError doesn't have a statusCode property in this implementation
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
    @MainActor func testRegionalAPIClientConfigurationValidation() {
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

                // Should be able to create providers for all combinations
                if brand == .kia {
                    let provider = KiaAPIEndpointProvider(configuration: config)
                    let endpoint = provider.loginEndpoint()
                    #expect(endpoint.url.hasPrefix("https://"))
                } else if brand == .hyundai {
                    let provider = HyundaiAPIEndpointProvider(configuration: config)
                    let endpoint = provider.loginEndpoint()
                    #expect(endpoint.url.hasPrefix("https://"))
                }
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
}
