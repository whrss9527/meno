import Foundation

/// Scores how well a query matches text, for the Quick Open palette.
///
/// Matching is case, diacritic and width insensitive. Exact and prefix
/// matches rank highest, then matches at word starts, then any ordered
/// subsequence of the query's characters.
public enum FuzzyMatcher {
    /// Returns a score where higher is better, or `nil` if there is no match.
    /// An empty query matches everything with a score of 0.
    public static func score(_ query: String, in candidate: String) -> Int? {
        let needle = Array(fold(query).filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let foldedCandidate = fold(candidate)
        let haystack = Array(foldedCandidate)
        guard !haystack.isEmpty, needle.count <= haystack.count else { return nil }

        let compactHaystack = String(haystack.filter { !$0.isWhitespace })
        let needleString = String(needle)
        if compactHaystack == needleString { return 1_000 }
        if compactHaystack.hasPrefix(needleString) {
            return 900 - min(compactHaystack.count - needle.count, 100)
        }
        if let range = foldedCandidate.range(of: needleString) {
            let offset = foldedCandidate.distance(from: foldedCandidate.startIndex, to: range.lowerBound)
            let atWordStart = offset == 0 || isSeparator(haystack[offset - 1])
            return (atWordStart ? 800 : 650) - min(offset, 100)
        }

        // Ordered subsequence with bonuses for runs and word starts.
        var score = 0
        var needleIndex = 0
        var previousMatch = -2
        var firstMatch = -1
        for (index, character) in haystack.enumerated() where needleIndex < needle.count {
            guard character == needle[needleIndex] else { continue }
            var gain = 10
            if index == previousMatch + 1 { gain += 15 }
            if index == 0 || isSeparator(haystack[index - 1]) { gain += 25 }
            score += gain
            if firstMatch < 0 { firstMatch = index }
            previousMatch = index
            needleIndex += 1
        }
        guard needleIndex == needle.count else { return nil }
        score -= min(firstMatch, 30)
        score -= (haystack.count - needle.count) / 4
        return max(1, min(score, 600))
    }

    /// The best score across several fields (name, app name, keywords…).
    public static func bestScore(_ query: String, fields: [String]) -> Int? {
        fields.compactMap { score(query, in: $0) }.max()
    }

    /// First letters of the words in `text`, for example "Control Center"
    /// → "cc" or the romanization "wei xin" → "wx".
    public static func initials(of text: String) -> String {
        var result = ""
        var atWordStart = true
        for character in fold(text) {
            if isSeparator(character) {
                atWordStart = true
            } else if atWordStart {
                result.append(character)
                atWordStart = false
            }
        }
        return result
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func isSeparator(_ character: Character) -> Bool {
        character.isWhitespace || character == "-" || character == "_" || character == "."
            || character == "/" || character == ":" || character == "(" || character == ")"
    }
}
