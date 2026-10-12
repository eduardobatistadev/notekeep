import Foundation

public struct SearchOptions: Equatable, Sendable {
    public var pattern: String
    public var isRegex: Bool
    public var matchCase: Bool
    public var wholeWord: Bool

    public init(pattern: String, isRegex: Bool = false, matchCase: Bool = false, wholeWord: Bool = false) {
        self.pattern = pattern
        self.isRegex = isRegex
        self.matchCase = matchCase
        self.wholeWord = wholeWord
    }
}

public enum SearchError: Error, Equatable {
    case emptyPattern
    case invalidRegex(String)
}

/// Find / replace over UTF-16 ranges (the coordinate space of NSTextView).
public struct SearchEngine {
    public let options: SearchOptions
    public let regex: NSRegularExpression

    public init(options: SearchOptions) throws {
        guard !options.pattern.isEmpty else { throw SearchError.emptyPattern }
        var pattern = options.isRegex ? options.pattern : NSRegularExpression.escapedPattern(for: options.pattern)
        if options.wholeWord {
            pattern = "\\b(?:\(pattern))\\b"
        }
        var regexOptions: NSRegularExpression.Options = [.anchorsMatchLines]
        if !options.matchCase { regexOptions.insert(.caseInsensitive) }
        do {
            regex = try NSRegularExpression(pattern: pattern, options: regexOptions)
        } catch {
            throw SearchError.invalidRegex(options.pattern)
        }
        self.options = options
    }

    /// First match at or after the end of `selection`, skipping an empty match
    /// identical to the current empty selection so repeated searches advance.
    public func findNext(in text: NSString, after selection: NSRange, wrap: Bool) -> NSRange? {
        let start = NSMaxRange(selection)
        if let match = firstMatch(in: text, from: start, excluding: selection) {
            return match
        }
        guard wrap else { return nil }
        return firstMatch(in: text, from: 0, excluding: selection)
    }

    /// Last match that starts before `selection`.
    public func findPrevious(in text: NSString, before selection: NSRange, wrap: Bool) -> NSRange? {
        let all = regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)).map(\.range)
        if let match = all.last(where: { $0.location < selection.location }) {
            return match
        }
        guard wrap else { return nil }
        return all.last(where: { $0 != selection })
    }

    public func count(in text: NSString) -> Int {
        regex.numberOfMatches(in: text as String, range: NSRange(location: 0, length: text.length))
    }

    /// Whether `range` is exactly one match (used by "Replace" to decide whether
    /// the current selection may be replaced).
    public func match(exactly range: NSRange, in text: NSString) -> NSTextCheckingResult? {
        guard NSMaxRange(range) <= text.length else { return nil }
        // Match against the rest of the text, not just the selection, so a
        // greedy pattern that would extend past the selection does not count.
        let rest = NSRange(location: range.location, length: text.length - range.location)
        let result = regex.firstMatch(in: text as String, options: [.anchored, .withoutAnchoringBounds], range: rest)
        return result?.range == range ? result : nil
    }

    /// Replacement text for one match, expanding `$1`-style groups in regex mode.
    public func replacement(for match: NSTextCheckingResult, in text: NSString, with replacement: String) -> String {
        regex.replacementString(for: match, in: text as String, offset: 0, template: template(for: replacement))
    }

    public func replaceAll(in text: String, with replacement: String) -> (text: String, count: Int) {
        let mutable = NSMutableString(string: text)
        let count = regex.replaceMatches(
            in: mutable,
            range: NSRange(location: 0, length: mutable.length),
            withTemplate: template(for: replacement)
        )
        return (mutable as String, count)
    }

    /// In regex mode `\n`, `\r` and `\t` in the replacement produce control
    /// characters (as in Notepad++); other escapes keep NSRegularExpression
    /// semantics. In normal mode the replacement is literal.
    public func template(for replacement: String) -> String {
        guard options.isRegex else { return NSRegularExpression.escapedTemplate(for: replacement) }
        var result = ""
        var iterator = replacement.makeIterator()
        while let character = iterator.next() {
            guard character == "\\" else {
                result.append(character)
                continue
            }
            guard let next = iterator.next() else {
                result.append("\\\\")
                break
            }
            switch next {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            default:
                result.append("\\")
                result.append(next)
            }
        }
        return result
    }

    private func firstMatch(in text: NSString, from location: Int, excluding selection: NSRange) -> NSRange? {
        var searchFrom = location
        while searchFrom <= text.length {
            let range = NSRange(location: searchFrom, length: text.length - searchFrom)
            guard let match = regex.firstMatch(in: text as String, options: [.withoutAnchoringBounds], range: range)?.range else {
                return nil
            }
            if match.length == 0 && match == selection {
                searchFrom = match.location + 1
                continue
            }
            return match
        }
        return nil
    }
}
