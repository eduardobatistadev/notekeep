import AppKit
import EditorCore

/// One editor window (or tab): text view, line-number gutter, syntax colors
/// and status bar, plus the document-level menu commands.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSMenuItemValidation {
    /// Files above this size are shown without syntax colors to stay responsive.
    private static let highlightLimit = 4_000_000

    let textView: EditorTextView
    private let scrollView = NSScrollView()
    private let ruler: LineNumberRulerView
    private let statusLabels = (0..<5).map { _ in NSTextField(labelWithString: "") }
    private var lineIndex = LineIndex(text: "")
    private var highlightWorkItem: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    /// Held directly because `document` is only assigned after init, when
    /// NSDocument.addWindowController runs.
    private weak var textDocument: TextDocument?

    init(document: TextDocument) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "NotepadMacEditor"
        window.minSize = NSSize(width: 360, height: 240)

        // TextKit 1 stack attached to the document's own storage.
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        document.textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 900, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600), textContainer: container)
        ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)

        textDocument = document
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
        buildLayout()
        configureTextView()

        document.onContentsReload = { [weak self] in self?.contentsDidReload() }
        document.onLanguageChange = { [weak self] in self?.languageDidChange() }
        document.onFormatChange = { [weak self] in self?.updateStatus() }

        observers.append(NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ruler.needsDisplay = true }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: textView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ruler.needsDisplay = true }
        })

        applySettings()
        languageDidChange()
        contentsDidReload()
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: Layout

    private func buildLayout() {
        guard let contentView = window?.contentView else { return }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        textView.postsFrameChangedNotifications = true

        let statusBar = NSStackView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.orientation = .horizontal
        statusBar.spacing = 0
        statusBar.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        for (index, label) in statusLabels.enumerated() {
            label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(index == 0 ? .defaultLow : .defaultHigh, for: .horizontal)
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.heightAnchor.constraint(equalToConstant: 14).isActive = true
                statusBar.addView(separator, in: .trailing)
                statusBar.setCustomSpacing(10, after: separator)
                statusBar.addView(label, in: .trailing)
                statusBar.setCustomSpacing(10, after: label)
            } else {
                statusBar.addView(label, in: .leading)
            }
        }

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        contentView.addSubview(divider)
        contentView.addSubview(statusBar)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            divider.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.topAnchor.constraint(equalTo: divider.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    private func configureTextView() {
        textView.configureForCode()
        textView.delegate = self
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
    }

    private func applySettings() {
        let settings = Settings.shared
        textView.applyBaseAttributes(settings.baseAttributes)
        ruler.font = NSFont.monospacedDigitSystemFont(ofSize: max(9, settings.fontSize - 2), weight: .regular)
        scrollView.rulersVisible = settings.showLineNumbers
        applyWordWrap(settings.wordWrap)
        scheduleHighlight(immediately: true)
    }

    private func applyWordWrap(_ wrap: Bool) {
        guard let container = textView.textContainer else { return }
        let width = scrollView.contentSize.width
        scrollView.hasHorizontalScroller = !wrap
        if wrap {
            textView.isHorizontallyResizable = false
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        } else {
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: 10_000_000, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
        }
        textView.sizeToFit()
        ruler.needsDisplay = true
    }

    // MARK: Document events

    private func contentsDidReload() {
        textView.applyBaseAttributes(Settings.shared.baseAttributes)
        textDidChangeContents()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    private func languageDidChange() {
        textView.language = textDocument?.language ?? .plainText
        scheduleHighlight(immediately: true)
        updateStatus()
    }

    private func textDidChangeContents() {
        lineIndex = LineIndex(text: textView.string as NSString)
        ruler.lineIndex = lineIndex
        updateStatus()
        scheduleHighlight(immediately: false)
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        textDidChangeContents()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateStatus()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        textDocument?.undoManager
    }

    // MARK: Syntax highlighting

    private func scheduleHighlight(immediately: Bool) {
        highlightWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.highlight() }
        }
        highlightWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediately ? 0 : 0.15), execute: work)
    }

    private func highlight() {
        guard let layoutManager = textView.layoutManager else { return }
        let text = textView.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        guard text.length <= Self.highlightLimit else { return }
        let tokenizer = SyntaxTokenizer.forLanguage(textView.language)
        for token in tokenizer.tokens(in: text) {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: Self.color(for: token.kind), forCharacterRange: token.range)
        }
    }

    private static func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .comment: return .systemGreen
        case .string: return .systemBrown
        case .number: return .systemOrange
        case .keyword: return .systemBlue
        case .preprocessor: return .systemPurple
        case .tag: return .systemBlue
        case .attribute: return .systemRed
        case .heading: return .systemIndigo
        }
    }

    // MARK: Status bar

    private func updateStatus() {
        guard let document = textDocument else { return }
        let selection = textView.selectedRange()
        let line = lineIndex.line(at: selection.location)
        ruler.currentLine = line
        var position = "Ln \(line + 1), Col \(lineIndex.column(at: selection.location) + 1)"
        if selection.length > 0 {
            let lastLine = lineIndex.line(at: max(selection.location, NSMaxRange(selection) - 1))
            position += "   Sel \(selection.length) | \(lastLine - line + 1)"
        }
        statusLabels[0].stringValue = "Tamanho: \(lineIndex.length)   Linhas: \(lineIndex.lineCount)"
        statusLabels[1].stringValue = position
        statusLabels[2].stringValue = document.language.displayName
        statusLabels[3].stringValue = document.lineEnding.displayName
        statusLabels[4].stringValue = document.encoding.displayName
    }

    // MARK: Menu commands

    @objc func setEncoding(_ sender: NSMenuItem) {
        guard FileEncoding.allCases.indices.contains(sender.tag) else { return }
        textDocument?.setEncoding(FileEncoding.allCases[sender.tag])
    }

    @objc func reopenWithEncoding(_ sender: NSMenuItem) {
        guard let document = textDocument, FileEncoding.allCases.indices.contains(sender.tag) else { return }
        do {
            try document.reopen(with: FileEncoding.allCases[sender.tag])
        } catch {
            document.presentError(error)
        }
    }

    @objc func setLineEnding(_ sender: NSMenuItem) {
        guard LineEnding.allCases.indices.contains(sender.tag) else { return }
        textDocument?.setLineEnding(LineEnding.allCases[sender.tag])
    }

    @objc func setLanguage(_ sender: NSMenuItem) {
        guard Language.allCases.indices.contains(sender.tag) else { return }
        textDocument?.language = Language.allCases[sender.tag]
    }

    @objc func toggleWordWrap(_ sender: Any?) {
        Settings.shared.wordWrap.toggle()
    }

    @objc func toggleLineNumbers(_ sender: Any?) {
        Settings.shared.showLineNumbers.toggle()
    }

    @objc func makeTextLarger(_ sender: Any?) {
        Settings.shared.fontSize += 1
    }

    @objc func makeTextSmaller(_ sender: Any?) {
        Settings.shared.fontSize -= 1
    }

    @objc func makeTextStandardSize(_ sender: Any?) {
        Settings.shared.fontSize = 13
    }

    @objc func useSelectionForFind(_ sender: Any?) {
        let selection = textView.selectedRange()
        guard selection.length > 0 else { return }
        FindPanelController.shared.setSearchText((textView.string as NSString).substring(with: selection))
    }

    @objc func goToLine(_ sender: Any?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Ir para a linha"
        alert.informativeText = "Número da linha (1 – \(lineIndex.lineCount)):"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = "\(lineIndex.line(at: textView.selectedRange().location) + 1)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Ir")
        alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self, let number = Int(field.stringValue.trimmingCharacters(in: .whitespaces)) else { return }
            let line = min(max(number, 1), self.lineIndex.lineCount) - 1
            let location = self.lineIndex.lineStarts[line]
            self.textView.setSelectedRange(NSRange(location: location, length: 0))
            self.textView.scrollRangeToVisible(NSRange(location: location, length: 0))
            self.window?.makeFirstResponder(self.textView)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let document = textDocument else { return false }
        switch menuItem.action {
        case #selector(setEncoding(_:)):
            menuItem.state = FileEncoding.allCases.firstIndex(of: document.encoding) == menuItem.tag ? .on : .off
        case #selector(reopenWithEncoding(_:)):
            return document.fileURL != nil && !document.isDocumentEdited
        case #selector(setLineEnding(_:)):
            menuItem.state = LineEnding.allCases.firstIndex(of: document.lineEnding) == menuItem.tag ? .on : .off
        case #selector(setLanguage(_:)):
            menuItem.state = Language.allCases.firstIndex(of: document.language) == menuItem.tag ? .on : .off
        case #selector(toggleWordWrap(_:)):
            menuItem.state = Settings.shared.wordWrap ? .on : .off
        case #selector(toggleLineNumbers(_:)):
            menuItem.state = Settings.shared.showLineNumbers ? .on : .off
        case #selector(useSelectionForFind(_:)):
            return textView.selectedRange().length > 0
        default:
            break
        }
        return true
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        if Settings.shared.wordWrap {
            textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        }
    }
}
