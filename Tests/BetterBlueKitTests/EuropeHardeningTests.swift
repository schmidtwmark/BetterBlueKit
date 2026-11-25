import Foundation
import os
import Testing
@testable import BetterBlueKit

@MainActor
@Suite("Europe CCSP hardening", .serialized)
struct EuropeHardeningTests {
    private struct Reply: Sendable {
        var status = 200
        var body = "{}"
        var error: URLError.Code?
        var delay: TimeInterval = 0
    }

    private final class StubProtocol: URLProtocol, @unchecked Sendable {
        struct State {
            var replies: [String: Reply] = [:]
            var paths: [String] = []
            var onRequest: (@Sendable (String) -> Void)?
            var refreshHold: DispatchSemaphore?
        }

        static let state = OSAllocatedUnfairLock(initialState: State())

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let url = request.url!
            let (reply, onRequest, refreshHold) = Self.state.withLock { state in
                state.paths.append(url.path)
                return (state.replies[url.path] ?? Reply(status: 418), state.onRequest, state.refreshHold)
            }
            onRequest?(url.path)
            if url.path == "/auth/v2/token-refresh" {
                _ = refreshHold?.wait(timeout: .now() + 3)
            }
            if reply.delay > 0 { Thread.sleep(forTimeInterval: reply.delay) }
            if let error = reply.error {
                client?.urlProtocol(self, didFailWithError: URLError(error))
                return
            }
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private final class MessageSink: BBLogSink {
        let messages = OSAllocatedUnfairLock(initialState: [String]())

        func log(level: BBLogLevel, category: BBLogCategory, message: String) {
            messages.withLock { $0.append(message) }
        }
    }

    private let refreshPath = "/auth/v2/token-refresh"
    private let exchangePath = "/auth/v1/token-exchange"
    private let pinPath = "/api/v1/user/pin"

    private static let storedCCI = CCITokenSet(
        accessToken: "old-access", refreshToken: "old-refresh",
        exchangeableAccessToken: "old-exchange", exchangeableRefreshToken: "old-exchange-refresh",
        nonCcsToken: "old-non-ccs", nonCcsRefreshToken: "old-non-ccs-refresh", idToken: "old-id"
    ).encodeForStorage()

    private func makeClient(
        brand: Brand = .kia, accountId: UUID = UUID(), refreshToken: String? = nil,
        password: String = "", deviceId: String? = "synthetic-device",
        redactPII: Bool = true, logSink: HTTPLogSink? = nil
    ) -> any EuropeCCSPClient {
        let configuration = APIClientConfiguration(
            region: .europe, brand: brand, username: "test@example.com", password: password,
            refreshToken: refreshToken, pin: "1234", accountId: accountId, logSink: logSink, redactPII: redactPII, deviceId: deviceId
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        if brand == .kia {
            return KiaEuropeAPIClient(configuration: configuration, urlSession: session)
        }
        return HyundaiEuropeAPIClient(configuration: configuration, urlSession: session)
    }

    private func stub(_ replies: [String: Reply]) {
        StubProtocol.state.withLock { $0 = .init(replies: replies) }
    }

    private var paths: [String] { StubProtocol.state.withLock { $0.paths } }

    private func vehicle(for client: any EuropeCCSPClient, ccs2: Bool = true) -> Vehicle {
        Vehicle(
            vin: "SYNTHETICVIN", regId: "ev", model: "Test EV", accountId: client.accountId,
            fuelType: .electric, generation: 1, odometer: .init(length: 0, units: .kilometers),
            marketOptions: client.brand == .kia ? .kiaEurope(ccs2Supported: ccs2) : .hyundaiEurope(ccs2Supported: ccs2)
        )
    }

    private var authToken: AuthToken {
        AuthToken(accessToken: "synthetic-access", refreshToken: "", expiresAt: .distantFuture)
    }

    @Test func credentialsStayOutOfBothLogSinks() async throws {
        let legacySecret = "synthetic-legacy-refresh"
        let controlSecret = "synthetic-control-token"
        let codeSecret = "synthetic-oauth-code"
        let legacyPath = "/auth/api/v2/user/oauth2/token"
        let codePath = "/auth/v1/token"
        stub([
            legacyPath: Reply(body: #"{"access_token":"fresh","expires_in":3600}"#),
            pinPath: Reply(body: #"{"controlToken":"synthetic-control-token","expiresTime":600}"#),
            "/api/v2/spa/vehicles/ev/ccs2/control/door": Reply(),
            codePath: Reply()
        ])

        let httpLogs = OSAllocatedUnfairLock(initialState: [HTTPLog]())
        let client = makeClient(refreshToken: legacySecret) { log in httpLogs.withLock { $0.append(log) } }
        let messageSink = MessageSink()
        let previousSink = BBLogger.sink
        BBLogger.sink = messageSink
        defer { BBLogger.sink = previousSink }

        _ = try await client.login()
        try await client.sendCommand(for: vehicle(for: client), command: .lock, authToken: authToken)
        _ = try await client.performRequest(
            url: "https://synthetic.invalid\(codePath)?code=\(codeSecret)", method: .POST, requestType: .login
        )

        let logs = httpLogs.withLock { $0 }
        let legacyLog = try #require(logs.first { $0.url.hasSuffix(legacyPath) })
        let pinLog = try #require(logs.first { $0.url.contains(pinPath) })
        let codeLog = try #require(logs.first { $0.url.contains(codePath + "?") })
        #expect(legacyLog.requestBody?.contains("refresh_token=[REDACTED]") == true)
        #expect(legacyLog.requestBody?.contains("client_secret=[REDACTED]") == true)
        #expect(pinLog.responseBody?.contains(#""controlToken":"[REDACTED]""#) == true)
        #expect(codeLog.url.contains("code=[REDACTED]"))
        let serializedLogs = String(decoding: try JSONEncoder().encode(logs), as: UTF8.self)
        let messages = messageSink.messages.withLock { $0.joined(separator: "\n") }
        #expect(messages.contains(codePath))
        for secret in [legacySecret, controlSecret, codeSecret] {
            #expect(!serializedLogs.contains(secret))
            #expect(!messages.contains(secret))
        }
    }

    @Test func simultaneousLoginsShareCCIRefreshAcrossClients() async throws {
        stub([
            refreshPath: Reply(body: #"{"accessToken":"rotated-cci","refreshToken":"rotated-refresh"}"#, delay: 0.1),
            exchangePath: Reply(body: #"{"accessToken":"new-ccs","expiresTime":3600}"#)
        ])
        let accountId = UUID()
        let first = makeClient(accountId: accountId, refreshToken: Self.storedCCI)
        let second = makeClient(accountId: accountId, refreshToken: Self.storedCCI)
        async let firstLogin = first.login()
        async let secondLogin = second.login()
        let (firstToken, secondToken) = try await (firstLogin, secondLogin)
        #expect(paths == [refreshPath, exchangePath])
        #expect(firstToken.accessToken == "new-ccs")
        #expect(firstToken.accessToken == secondToken.accessToken)
        #expect(firstToken.expiresAt == secondToken.expiresAt)
        #expect(firstToken.refreshToken == secondToken.refreshToken)
        #expect(CCITokenSet.decodeFromStorage(firstToken.refreshToken)?.refreshToken == "rotated-refresh")
        #expect(first.configuration.refreshToken == firstToken.refreshToken)
        #expect(second.configuration.refreshToken == secondToken.refreshToken)
    }

    @Test func cancellingCallerDoesNotDiscardInFlightRotation() async throws {
        stub([
            refreshPath: Reply(body: #"{"accessToken":"rotated-cci","refreshToken":"rotated-refresh"}"#),
            exchangePath: Reply(body: #"{"accessToken":"new-ccs","expiresTime":3600}"#)
        ])
        let (requests, signal) = AsyncStream.makeStream(of: String.self)
        let releaseRefresh = DispatchSemaphore(value: 0)
        StubProtocol.state.withLock {
            $0.onRequest = { signal.yield($0) }
            $0.refreshHold = releaseRefresh
        }
        defer { signal.finish() }

        let accountId = UUID()
        let client = makeClient(accountId: accountId, refreshToken: Self.storedCCI, password: "synthetic-password")
        let cancelled = Task { try await client.login() }
        var requestIterator = requests.makeAsyncIterator()
        #expect(await requestIterator.next() == refreshPath)
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(paths == [refreshPath])

        let otherClient = makeClient(accountId: accountId, refreshToken: Self.storedCCI)
        let otherLogin = Task { try await otherClient.login() }
        await Task.yield()
        releaseRefresh.signal()
        let token = try await otherLogin.value
        #expect(token.accessToken == "new-ccs")
        #expect(paths == [refreshPath, exchangePath])
        #expect(client.configuration.refreshToken == token.refreshToken)
    }

    @Test(arguments: [401, 400])
    func rejectedRefreshCanStillFallBackToPassword(status: Int) async {
        let authorizePath = "/auth/api/v2/user/oauth2/authorize"
        stub([
            refreshPath: Reply(status: status, body: #"{"code":9030,"message":"Token expired"}"#),
            authorizePath: Reply(status: 503)
        ])
        let client = makeClient(refreshToken: Self.storedCCI, password: "synthetic-password")
        await #expect(throws: APIError.self) { try await client.login() }
        #expect(paths == [refreshPath, authorizePath])
    }

    @Test func olderTokenCannotBlockRefreshOfNewerToken() async throws {
        stub([
            refreshPath: Reply(status: 401),
            exchangePath: Reply(body: #"{"accessToken":"new-ccs"}"#)
        ])
        let (requests, signal) = AsyncStream.makeStream(of: String.self)
        let releaseRefresh = DispatchSemaphore(value: 0)
        StubProtocol.state.withLock {
            $0.onRequest = { signal.yield($0) }
            $0.refreshHold = releaseRefresh
        }
        defer { signal.finish() }
        let accountId = UUID()
        var newerSet = try #require(CCITokenSet.decodeFromStorage(Self.storedCCI))
        newerSet.refreshToken = "newer-refresh"
        let oldClient = makeClient(accountId: accountId, refreshToken: Self.storedCCI)
        let newClient = makeClient(accountId: accountId, refreshToken: newerSet.encodeForStorage())
        let oldLogin = Task { try await oldClient.login() }
        var iterator = requests.makeAsyncIterator()
        #expect(await iterator.next() == refreshPath)
        StubProtocol.state.withLock {
            $0.refreshHold = nil
            $0.replies[refreshPath] = Reply(body: #"{"accessToken":"rotated-cci","refreshToken":"rotated-refresh"}"#)
        }
        let newLogin = Task { try await newClient.login() }
        await Task.yield()
        releaseRefresh.signal()
        let oldError = await #expect(throws: APIError.self) { try await oldLogin.value }
        #expect(oldError?.errorType == .invalidCredentials)
        let newToken = try await newLogin.value
        #expect(newToken.accessToken == "new-ccs")
        #expect(paths == [refreshPath, refreshPath, exchangePath])
    }

    @Test func exchange503PreservesRotationForAllWaitingClients() async throws {
        stub([
            refreshPath: Reply(body: #"{"accessToken":"rotated-cci","refreshToken":"rotated-refresh"}"#, delay: 0.1),
            exchangePath: Reply(status: 503)
        ])
        let accountId = UUID()
        let first = makeClient(accountId: accountId, refreshToken: Self.storedCCI, password: "synthetic-password")
        let retryLogs = OSAllocatedUnfairLock(initialState: [HTTPLog]())
        let second = makeClient(
            accountId: accountId, refreshToken: Self.storedCCI, password: "synthetic-password", redactPII: false
        ) { log in retryLogs.withLock { $0.append(log) } }
        let firstLogin = Task { try await first.login() }
        let secondLogin = Task { try await second.login() }
        for login in [firstLogin, secondLogin] {
            let error = await #expect(throws: APIError.self) { try await login.value }
            #expect(error?.errorType == .serverError)
        }
        #expect(paths == [refreshPath, exchangePath])
        for client in [first, second] {
            let stored = try #require(client.configuration.refreshToken)
            #expect(CCITokenSet.decodeFromStorage(stored)?.refreshToken == "rotated-refresh")
        }

        stub([
            refreshPath: Reply(body: #"{"accessToken":"latest-cci","refreshToken":"latest-refresh"}"#),
            exchangePath: Reply(body: #"{"accessToken":"new-ccs"}"#)
        ])
        let token = try await second.login()
        #expect(token.accessToken == "new-ccs")
        #expect(paths == [refreshPath, exchangePath])
        let sent = try #require(retryLogs.withLock { logs in
            logs.last { $0.url.hasSuffix(refreshPath) }?.requestBody
        })
        let fields = try JSONDecoder().decode([String: String].self, from: Data(sent.utf8))
        #expect(fields["refreshToken"] == "rotated-refresh")
    }

    @Test(arguments: [401, 502])
    func errorResponseRedactsControlTokenInBothLogSinks(status: Int) async throws {
        let secret = "synthetic-error-control-token"
        stub([pinPath: Reply(status: status, body: #"{"controlToken":"synthetic-error-control-token"}"#)])
        let httpLogs = OSAllocatedUnfairLock(initialState: [HTTPLog]())
        let client = makeClient { log in httpLogs.withLock { $0.append(log) } }
        let messageSink = MessageSink()
        let previousSink = BBLogger.sink
        BBLogger.sink = messageSink
        defer { BBLogger.sink = previousSink }
        let error = await #expect(throws: APIError.self) {
            try await client.sendCommand(for: vehicle(for: client), command: .lock, authToken: authToken)
        }
        #expect(error?.errorType == (status == 401 ? .invalidCredentials : .serverError))
        #expect(error?.message.contains(secret) == false)
        let log = try #require(httpLogs.withLock { $0.first })
        #expect(log.responseStatus == status)
        #expect(log.responseBody?.contains(#""controlToken":"[REDACTED]""#) == true)
        let messages = messageSink.messages.withLock { $0.joined(separator: "\n") }
        #expect(messages.contains("Response \(status)"))
        #expect(!messages.contains(secret))
    }

    @Test func unavailableRefreshDoesNotAttemptPasswordLogin() async {
        stub([refreshPath: Reply(status: 503)])
        let client = makeClient(refreshToken: Self.storedCCI, password: "synthetic-password")
        let error = await #expect(throws: APIError.self) { try await client.login() }
        #expect(error?.errorType == .serverError)
        #expect(paths == [refreshPath])
        #expect(client.configuration.refreshToken == Self.storedCCI)
    }

    @Test(arguments: [URLError.cancelled, URLError.notConnectedToInternet])
    func refreshTransportFailureDoesNotAttemptPasswordLogin(code: URLError.Code) async {
        stub([refreshPath: Reply(error: code)])
        let client = makeClient(refreshToken: Self.storedCCI, password: "synthetic-password")
        if code == .cancelled {
            await #expect(throws: CancellationError.self) { try await client.login() }
        } else {
            await #expect(throws: APIError.self) { try await client.login() }
        }
        #expect(paths == [refreshPath])
        #expect(client.configuration.refreshToken == Self.storedCCI)
    }

    @Test(arguments: [Brand.kia, .hyundai])
    func rejectsMissingStatusNode(brand: Brand) throws {
        let client = makeClient(brand: brand)
        for ccs2 in [false, true] {
            #expect(throws: APIError.self) {
                try client.parseVehicleStatusResponse(
                    Data(#"{"resMsg":{}}"#.utf8), nil, for: vehicle(for: client, ccs2: ccs2)
                )
            }
        }
    }

    private func ccs2Status(for client: any EuropeCCSPClient, chargingState: Int) throws -> VehicleStatus {
        let fixture = """
        {"resMsg":{"lastUpdateTime":1747800000123,"state":{"Vehicle":{"Green":{"ChargingInformation":{
            "Charging":{"State":\(chargingState),"RemainTime":30},
            "ConnectorFastening":{"State":1},
            "TargetSoC":{"Standard":80,"Quick":90}
        }}}}}}
        """
        return try client.parseVehicleStatusResponse(Data(fixture.utf8), nil, for: vehicle(for: client))
    }

    @Test(arguments: [Brand.kia, .hyundai])
    func ccs2UsesTimestampAndExplicitChargingState(brand: Brand) throws {
        let client = makeClient(brand: brand)
        let status = try ccs2Status(for: client, chargingState: 0)
        #expect(status.syncDate == Date(timeIntervalSince1970: 1_747_800_000.123))
        #expect(status.evStatus?.charging == false)
    }

    @Test(arguments: [Brand.kia, .hyundai])
    func ccs2DoesNotInferActiveTargetFromConnectorState(brand: Brand) throws {
        let status = try ccs2Status(for: makeClient(brand: brand), chargingState: 1)
        let ev = try #require(status.evStatus)
        #expect(ev.charging)
        #expect(ev.pluggedIn)
        #expect(ev.targetSocAC == 80)
        #expect(ev.targetSocDC == 90)
        #expect(ev.currentTargetSOC == nil)
        #expect(ev.knownPlugType == nil)
        let restored = try JSONDecoder().decode(VehicleStatus.EVStatus.self, from: JSONEncoder().encode(ev))
        #expect(restored.pluggedIn)
        #expect(restored.knownPlugType == nil)
        #expect(restored.currentTargetSOC == nil)
    }

    @Test(arguments: [#""resCode":"4004","#, #""resCode":4004,"#, ""])
    func explicitCCSPFailureCannotSucceed(codeField: String) {
        let client = makeClient()
        let body = Data("{\(codeField)\"retCode\":\"F\"}".utf8)
        let error = #expect(throws: APIError.self) { try client.checkCCSPResponseForErrors(data: body) }
        #expect(error?.errorType == (codeField.isEmpty ? .general : .concurrentRequest))
    }

    @Test(arguments: [nil as String?, ""])
    func missingDeviceIdStopsPINExchangeBeforeHTTP(deviceId: String?) async {
        stub([:])
        let client = makeClient(deviceId: deviceId)
        client.commandToken = "old-command-token"
        client.commandTokenExpiration = .distantFuture
        let error = await #expect(throws: APIError.self) {
            try await client.sendCommand(for: vehicle(for: client), command: .lock, authToken: authToken)
        }
        #expect(error?.message.contains("device ID") == true)
        #expect(paths.isEmpty)
    }

    @Test(arguments: ["{}", #"{"controlToken":"synthetic-control-token"}"#, #"{"expiresTime":600}"#,
                      #"{"controlToken":"synthetic-control-token","expiresTime":true}"#])
    func malformedPINResponseIsAProtocolError(body: String) async {
        stub([pinPath: Reply(body: body)])
        let client = makeClient()
        let error = await #expect(throws: APIError.self) {
            try await client.sendCommand(for: vehicle(for: client), command: .lock, authToken: authToken)
        }
        #expect(error?.errorType == .general)
        #expect(error?.message.contains("Invalid PIN verification response") == true)
        #expect(paths == [pinPath])
    }

    @Test func explicitPINRejectionPreservesServiceError() async {
        stub([pinPath: Reply(status: 400, body: #"{"retCode":"F","resCode":"1234","resMsg":"PIN rejected"}"#)])
        let client = makeClient()
        let error = await #expect(throws: APIError.self) {
            try await client.sendCommand(for: vehicle(for: client), command: .lock, authToken: authToken)
        }
        #expect(error?.message.contains("PIN rejected") == true)
        #expect(paths == [pinPath])
    }
}
