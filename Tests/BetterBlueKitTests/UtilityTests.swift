//
//  UtilityTests.swift
//  BetterBlueKit
//
//  Utility function tests
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Utility Functions Tests")
struct UtilityFunctionTests {

    // MARK: - extractNumber Tests

    @Test("extractNumber with nil value")
    func testExtractNumberWithNil() {
        let result: Int? = extractNumber(from: nil)
        #expect(result == nil)

        let doubleResult: Double? = extractNumber(from: nil)
        #expect(doubleResult == nil)
    }

    @Test("extractNumber with direct Int value")
    func testExtractNumberWithDirectInt() {
        let result: Int? = extractNumber(from: 42)
        #expect(result == 42)

        let result2: Int? = extractNumber(from: 0)
        #expect(result2 == 0)

        let result3: Int? = extractNumber(from: -100)
        #expect(result3 == -100)
    }

    @Test("extractNumber with direct Double value")
    func testExtractNumberWithDirectDouble() {
        let result: Double? = extractNumber(from: 42.5)
        #expect(result == 42.5)

        let result2: Double? = extractNumber(from: 0.0)
        #expect(result2 == 0.0)

        let result3: Double? = extractNumber(from: -3.14159)
        #expect(result3 == -3.14159)
    }

    @Test("extractNumber with string containing valid integer")
    func testExtractNumberWithValidIntegerString() {
        let result: Int? = extractNumber(from: "42")
        #expect(result == 42)

        let result2: Int? = extractNumber(from: "0")
        #expect(result2 == 0)

        let result3: Int? = extractNumber(from: "-100")
        #expect(result3 == -100)
    }

    @Test("extractNumber with string containing valid double")
    func testExtractNumberWithValidDoubleString() {
        let result: Double? = extractNumber(from: "42.5")
        #expect(result == 42.5)

        let result2: Double? = extractNumber(from: "0.0")
        #expect(result2 == 0.0)

        let result3: Double? = extractNumber(from: "-3.14159")
        #expect(result3 == -3.14159)
    }

    @Test("extractNumber with string containing invalid number")
    func testExtractNumberWithInvalidString() {
        let result: Int? = extractNumber(from: "not a number")
        #expect(result == nil)

        let result2: Double? = extractNumber(from: "abc123")
        #expect(result2 == nil)

        let result3: Int? = extractNumber(from: "")
        #expect(result3 == nil)
    }

    @Test("extractNumber with mixed type conversion")
    func testExtractNumberWithMixedTypes() {
        // Int from integer string - this will work
        let result1: Int? = extractNumber(from: "42")
        #expect(result1 == 42)

        // Double from Int - this might work depending on how Swift handles the cast
        let result2: Double? = extractNumber(from: 42)
        // This test demonstrates that the function doesn't do automatic conversion
        // It just tries to cast the value as-is
        #expect(result2 == nil) // Int(42) cannot be cast directly to Double

        // Int from Double - this also won't work
        let result3: Int? = extractNumber(from: 42.0)
        #expect(result3 == nil) // Double(42.0) cannot be cast directly to Int

        // String with decimal to Int - this will fail as expected
        let result4: Int? = extractNumber(from: "42.0")
        #expect(result4 == nil) // Int("42.0") returns nil
    }

    @Test("extractNumber with float strings")
    func testExtractNumberWithFloatStrings() {
        let result1: Float? = extractNumber(from: "3.14")
        #expect(result1 == 3.14)

        let result2: Float? = extractNumber(from: "0.001")
        #expect(result2 == 0.001)
    }

    @Test("extractNumber with edge case values")
    func testExtractNumberWithEdgeCases() {
        // Very large numbers
        let result1: Int? = extractNumber(from: "999999999")
        #expect(result1 == 999999999)

        // Very small decimal
        let result2: Double? = extractNumber(from: "0.000001")
        #expect(result2 == 0.000001)

        // Scientific notation (might not work, but let's test)
        let result3: Double? = extractNumber(from: "1e-6")
        #expect(result3 == 1e-6)
    }

    @Test("extractNumber with whitespace strings")
    func testExtractNumberWithWhitespace() {
        // Leading/trailing whitespace should not work with LosslessStringConvertible
        let result1: Int? = extractNumber(from: " 42 ")
        #expect(result1 == nil)

        let result2: Double? = extractNumber(from: "\t3.14\n")
        #expect(result2 == nil)
    }

    @Test("extractNumber with non-string, non-number types")
    func testExtractNumberWithOtherTypes() {
        let result1: Int? = extractNumber(from: true)
        #expect(result1 == nil)

        let result2: Double? = extractNumber(from: ["array"])
        #expect(result2 == nil)

        let result3: Int? = extractNumber(from: ["key": "value"])
        #expect(result3 == nil)
    }

    // MARK: - Type-specific tests for comprehensive coverage

    @Test("extractNumber works with all numeric types")
    func testExtractNumberWithAllNumericTypes() {
        // Test with Int8, Int16, Int32, Int64
        let int8Result: Int8? = extractNumber(from: "127")
        #expect(int8Result == 127)

        let int16Result: Int16? = extractNumber(from: "32767")
        #expect(int16Result == 32767)

        let int32Result: Int32? = extractNumber(from: "2147483647")
        #expect(int32Result == 2147483647)

        let int64Result: Int64? = extractNumber(from: "9223372036854775807")
        #expect(int64Result == 9223372036854775807)

        // Test with UInt variations
        let uintResult: UInt? = extractNumber(from: "42")
        #expect(uintResult == 42)

        let uint8Result: UInt8? = extractNumber(from: "255")
        #expect(uint8Result == 255)
    }
}
