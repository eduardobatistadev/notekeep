import Foundation

public struct SyntaxToken: Equatable, Sendable {
    public let range: NSRange
    public let kind: TokenKind
}

/// Scans text left to right with one combined regular expression per
/// language, so a comment marker inside a string (or vice versa) is classified
/// by whichever construct starts first.
public final class SyntaxTokenizer: @unchecked Sendable {
    public let language: Language
    private let regex: NSRegularExpression?
    private let kinds: [TokenKind]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Language: SyntaxTokenizer] = [:]

    public static func forLanguage(_ language: Language) -> SyntaxTokenizer {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[language] { return cached }
        let tokenizer = SyntaxTokenizer(language: language)
        cache[language] = tokenizer
        return tokenizer
    }

    init(language: Language) {
        self.language = language
        let rules = language.rules
        kinds = rules.map(\.kind)
        if rules.isEmpty {
            regex = nil
        } else {
            let pattern = rules.map { "(\($0.pattern))" }.joined(separator: "|")
            regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
    }

    /// Number of capture groups in the combined pattern; equals the rule count
    /// when every rule follows the no-capturing-groups contract.
    public var captureGroupCount: Int { regex?.numberOfCaptureGroups ?? 0 }
    public var isValid: Bool { language.rules.isEmpty || regex != nil }

    public func tokens(in text: NSString, range: NSRange? = nil) -> [SyntaxToken] {
        guard let regex else { return [] }
        let searchRange = range ?? NSRange(location: 0, length: text.length)
        var result: [SyntaxToken] = []
        regex.enumerateMatches(in: text as String, options: [], range: searchRange) { match, _, _ in
            guard let match, match.range.length > 0 else { return }
            for index in 0..<kinds.count where match.range(at: index + 1).location != NSNotFound {
                result.append(SyntaxToken(range: match.range, kind: kinds[index]))
                return
            }
        }
        return result
    }
}
