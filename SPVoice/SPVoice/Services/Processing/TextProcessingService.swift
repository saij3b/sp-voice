import Foundation
import os

/// Post-transcription text transform pipeline.
enum TextProcessingService {

    /// Common filler words/phrases to strip in polished mode.
    private static let fillerPatterns: [String] = [
        "\\bum\\b", "\\buh\\b", "\\blike\\b", "\\byou know\\b",
        "\\bactually\\b", "\\bbasically\\b", "\\bliterally\\b",
        "\\bI mean\\b", "\\bsort of\\b", "\\bkind of\\b",
    ]

    /// Process transcribed text according to the selected mode.
    static func process(_ text: String, mode: TextProcessingMode) async throws -> String {
        switch mode {
        case .rawDictation:
            return text
        case .polishedWriting:
            return polishText(text)
        case .promptMode:
            // Prompt mode requires a chat model — pass through for now.
            // A future version could route through the active provider's chat endpoint.
            Logger.transcription.info("Prompt mode — passthrough (no chat model wired)")
            return text
        case .customTransform:
            Logger.transcription.info("Custom transform — passthrough (placeholder)")
            return text
        }
    }

    // MARK: - Polished Writing

    /// Local text polishing: remove fillers, fix spacing, capitalize, ensure trailing punctuation.
    static func polishText(_ text: String) -> String {
        var result = text

        // 1. Remove filler words (case-insensitive)
        for pattern in fillerPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result), withTemplate: ""
                )
            }
        }

        // 2. Collapse multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // 3. Trim
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // 4. Capitalize first character
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }

        // 5. Ensure trailing punctuation
        if !result.isEmpty {
            let lastChar = result.last!
            if !lastChar.isPunctuation {
                result.append(".")
            }
        }

        return result
    }
}
