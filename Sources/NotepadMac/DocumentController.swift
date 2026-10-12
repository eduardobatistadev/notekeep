import AppKit

/// Opens any file as text, like Notepad++, whether or not the app runs from a
/// bundle with declared document types.
final class DocumentController: NSDocumentController {
    static let textType = "public.plain-text"

    override var defaultType: String? { Self.textType }

    override func documentClass(forType typeName: String) -> AnyClass? {
        TextDocument.self
    }

    override func typeForContents(of url: URL) throws -> String {
        Self.textType
    }

    override func displayName(forType typeName: String) -> String? {
        "Texto"
    }
}
