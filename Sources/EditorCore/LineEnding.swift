import Foundation

/// End-of-line convention. The editor keeps text normalized to LF in memory
/// and applies the document's convention when saving.
public enum LineEnding: String, CaseIterable, Sendable {
    case lf
    case crlf
    case cr

    public var displayName: String {
        switch self {
        case .lf: return "Unix (LF)"
        case .crlf: return "Windows (CR LF)"
        case .cr: return "Macintosh clássico (CR)"
        }
    }

    public var sequence: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        }
    }

    /// Picks the most frequent convention; LF when the text has no line breaks.
    public static func detect(in text: String) -> LineEnding {
        var lf = 0, crlf = 0, cr = 0
        var previousWasCR = false
        for byte in text.utf8 {
            switch byte {
            case 0x0D:
                if previousWasCR { cr += 1 }
                previousWasCR = true
            case 0x0A:
                if previousWasCR { crlf += 1 } else { lf += 1 }
                previousWasCR = false
            default:
                if previousWasCR { cr += 1 }
                previousWasCR = false
            }
        }
        if previousWasCR { cr += 1 }
        if crlf >= lf && crlf >= cr && crlf > 0 { return .crlf }
        if cr > lf { return .cr }
        return .lf
    }

    /// Converts every CR LF and lone CR to LF.
    public static func normalize(_ text: String) -> String {
        guard text.utf8.contains(0x0D) else { return text }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Converts LF-normalized text to this convention.
    public func apply(to normalizedText: String) -> String {
        self == .lf ? normalizedText : normalizedText.replacingOccurrences(of: "\n", with: sequence)
    }
}
