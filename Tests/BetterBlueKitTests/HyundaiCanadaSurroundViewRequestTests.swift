import Foundation
import Testing
@testable import BetterBlueKit

// Each test configures the same URLProtocol fixture.
@Suite("Hyundai Canada Surround View requests", .serialized)
struct HyundaiCanadaSurroundViewRequestTests {
    private final class StubState: @unchecked Sendable {
        private let lock = NSLock()
        private var response = Data()
        private var requests: [URLRequest] = []

        func reset(response: String) {
            lock.withLock {
                self.response = Data(response.utf8)
                requests = []
            }
        }

        func respond(to request: URLRequest) -> Data {
            lock.withLock {
                requests.append(request)
                if request.url?.path.hasSuffix("/vrfypin") == true {
                    return Data(#"{"responseHeader":{"responseCode":0},"result":{"pAuth":"fixture-auth"}}"#.utf8)
                }
                return response
            }
        }

        func capturedRequests() -> [URLRequest] { lock.withLock { requests } }
    }

    private final class StubProtocol: URLProtocol, @unchecked Sendable {
        static let state = StubState()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let data = Self.state.respond(to: request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    @MainActor private func makeClient(response: String) -> HyundaiCanadaAPIClient {
        StubProtocol.state.reset(response: response)
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [StubProtocol.self]
        return HyundaiCanadaAPIClient(
            configuration: APIClientConfiguration(
                region: .canada, brand: .hyundai, username: "fixture@example.com",
                password: "fixture", pin: "1234", accountId: UUID()
            ),
            urlSession: URLSession(configuration: session)
        )
    }

    private var vehicle: Vehicle {
        Vehicle(
            vin: "TESTVIN0000000000", regId: "fixture-vehicle", model: "TUCSON",
            accountId: UUID(), fuelType: .gas, generation: 2,
            odometer: Distance(length: 0, units: .kilometers)
        )
    }

    private var token: AuthToken {
        AuthToken(accessToken: "fixture-token", refreshToken: "", expiresAt: .distantFuture)
    }

    @Test("Capture success does not require a capture list")
    @MainActor func captureWithoutLocations() async throws {
        let client = makeClient(response: #"{"responseHeader":{"responseCode":0}}"#)
        try await client.requestSurroundViewCapture(for: vehicle, authToken: token)
        #expect(StubProtocol.state.capturedRequests().last?.url?.path.hasSuffix("/rfc/fndmcrsvm") == true)
    }

    @Test("Gallery maps imagery and preserves request body and authorization")
    @MainActor func galleryRequest() async throws {
        let image = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x11, 0x11, 0xFF, 0xD9])
        let body = #"{"responseHeader":{"responseCode":0},"result":{"svmLocations":[{"utcTime":"20260826003935","svmImage":"\#(image.base64EncodedString())"}]}}"#
        let captures = try await makeClient(response: body).fetchSurroundViewCaptures(for: vehicle, authToken: token)
        let capture = try #require(captures.first)
        #expect(captures.count == 1)
        #expect(capture.frames == [image])
        let requests = StubProtocol.state.capturedRequests()
        #expect(requests.count == 2)
        let request = try #require(requests.last)
        #expect(request.url?.path.hasSuffix("/rfc/lastmcrsvm") == true)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Pauth") == "fixture-auth")
        #expect(request.value(forHTTPHeaderField: "Accesstoken") == token.accessToken)
        #expect(request.value(forHTTPHeaderField: "Vehicleid") == vehicle.regId)
        let data: Data
        if let body = request.httpBody {
            data = body
        } else {
            let stream = try #require(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 256)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                result.append(buffer, count: count)
            }
            data = result
        }
        #expect(try JSONSerialization.jsonObject(with: data) as? [String: String] == ["pin": "1234"])
    }

    @Test("HTTP 200 credential refusals reject capture and gallery", arguments: [false, true])
    @MainActor func credentialRefusal(fetch: Bool) async throws {
        let body = #"{"responseHeader":{"responseCode":1},"error":{"errorCode":7403,"errorDesc":"Token expired"}}"#
        let client = makeClient(response: body)
        do {
            if fetch {
                _ = try await client.fetchSurroundViewCaptures(for: vehicle, authToken: token)
            } else {
                try await client.requestSurroundViewCapture(for: vehicle, authToken: token)
            }
            Issue.record("Expected Canada refusal")
        } catch let error as APIError {
            #expect(error.errorType == .invalidCredentials)
        }
        #expect(throws: APIError.self) { try client.parseCanadaSurroundViewResponse(Data(body.utf8), for: vehicle) }
    }

    @Test("Malformed or missing envelopes reject both operations", arguments: ["not JSON", "{}"], [false, true])
    @MainActor func invalidEnvelope(body: String, fetch: Bool) async {
        let client = makeClient(response: body)
        do {
            if fetch {
                _ = try await client.fetchSurroundViewCaptures(for: vehicle, authToken: token)
            } else {
                try await client.requestSurroundViewCapture(for: vehicle, authToken: token)
            }
            Issue.record("Expected invalid Canada response to throw")
        } catch {
            // Both Foundation JSON errors and invalid-envelope API errors are failures.
        }
    }
}
