//
//  BetterBlueKitTests.swift
//  BetterBlueKit
//
//  Main module and version info tests
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("BetterBlueKit Version Tests")
struct BetterBlueKitVersionTests {
    
    @Test("BetterBlueKitVersion has valid version string")
    func testVersionString() {
        let version = BetterBlueKitVersion.version
        #expect(!version.isEmpty)
        #expect(version == "1.0.1")
    }
    
    @Test("BetterBlueKitVersion has valid build date")
    func testBuildDate() {
        let buildDate = BetterBlueKitVersion.buildDate
        #expect(!buildDate.isEmpty)
        #expect(buildDate == "2025-09-16")
    }
    
    @Test("BetterBlueKitVersion description contains version and name")
    func testDescription() {
        let description = BetterBlueKitVersion.description
        #expect(description.contains("BetterBlueKit"))
        #expect(description.contains("1.0.1"))
        #expect(description.contains("Hyundai/Kia Vehicle API Library"))
        #expect(description == "BetterBlueKit v1.0.1 - Hyundai/Kia Vehicle API Library")
    }
    
    @Test("BetterBlueKitVersion static properties are consistent")
    func testStaticPropertiesConsistency() {
        let version = BetterBlueKitVersion.version
        let description = BetterBlueKitVersion.description
        
        // Version should be included in description
        #expect(description.contains(version))
    }
}