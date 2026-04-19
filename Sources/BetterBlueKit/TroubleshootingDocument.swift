//
//  TroubleshootingDocument.swift
//  BetterBlueKit
//
//  Single-source-of-truth accessor for the bundled troubleshooting
//  markdown. The actual content lives in `Troubleshooting.md` next to
//  this file; the repo-root `Troubleshooting.md` is a symlink to the
//  same file so GitHub renders the canonical copy.
//

import Foundation

/// Accessor for the bundled troubleshooting markdown document.
///
/// Usage:
/// ```swift
/// Text(try! AttributedString(markdown: TroubleshootingDocument.markdown))
/// ```
///
/// Splitting into sections:
/// ```swift
/// for section in TroubleshootingDocument.sections {
///     // section.title, section.body
/// }
/// ```
public enum TroubleshootingDocument {
    /// The raw markdown content.
    public static let markdown: String = {
        guard
            let url = Bundle.module.url(forResource: "Troubleshooting", withExtension: "md"),
            let data = try? Data(contentsOf: url),
            let text = String(data: data, encoding: .utf8)
        else {
            return "Troubleshooting content is unavailable in this build."
        }
        return text
    }()

    /// A parsed section of the document.
    public struct Section: Identifiable, Sendable {
        public let title: String
        /// Markdown body of the section with the `##` heading stripped.
        public let body: String

        public var id: String { title }
    }

    /// Top-level H2 sections, in document order. Skips the H1 intro.
    public static let sections: [Section] = {
        let lines = markdown.components(separatedBy: .newlines)
        var sections: [Section] = []
        var currentTitle: String?
        var currentBody: [String] = []

        for line in lines {
            if line.hasPrefix("## ") {
                if let title = currentTitle {
                    sections.append(Section(
                        title: title,
                        body: currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentBody = []
            } else if currentTitle != nil {
                currentBody.append(line)
            }
        }

        if let title = currentTitle {
            sections.append(Section(
                title: title,
                body: currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        return sections
    }()
}
