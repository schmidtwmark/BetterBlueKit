//
//  HTTPLogging.swift
//  BetterBlueKit
//
//  HTTP logging models and types
//

import Foundation

// MARK: - HTTP Logging

public enum HTTPRequestType: String, CaseIterable, Codable, Sendable {
    case login, fetchVehicles, fetchVehicleStatus, sendCommand

    public var displayName: String {
        switch self {
        case .login: "Login"
        case .fetchVehicles: "Fetch Vehicles"
        case .fetchVehicleStatus: "Fetch Status"
        case .sendCommand: "Send Command"
        }
    }
}

public typealias HTTPLogSink = @Sendable (HTTPLog) -> Void

public struct HTTPLog: Identifiable, Codable, Sendable {
    public var id: UUID { UUID() }
    public let timestamp: Date, accountId: UUID
    public let requestType: HTTPRequestType, method: String, url: String
    public let requestHeaders: [String: String], requestBody: String?
    public let responseStatus: Int?, responseHeaders: [String: String]
    public let responseBody: String?, error: String?
    public let apiError: String?, duration: TimeInterval, stackTrace: String?

    public init(timestamp: Date, accountId: UUID, requestType: HTTPRequestType, method: String, url: String,
                requestHeaders: [String: String], requestBody: String?, responseStatus: Int?,
                responseHeaders: [String: String], responseBody: String?, error: String?,
                apiError: String? = nil, duration: TimeInterval, stackTrace: String? = nil) {
        (self.timestamp, self.accountId, self.requestType, self.method, self.url) =
            (timestamp, accountId, requestType, method, url)
        (self.requestHeaders, self.requestBody, self.responseStatus, self.responseHeaders, self.responseBody) =
            (requestHeaders, requestBody, responseStatus, responseHeaders, responseBody)
        (self.error, self.apiError, self.duration, self.stackTrace) = (error, apiError, duration, stackTrace)
    }

    public var statusText: String {
        guard let status = responseStatus else { return error != nil ? "Error" : "Pending" }
        return apiError != nil ? "\(status) (API Error)" : "\(status)"
    }

    public var isSuccess: Bool {
        guard let status = responseStatus else { return false }
        return (200 ... 299).contains(status) && error == nil && apiError == nil
    }

    public var formattedDuration: String {
        String(format: "%.2fs", duration)
    }

    public var preciseTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}
