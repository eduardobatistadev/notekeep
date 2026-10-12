import Foundation

/// A single replacement plus the selection to show afterwards. Applying it as
/// one edit keeps each command a single undo step.
public struct TextEdit: Equatable, Sendable {
    public var range: NSRange
    public var replacement: String
    public var selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}

/// Notepad++-style line commands over UTF-16 ranges of LF-normalized text.
public enum LineOperations {
    /// Full lines covered by the selection. A selection ending exactly at a
    /// line start does not include that following line.
    public static func coveredLines(in text: NSString, selection: NSRange) -> NSRange {
        var end = NSMaxRange(selection)
        if selection.length > 0, end > selection.location, end <= text.length, text.character(at: end - 1) == 0x0A {
            end -= 1
        }
        let first = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let last = text.lineRange(for: NSRange(location: max(end, selection.location), length: 0))
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    public static func duplicateLines(in text: NSString, selection: NSRange) -> TextEdit {
        let lines = coveredLines(in: text, selection: selection)
        let block = text.substring(with: lines)
        let hasNewline = block.hasSuffix("\n")
        let insertion = hasNewline ? block : "\n" + block
        let shift = (block as NSString).length + (hasNewline ? 0 : 1)
        return TextEdit(
            range: NSRange(location: NSMaxRange(lines), length: 0),
            replacement: insertion,
            selection: NSRange(location: selection.location + shift, length: selection.length)
        )
    }

    public static func deleteLines(in text: NSString, selection: NSRange) -> TextEdit {
        var lines = coveredLines(in: text, selection: selection)
        let block = text.substring(with: lines)
        if !block.hasSuffix("\n"), lines.location > 0 {
            // Last line without a terminator: remove the preceding newline instead.
            lines = NSRange(location: lines.location - 1, length: lines.length + 1)
        }
        let remaining = text.replacingCharacters(in: lines, with: "") as NSString
        let caret = min(lines.location, remaining.length)
        let lineStart = remaining.lineRange(for: NSRange(location: caret, length: 0)).location
        return TextEdit(range: lines, replacement: "", selection: NSRange(location: lineStart, length: 0))
    }

    public static func moveLinesUp(in text: NSString, selection: NSRange) -> TextEdit? {
        let lines = coveredLines(in: text, selection: selection)
        guard lines.location > 0 else { return nil }
        let previous = text.lineRange(for: NSRange(location: lines.location - 1, length: 0))
        let above = text.substring(with: previous)
        let block = text.substring(with: lines)
        let replacement = block.hasSuffix("\n") ? block + above : block + "\n" + String(above.dropLast())
        return TextEdit(
            range: NSRange(location: previous.location, length: NSMaxRange(lines) - previous.location),
            replacement: replacement,
            selection: NSRange(location: selection.location - previous.length, length: selection.length)
        )
    }

    public static func moveLinesDown(in text: NSString, selection: NSRange) -> TextEdit? {
        let lines = coveredLines(in: text, selection: selection)
        guard NSMaxRange(lines) < text.length else { return nil }
        let next = text.lineRange(for: NSRange(location: NSMaxRange(lines), length: 0))
        let below = text.substring(with: next)
        let block = text.substring(with: lines)
        let replacement: String
        let shift: Int
        if below.hasSuffix("\n") {
            replacement = below + block
            shift = next.length
        } else {
            replacement = below + "\n" + String(block.dropLast())
            shift = next.length + 1
        }
        return TextEdit(
            range: NSRange(location: lines.location, length: NSMaxRange(next) - lines.location),
            replacement: replacement,
            selection: NSRange(location: selection.location + shift, length: selection.length)
        )
    }

    public static func toggleComment(in text: NSString, selection: NSRange, syntax: CommentSyntax) -> TextEdit {
        let lines = coveredLines(in: text, selection: selection)
        var block = text.substring(with: lines)
        let trailingNewline = block.hasSuffix("\n")
        if trailingNewline { block.removeLast() }

        let replacement: String
        switch syntax {
        case .line(let prefix):
            replacement = toggleLineComment(block, prefix: prefix)
        case .block(let open, let close):
            replacement = toggleBlockComment(block, open: open, close: close)
        }
        let newLength = (replacement as NSString).length
        let selectionAfter: NSRange
        if selection.length == 0 {
            let delta = newLength - (block as NSString).length
            let caret = min(max(lines.location, selection.location + delta), lines.location + newLength)
            selectionAfter = NSRange(location: caret, length: 0)
        } else {
            selectionAfter = NSRange(location: lines.location, length: newLength)
        }
        return TextEdit(
            range: NSRange(location: lines.location, length: (block as NSString).length),
            replacement: replacement,
            selection: selectionAfter
        )
    }

    private static func toggleLineComment(_ block: String, prefix: String) -> String {
        let lines = block.components(separatedBy: "\n")
        let contentLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allCommented = !contentLines.isEmpty && contentLines.allSatisfy {
            $0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix(prefix)
        }
        if allCommented {
            return lines.map { line in
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
                var rest = line.dropFirst(indent.count)
                guard rest.hasPrefix(prefix) else { return line }
                rest = rest.dropFirst(prefix.count)
                if rest.hasPrefix(" ") { rest = rest.dropFirst() }
                return String(indent) + rest
            }.joined(separator: "\n")
        }
        let indentWidth = contentLines.map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }.min() ?? 0
        return lines.map { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let index = line.index(line.startIndex, offsetBy: indentWidth)
            return String(line[..<index]) + prefix + " " + line[index...]
        }.joined(separator: "\n")
    }

    private static func toggleBlockComment(_ block: String, open: String, close: String) -> String {
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(open), trimmed.hasSuffix(close), trimmed.count >= open.count + close.count {
            var inner = String(trimmed.dropFirst(open.count).dropLast(close.count))
            if inner.hasPrefix(" ") { inner.removeFirst() }
            if inner.hasSuffix(" ") { inner.removeLast() }
            let leading = block.prefix(while: { $0 == " " || $0 == "\t" })
            return String(leading) + inner
        }
        let leading = block.prefix(while: { $0 == " " || $0 == "\t" })
        return String(leading) + open + " " + block.dropFirst(leading.count) + " " + close
    }

    public static func trimTrailingWhitespace(in text: NSString, selection: NSRange) -> TextEdit? {
        let original = text as String
        let trimmed = original.components(separatedBy: "\n").map { line -> String in
            var line = line
            while let last = line.last, last == " " || last == "\t" { line.removeLast() }
            return line
        }.joined(separator: "\n")
        guard trimmed != original else { return nil }
        let length = (trimmed as NSString).length
        return TextEdit(
            range: NSRange(location: 0, length: text.length),
            replacement: trimmed,
            selection: NSRange(location: min(selection.location, length), length: 0)
        )
    }

    /// Sorts the selected lines, or the whole document when nothing spanning
    /// more than one line is selected.
    public static func sortLines(in text: NSString, selection: NSRange, descending: Bool = false) -> TextEdit? {
        var range = coveredLines(in: text, selection: selection)
        if selection.length == 0 { range = NSRange(location: 0, length: text.length) }
        var block = text.substring(with: range)
        let trailingNewline = block.hasSuffix("\n")
        if trailingNewline { block.removeLast() }
        var lines = block.components(separatedBy: "\n")
        guard lines.count > 1 else { return nil }
        lines.sort { lhs, rhs in
            let order = lhs.localizedStandardCompare(rhs)
            return descending ? order == .orderedDescending : order == .orderedAscending
        }
        let replacement = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        return TextEdit(
            range: range,
            replacement: replacement,
            selection: NSRange(location: range.location, length: (replacement as NSString).length)
        )
    }
}
