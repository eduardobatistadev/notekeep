import AppKit
import EditorCore

/// One open file. Owns the text storage shared by its editor; text is kept
/// LF-normalized in memory and the original encoding and line ending are
/// restored on save.
@objc(TextDocument)
final class TextDocument: NSDocument {
    let textStorage = NSTextStorage()
    private(set) var encoding: FileEncoding = .utf8
    private(set) var lineEnding: LineEnding = .lf
    var language: Language = .plainText {
        didSet { if language != oldValue { onLanguageChange?() } }
    }

    /// Set by the window controller to refresh after contents are replaced
    /// outside the text view (revert, reopen with encoding).
    var onContentsReload: (() -> Void)?
    var onLanguageChange: (() -> Void)?
    var onFormatChange: (() -> Void)?

    override init() {
        super.init()
        hasUndoManager = true
        textStorage.setAttributedString(NSAttributedString(string: "", attributes: Settings.shared.baseAttributes))
    }

    override class var autosavesInPlace: Bool { false }
    override class var readableTypes: [String] { [DocumentController.textType, "public.data"] }
    override class var writableTypes: [String] { [DocumentController.textType] }
    override class func isNativeType(_ type: String) -> Bool { true }

    override func makeWindowControllers() {
        addWindowController(EditorWindowController(document: self))
    }

    // MARK: Reading and writing

    override func read(from data: Data, ofType typeName: String) throws {
        let decoded = FileEncoding.decode(data)
        encoding = decoded.encoding
        load(decoded.text)
        language = Language.detect(fileName: fileURL?.lastPathComponent, content: textStorage.string)
    }

    override func data(ofType typeName: String) throws -> Data {
        let text = lineEnding.apply(to: textStorage.string)
        guard let data = encoding.encode(text) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInapplicableStringEncodingError, userInfo: [
                NSLocalizedDescriptionKey: "O texto contém caracteres que não podem ser salvos em \(encoding.displayName).",
                NSLocalizedRecoverySuggestionErrorKey: "Escolha Codificação ▸ UTF-8 e salve novamente.",
            ])
        }
        return data
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        return true
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil, let self, self.language == .plainText {
                // A first save as "x.py" should switch on Python highlighting.
                self.language = Language.detect(fileName: url.lastPathComponent, content: self.textStorage.string)
            }
            completionHandler(error)
        }
    }

    // MARK: Format changes

    func setEncoding(_ newEncoding: FileEncoding) {
        guard newEncoding != encoding else { return }
        let previous = encoding
        encoding = newEncoding
        undoManager?.registerUndo(withTarget: self) { $0.setEncoding(previous) }
        undoManager?.setActionName("Codificação")
        onFormatChange?()
    }

    func setLineEnding(_ newLineEnding: LineEnding) {
        guard newLineEnding != lineEnding else { return }
        let previous = lineEnding
        lineEnding = newLineEnding
        undoManager?.registerUndo(withTarget: self) { $0.setLineEnding(previous) }
        undoManager?.setActionName("Fim de linha")
        onFormatChange?()
    }

    /// Re-decodes the file on disk with a caller-chosen encoding, for files
    /// whose encoding was guessed wrong. Discards undo history.
    func reopen(with newEncoding: FileEncoding) throws {
        guard let url = fileURL else { return }
        let data = try Data(contentsOf: url)
        guard let text = FileEncoding.decode(data, as: newEncoding) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError, userInfo: [
                NSLocalizedDescriptionKey: "O arquivo não é válido em \(newEncoding.displayName).",
            ])
        }
        encoding = newEncoding
        load(text)
        undoManager?.removeAllActions()
        updateChangeCount(.changeCleared)
    }

    private func load(_ text: String) {
        lineEnding = LineEnding.detect(in: text)
        let normalized = LineEnding.normalize(text)
        textStorage.setAttributedString(NSAttributedString(string: normalized, attributes: Settings.shared.baseAttributes))
        onContentsReload?()
    }
}
