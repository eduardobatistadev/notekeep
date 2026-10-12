import AppKit
import EditorCore

/// Notepad++-style Find/Replace panel with regex, case, whole-word and
/// wrap-around options. Acts on the frontmost editor window.
final class FindPanelController: NSWindowController {
    static let shared = FindPanelController()

    private let findField = NSTextField()
    private let replaceField = NSTextField()
    private let regexBox = NSButton(checkboxWithTitle: "Expressão regular", target: nil, action: nil)
    private let matchCaseBox = NSButton(checkboxWithTitle: "Diferenciar maiúsculas", target: nil, action: nil)
    private let wholeWordBox = NSButton(checkboxWithTitle: "Palavra inteira", target: nil, action: nil)
    private let wrapBox = NSButton(checkboxWithTitle: "Voltar ao início", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 200),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        panel.title = "Localizar e substituir"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = false
        super.init(window: panel)
        buildLayout()
        panel.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private var editor: EditorWindowController? {
        NSApp.mainWindow?.windowController as? EditorWindowController
    }

    private func buildLayout() {
        guard let contentView = window?.contentView else { return }
        wrapBox.state = .on
        findField.placeholderString = "Localizar"
        replaceField.placeholderString = "Substituir por ($1, \\n, \\t no modo regex)"
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        findField.target = self
        findField.action = #selector(findNext(_:))

        func button(_ title: String, _ action: Selector) -> NSButton {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            return button
        }
        let findNextButton = button("Localizar próximo", #selector(findNext(_:)))
        findNextButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [
            findNextButton,
            button("Anterior", #selector(findPrevious(_:))),
            button("Contar", #selector(countMatches(_:))),
            button("Substituir", #selector(replace(_:))),
            button("Substituir tudo", #selector(replaceAll(_:))),
        ])
        buttons.spacing = 6

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Localizar:"), findField],
            [NSTextField(labelWithString: "Substituir:"), replaceField],
            [NSGridCell.emptyContentView, NSStackView(views: [regexBox, matchCaseBox, wholeWordBox, wrapBox])],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 8

        let stack = NSStackView(views: [grid, buttons, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 380),
        ])
    }

    func show() {
        if let editor {
            let selection = editor.textView.selectedRange()
            if selection.length > 0, selection.length < 200 {
                findField.stringValue = (editor.textView.string as NSString).substring(with: selection)
            }
        }
        showWindow(nil)
        window?.makeFirstResponder(findField)
    }

    func setSearchText(_ text: String) {
        findField.stringValue = text
        statusLabel.stringValue = ""
    }

    private func makeEngine() -> SearchEngine? {
        let options = SearchOptions(
            pattern: findField.stringValue,
            isRegex: regexBox.state == .on,
            matchCase: matchCaseBox.state == .on,
            wholeWord: wholeWordBox.state == .on
        )
        do {
            return try SearchEngine(options: options)
        } catch SearchError.invalidRegex {
            report("Expressão regular inválida.", beep: true)
        } catch {
            report("Digite o texto a localizar.", beep: true)
            show()
        }
        return nil
    }

    private func report(_ message: String, beep: Bool = false) {
        statusLabel.stringValue = message
        if beep { NSSound.beep() }
    }

    @discardableResult
    private func find(backwards: Bool) -> Bool {
        guard let editor, let engine = makeEngine() else { return false }
        let textView = editor.textView
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let wrap = wrapBox.state == .on
        let found = backwards
            ? engine.findPrevious(in: text, before: selection, wrap: wrap)
            : engine.findNext(in: text, after: selection, wrap: wrap)
        guard let found else {
            report("Não encontrado: \"\(findField.stringValue)\"", beep: true)
            return false
        }
        textView.setSelectedRange(found)
        textView.scrollRangeToVisible(found)
        textView.showFindIndicator(for: found)
        report("")
        return true
    }

    @objc func findNext(_ sender: Any?) {
        find(backwards: false)
    }

    @objc func findPrevious(_ sender: Any?) {
        find(backwards: true)
    }

    @objc func countMatches(_ sender: Any?) {
        guard let editor, let engine = makeEngine() else { return }
        let count = engine.count(in: editor.textView.string as NSString)
        report(count == 1 ? "1 ocorrência." : "\(count) ocorrências.")
    }

    @objc func replace(_ sender: Any?) {
        guard let editor, let engine = makeEngine() else { return }
        let textView = editor.textView
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        if let match = engine.match(exactly: selection, in: text) {
            let replacement = engine.replacement(for: match, in: text, with: replaceField.stringValue)
            let replacedLength = (replacement as NSString).length
            textView.apply(TextEdit(
                range: selection,
                replacement: replacement,
                selection: NSRange(location: selection.location + replacedLength, length: 0)
            ))
            textView.undoManager?.setActionName("Substituir")
        }
        find(backwards: false)
    }

    @objc func replaceAll(_ sender: Any?) {
        guard let editor, let engine = makeEngine() else { return }
        let textView = editor.textView
        let result = engine.replaceAll(in: textView.string, with: replaceField.stringValue)
        guard result.count > 0 else {
            report("Nenhuma ocorrência.", beep: true)
            return
        }
        let caret = min(textView.selectedRange().location, (result.text as NSString).length)
        textView.apply(TextEdit(
            range: NSRange(location: 0, length: (textView.string as NSString).length),
            replacement: result.text,
            selection: NSRange(location: caret, length: 0)
        ))
        textView.undoManager?.setActionName("Substituir tudo")
        report(result.count == 1 ? "1 substituição." : "\(result.count) substituições.")
    }
}
