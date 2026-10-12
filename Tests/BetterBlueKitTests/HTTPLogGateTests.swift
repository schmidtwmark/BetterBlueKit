import Foundation
import Testing
@testable import BetterBlueKit

@Suite("HTTP log preparation gate")
struct HTTPLogGateTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var logs: [HTTPLog] = []
        func append(_ log: HTTPLog) { lock.withLock { logs.append(log) } }
        func capturedLogs() -> [HTTPLog] { lock.withLock { logs } }
    }

    @MainActor private final class Gate {
        var enabled = false
    }

    private final class StubProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: request.url?.path == "/unauthorized" ? 401 : 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"result":"fixture"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    @MainActor private func configuration(_ recorder: Recorder) -> APIClientConfiguration {
        APIClientConfiguration(
            region: .usa, brand: .hyundai, username: "fixture@example.com",
            password: "fixture", pin: "1234", accountId: UUID(),
            logSink: { recorder.append($0) }
        )
    }

    @Test("Logging stays enabled by default and retains privacy processing")
    @MainActor func defaultLogging() async throws {
        let recorder = Recorder()
        let client = APIClientBase(configuration: configuration(recorder), urlSession: session())
        _ = try await client.performRequest(
            url: "https://fixture.invalid/ok", headers: ["Authorization": "Bearer fixture-secret"],
            requestType: .fetchVehicles
        )
        let logs = recorder.capturedLogs()
        #expect(logs.count == 1)
        let log = try #require(logs.first)
        #expect(log.requestHeaders["Authorization"] != nil)
        #expect(log.requestHeaders["Authorization"] != "Bearer fixture-secret")
        #expect(log.stackTrace?.isEmpty == false)
        #expect(log.responseStatus == 200)
    }

    @Test("Live gate survives device and token configuration copies")
    @MainActor func liveGateAndCopies() async throws {
        let recorder = Recorder()
        let gate = Gate()
        let configuration = APIClientConfiguration(
            region: .usa, brand: .hyundai, username: "fixture@example.com",
            password: "fixture", pin: "1234", accountId: UUID(),
            logSink: { recorder.append($0) }, shouldLogHTTPRequest: { gate.enabled }
        )
        let client = APIClientBase(configuration: configuration, urlSession: session())
        _ = try await client.performRequest(url: "https://fixture.invalid/ok", requestType: .fetchVehicles)
        #expect(recorder.capturedLogs().isEmpty)

        gate.enabled = true
        _ = try await client.performRequest(url: "https://fixture.invalid/ok", requestType: .fetchVehicles)
        #expect(recorder.capturedLogs().count == 1)

        gate.enabled = false
        client.configuration = client.configuration.with(deviceId: "new-device").with(refreshToken: "new-token")
        _ = try await client.performRequest(url: "https://fixture.invalid/ok", requestType: .fetchVehicles)
        #expect(recorder.capturedLogs().count == 1)

        do {
            _ = try await client.performRequest(url: "https://fixture.invalid/unauthorized", requestType: .fetchVehicles)
            Issue.record("Disabled logging must not bypass HTTP validation")
        } catch let error as APIError {
            #expect(error.errorType == .invalidCredentials)
        }
        #expect(recorder.capturedLogs().count == 1)
    }
}
