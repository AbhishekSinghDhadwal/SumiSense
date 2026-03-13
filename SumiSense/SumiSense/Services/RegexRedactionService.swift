import Foundation

final class RegexRedactionService: RedactionService {
    func redact(text: String, mode: ShareMode) async throws -> RedactionResult {
        var transformed = text
        var applied: [String] = []

        transformed = replace(pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", in: transformed, with: "[Email]", options: [.caseInsensitive], applied: &applied, label: "email")
        transformed = replace(pattern: "(?<!\\d)(?:\\+1[-.\\s]?)?(?:\\(?\\d{3}\\)?[-.\\s]?)\\d{3}[-.\\s]?\\d{4}(?!\\d)", in: transformed, with: "[Phone]", options: [], applied: &applied, label: "phone")
        transformed = replace(pattern: "\\b(?:MRN|ID|Case|Record)[:#]?\\s*[A-Z0-9-]{4,}\\b", in: transformed, with: "[Identifier]", options: [.caseInsensitive], applied: &applied, label: "id")

        if mode != .personal {
            transformed = replace(pattern: "\\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\\s+\\d{1,2}(?:,\\s*\\d{2,4})?\\b", in: transformed, with: "[Date]", options: [.caseInsensitive], applied: &applied, label: "date")
            transformed = replace(pattern: "\\b\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4}\\b", in: transformed, with: "[Date]", options: [], applied: &applied, label: "date")
        }

        if mode == .researchSafe {
            transformed = replace(pattern: "\\bDr\\.?\\s+[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)?\\b", in: transformed, with: "[Provider]", options: [], applied: &applied, label: "provider")
            transformed = replace(pattern: "\\b[A-Z][a-z]+\\s+[A-Z][a-z]+\\b", in: transformed, with: "[Person]", options: [], applied: &applied, label: "name")
            transformed = replace(pattern: "\\b\\d{1,5}\\s+[A-Za-z0-9.\\s]+(?:Street|St|Avenue|Ave|Road|Rd|Drive|Dr|Lane|Ln|Boulevard|Blvd)\\b", in: transformed, with: "[Address]", options: [.caseInsensitive], applied: &applied, label: "address")
            transformed = replace(pattern: "\\b(?:Tempe|Phoenix|Scottsdale|Mesa|Chandler|Gilbert|clinic|hospital|center|park|studio)\\b", in: transformed, with: "[Location]", options: [.caseInsensitive], applied: &applied, label: "location")
        }

        transformed = modeSpecificTransform(text: transformed, mode: mode)

        return RedactionResult(
            mode: mode,
            sourceText: text,
            outputText: transformed,
            redactionsApplied: Array(NSOrderedSet(array: applied).compactMap { $0 as? String }),
            source: .fallback
        )
    }

    private func modeSpecificTransform(text: String, mode: ShareMode) -> String {
        switch mode {
        case .personal:
            return text
        case .clinician:
            return "Clinician summary: \(text)"
        case .researchSafe:
            return "Research-safe summary: \(text)"
        }
    }

    private func replace(
        pattern: String,
        in text: String,
        with replacement: String,
        options: NSRegularExpression.Options,
        applied: inout [String],
        label: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return text }

        applied.append(label)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}
