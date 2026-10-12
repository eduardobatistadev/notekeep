import AppKit
import EditorCore

/// NSTextView configured for code, plus the Notepad++ line commands.
final class EditorTextView: NSTextView {
    var language: Language = .plainText

    func configureForCode() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        smartInsertDeleteEnabled = false
        isIncrementalSearchingEnabled = false
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        insertionPointColor = .textColor
        textContainerInset = NSSize(width: 4, height: 4)
    }

    func applyBaseAttributes(_ attributes: [NSAttributedString.Key: Any]) {
        typingAttributes = attributes
        defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        guard let storage = textStorage else { return }
        storage.beginEditing()
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }

    /// Applies an edit as one undoable change and shows the resulting selection.
    func apply(_ edit: TextEdit) {
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: NSAttributedString(string: edit.replacement, attributes: typingAttributes))
        didChangeText()
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
    }

    private var text: NSString { string as NSString }

    private func apply(_ edit: TextEdit?, actionName: String) {
        guard let edit else {
            NSSound.beep()
            return
        }
        apply(edit)
        undoManager?.setActionName(actionName)
    }

    // MARK: Line commands (Edit menu)

    @objc func duplicateLine(_ sender: Any?) {
        apply(LineOperations.duplicateLines(in: text, selection: selectedRange()), actionName: "Duplicar linha")
    }

    @objc func deleteLine(_ sender: Any?) {
        apply(LineOperations.deleteLines(in: text, selection: selectedRange()), actionName: "Excluir linha")
    }

    @objc func moveLineUp(_ sender: Any?) {
        apply(LineOperations.moveLinesUp(in: text, selection: selectedRange()), actionName: "Mover linha")
    }

    @objc func moveLineDown(_ sender: Any?) {
        apply(LineOperations.moveLinesDown(in: text, selection: selectedRange()), actionName: "Mover linha")
    }

    @objc func toggleComment(_ sender: Any?) {
        guard let syntax = language.commentSyntax else {
            NSSound.beep()
            return
        }
        apply(LineOperations.toggleComment(in: text, selection: selectedRange(), syntax: syntax), actionName: "Comentário")
    }

    @objc func trimTrailingWhitespace(_ sender: Any?) {
        apply(LineOperations.trimTrailingWhitespace(in: text, selection: selectedRange()), actionName: "Remover espaços finais")
    }

    @objc func sortLinesAscending(_ sender: Any?) {
        apply(LineOperations.sortLines(in: text, selection: selectedRange()), actionName: "Ordenar linhas")
    }

    @objc func sortLinesDescending(_ sender: Any?) {
        apply(LineOperations.sortLines(in: text, selection: selectedRange(), descending: true), actionName: "Ordenar linhas")
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleComment(_:)) {
            return isEditable && language.commentSyntax != nil
        }
        return super.validateMenuItem(menuItem)
    }

    // Keep the caret's indentation on Return, like Notepad++'s auto-indent.
    override func insertNewline(_ sender: Any?) {
        let lineStart = text.lineRange(for: NSRange(location: selectedRange().location, length: 0)).location
        var indentEnd = lineStart
        while indentEnd < selectedRange().location, [0x20, 0x09].contains(text.character(at: indentEnd)) {
            indentEnd += 1
        }
        let indent = text.substring(with: NSRange(location: lineStart, length: indentEnd - lineStart))
        insertText("\n" + indent, replacementRange: selectedRange())
    }
}
