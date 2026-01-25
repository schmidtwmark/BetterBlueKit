//
//  BBLogger.swift
//  BetterBlueKit
//
//  Abstract logging infrastructure that can be configured with different sinks.
//  Default implementation uses print(). Apps can configure a custom sink (e.g., OSLog).
//

import Foundation

// MARK: - Log Level

public enum BBLogLevel: String, Sendable {
    case debug
    case info
    case warning
    case error

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }
}

// MARK: - Log Category

public enum BBLogCategory: String, Sendable {
    case api = "API"
    case auth = "Auth"
    case mfa = "MFA"
    case liveActivity = "LiveActivity"
    case intent = "Intent"
    case background = "Background"
    case push = "Push"
    case app = "App"
    case vehicle = "Vehicle"
    case fakeAPI = "FakeAPI"
}

// MARK: - Log Sink Protocol

/// Protocol for log sinks that receive log messages.
/// Implement this to integrate with custom logging systems (e.g., OSLog).
public protocol BBLogSink: Sendable {
    func log(level: BBLogLevel, category: BBLogCategory, message: String)
}

// MARK: - Default Print Sink

/// Default log sink that uses print() for output.
public final class BBPrintLogSink: BBLogSink, @unchecked Sendable {
    public static let shared = BBPrintLogSink()

    private init() {}

    public func log(level: BBLogLevel, category: BBLogCategory, message: String) {
        print("\(level.emoji) [\(category.rawValue)] \(message)")
    }
}

// MARK: - Global Logger

/// Global logger that delegates to a configurable sink.
/// Configure the sink at app startup to integrate with your logging system.
///
/// Usage:
/// ```swift
/// // At app startup (optional - defaults to print)
/// BBLogger.sink = MyCustomLogSink()
///
/// // Throughout code
/// BBLogger.info(.api, "Fetching vehicles")
/// BBLogger.error(.auth, "Login failed: \(error)")
/// ```
public enum BBLogger {
    /// The log sink to use. Defaults to printing to console.
    /// Set this at app startup to integrate with OSLog or other logging systems.
    nonisolated(unsafe) public static var sink: BBLogSink = BBPrintLogSink.shared

    public static func debug(_ category: BBLogCategory, _ message: String) {
        sink.log(level: .debug, category: category, message: message)
    }

    public static func info(_ category: BBLogCategory, _ message: String) {
        sink.log(level: .info, category: category, message: message)
    }

    public static func warning(_ category: BBLogCategory, _ message: String) {
        sink.log(level: .warning, category: category, message: message)
    }

    public static func error(_ category: BBLogCategory, _ message: String) {
        sink.log(level: .error, category: category, message: message)
    }
}
