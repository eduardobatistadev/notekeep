import Foundation

/// On-disk encodings the editor can read and write, mirroring Notepad++'s
/// Encoding menu.
public enum FileEncoding: String, CaseIterable, Sendable {
    case utf8
    case utf8BOM
    case utf16LE
    case utf16BE
    case windows1252
    case latin1

    public var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf8BOM: return "UTF-8 com BOM"
        case .utf16LE: return "UTF-16 LE BOM"
        case .utf16BE: return "UTF-16 BE BOM"
        case .windows1252: return "ANSI (Windows-1252)"
        case .latin1: return "ISO-8859-1 (Latin-1)"
        }
    }

    private static let utf8BOMBytes: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let utf16LEBOMBytes: [UInt8] = [0xFF, 0xFE]
    private static let utf16BEBOMBytes: [UInt8] = [0xFE, 0xFF]

    /// Detects the encoding from a BOM, then strict UTF-8, then falls back to
    /// Windows-1252 and finally Latin-1 (which decodes any byte sequence).
    public static func decode(_ data: Data) -> (text: String, encoding: FileEncoding) {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: utf8BOMBytes), let text = decode(data, as: .utf8BOM) {
            return (text, .utf8BOM)
        }
        if bytes.starts(with: utf16LEBOMBytes), let text = decode(data, as: .utf16LE) {
            return (text, .utf16LE)
        }
        if bytes.starts(with: utf16BEBOMBytes), let text = decode(data, as: .utf16BE) {
            return (text, .utf16BE)
        }
        for candidate in [FileEncoding.utf8, .windows1252] {
            if let text = decode(data, as: candidate) {
                return (text, candidate)
            }
        }
        return (decode(data, as: .latin1) ?? "", .latin1)
    }

    /// Decodes with a caller-selected encoding ("Reopen with encoding").
    /// Returns nil when the bytes are invalid for that encoding.
    public static func decode(_ data: Data, as encoding: FileEncoding) -> String? {
        switch encoding {
        case .utf8:
            return String(data: data, encoding: .utf8)
        case .utf8BOM:
            let body = data.starts(with: utf8BOMBytes) ? data.dropFirst(3) : data[...]
            return String(data: Data(body), encoding: .utf8)
        case .utf16LE:
            let body = data.starts(with: utf16LEBOMBytes) ? data.dropFirst(2) : data[...]
            return String(data: Data(body), encoding: .utf16LittleEndian)
        case .utf16BE:
            let body = data.starts(with: utf16BEBOMBytes) ? data.dropFirst(2) : data[...]
            return String(data: Data(body), encoding: .utf16BigEndian)
        case .windows1252:
            return String(data: data, encoding: .windowsCP1252)
        case .latin1:
            return String(data: data, encoding: .isoLatin1)
        }
    }

    /// Encodes without loss. Returns nil when the text contains characters the
    /// encoding cannot represent.
    public func encode(_ text: String) -> Data? {
        switch self {
        case .utf8:
            return text.data(using: .utf8)
        case .utf8BOM:
            return text.data(using: .utf8).map { Data(Self.utf8BOMBytes) + $0 }
        case .utf16LE:
            return text.data(using: .utf16LittleEndian).map { Data(Self.utf16LEBOMBytes) + $0 }
        case .utf16BE:
            return text.data(using: .utf16BigEndian).map { Data(Self.utf16BEBOMBytes) + $0 }
        case .windows1252:
            return text.data(using: .windowsCP1252, allowLossyConversion: false)
        case .latin1:
            return text.data(using: .isoLatin1, allowLossyConversion: false)
        }
    }
}
