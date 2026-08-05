//
//  CCSPResponseErrorTests.swift
//  BetterBlueKit
//
//  Tests for CCSP (`retCode`/`resCode`) application-level error decoding.
//  The European Hyundai/Kia API answers control commands with an HTTP 400
//  whose body carries the real reason (e.g. `resCode: "4004"` for a
//  duplicate request). These verify we translate that envelope into a typed
//  `APIError` instead of surfacing a bare "HTTP 400", mirroring Home
//  Assistant's `hyundai_kia_connect_api` `_check_response_for_errors`.
//

import Foundation
import Testing
@testable import BetterBlueKit

@MainActor
@Suite("CCSP Response Error Decoding")
struct CCSPResponseErrorTests {
    private func makeClient() -> HyundaiEuropeAPIClient {
        HyundaiEuropeAPIClient(
            configuration: APIClientConfiguration(
                region: .europe,
                brand: .hyundai,
                username: "test@example.com",
                password: "password123",
                pin: "0000",
                accountId: UUID()
            )
        )
    }

    @Test("Duplicate request (4004) maps to concurrentRequest")
    func testDuplicateRequest() {
        let body = Data(#"""
        {"msgId":"abc","resCode":"4004","resMsg":"Duplicate request","retCode":"F"}
        """#.utf8)

        #expect(throws: APIError.self) {
            try self.makeClient().checkCCSPResponseForErrors(data: body)
        }
        do {
            try makeClient().checkCCSPResponseForErrors(data: body)
        } catch let error as APIError {
            #expect(error.errorType == .concurrentRequest)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Rate limiting (5091) maps to serverError")
    func testRateLimited() {
        let body = Data(#"{"resCode":"5091","resMsg":"Exceeds number of requests","retCode":"F"}"#.utf8)
        do {
            try makeClient().checkCCSPResponseForErrors(data: body)
            Issue.record("Expected an error to be thrown")
        } catch let error as APIError {
            #expect(error.errorType == .serverError)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Unknown failure code surfaces resCode and resMsg")
    func testUnknownFailureCode() {
        let body = Data(#"{"resCode":"1234","resMsg":"Some new error","retCode":"F"}"#.utf8)
        do {
            try makeClient().checkCCSPResponseForErrors(data: body)
            Issue.record("Expected an error to be thrown")
        } catch let error as APIError {
            #expect(error.errorType == .general)
            #expect(error.message.contains("1234"))
            #expect(error.message.contains("Some new error"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Success envelope (retCode S) does not throw")
    func testSuccessEnvelope() throws {
        let body = Data(#"{"resMsg":{"vehicles":[]},"resCode":"0000","retCode":"S"}"#.utf8)
        try makeClient().checkCCSPResponseForErrors(data: body)
    }

    @Test("Non-CCSP body (no retCode) does not throw")
    func testNonCCSPBody() throws {
        // US/Canada-style error payload — must be ignored here.
        let body = Data(#"{"status":{"errorCode":1003,"errorMessage":"Session expired"}}"#.utf8)
        try makeClient().checkCCSPResponseForErrors(data: body)
    }
}
