//
//  APIClientStackTrace.swift
//  BetterBlueKit
//
//  Stack trace utilities for APIClient
//

import Foundation

// MARK: - Stack Trace Extensions

extension APIClient {
    func captureStackTrace(
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
    ) -> String {
        generateStackTrace(file: file, function: function, line: line)
    }

    private func generateStackTrace(file: String, function: String, line: Int) -> String {
        #if DEBUG
            let callSite = "🎯 HTTP Request from: \(file):\(line) in \(function)"
            let symbols = Thread.callStackSymbols
            let processedSymbols = formatStackTraceSymbols(symbols)
            return ([callSite] + processedSymbols).joined(separator: "\n")
        #else
            return "Stack traces only available in debug builds"
        #endif
    }

    private func formatStackTraceSymbols(_ symbols: [String]) -> [String] {
        symbols.enumerated().map { index, symbol in
            let frameInfo = "Frame \(index):"
            let cleanSymbol = cleanStackTraceSymbol(symbol)

            if isAppFrame(cleanSymbol) {
                return "\(frameInfo) [App] \(cleanSymbol)"
            } else if isSystemFrame(cleanSymbol) {
                return "\(frameInfo) [System] \(cleanSymbol)"
            } else {
                return "\(frameInfo) \(cleanSymbol)"
            }
        }
    }

    private func cleanStackTraceSymbol(_ symbol: String) -> String {
        symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  +", with: " +")
    }

    private func isAppFrame(_ symbol: String) -> Bool {
        symbol.contains("BetterBlue") || symbol.contains("$s")
    }

    private func isSystemFrame(_ symbol: String) -> Bool {
        symbol.contains("UIKit") ||
            symbol.contains("SwiftUI") ||
            symbol.contains("Foundation")
    }
}
