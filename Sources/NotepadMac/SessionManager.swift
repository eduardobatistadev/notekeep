import AppKit
import EditorCore

/// Notepad++-style session snapshot: quitting never asks to save, every tab
/// (including unsaved text) is backed up, and the next launch reopens them
/// where they were. A periodic backup also covers crashes and force quits.
@MainActor
final class SessionManager {
    static let shared = SessionManager()

    /// Same cadence as Notepad++'s default periodic backup.
    private static let backupInterval: TimeInterval = 7

    let store: SessionStore
    private var hasChanges = false
    private var timer: Timer?
    private var isRestoring = false
    private var savedForTermination = false
    /// editVersion of each document's text when its backup was last written.
    private var backedUpVersions: [UUID: Int] = [:]

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = SessionStore(directory: support.appendingPathComponent("NotepadMac/Session", isDirectory: true))
    }

    var isEnabled: Bool { Settings.shared.rememberSession }

    func markChanged() {
        if !isRestoring { hasChanges = true }
    }

    func startPeriodicBackup() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.backupInterval, repeats: true) { _ in
            MainActor.assumeIsolated { SessionManager.shared.saveIfChanged() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func saveIfChanged() {
        guard isEnabled, hasChanges else { return }
        _ = save()
    }

    /// Writes the snapshot now. Returns false (leaving the normal "save
    /// changes?" flow in charge) when it cannot be written.
    @discardableResult
    func save() -> Bool {
        let (snapshot, changedBackups, versions) = makeSnapshot()
        do {
            try store.write(snapshot, changedBackups: changedBackups)
        } catch {
            NSLog("NotepadMac: could not write session: \(error)")
            return false
        }
        backedUpVersions = versions
        hasChanges = false
        return true
    }

    /// Snapshot for quitting, taken once: either while AppKit reviews unsaved
    /// documents (it closes every document right after that review) or, when
    /// nothing is unsaved and no review happens, from applicationShouldTerminate.
    func saveForTermination() -> Bool {
        guard isEnabled else { return false }
        if savedForTermination { return true }
        savedForTermination = save()
        return savedForTermination
    }

    /// Called when the user turns the feature off.
    func discard() {
        store.clear()
        backedUpVersions = [:]
    }

    // MARK: Snapshot

    private func makeSnapshot() -> (SessionSnapshot, [UUID: String], [UUID: Int]) {
        var windows: [SessionSnapshot.WindowState] = []
        var changedBackups: [UUID: String] = [:]
        var versions: [UUID: Int] = [:]
        var seen = Set<ObjectIdentifier>()

        // Front-to-back, then any remaining (e.g. minimized) editor windows.
        for window in NSApp.orderedWindows + NSApp.windows where window.windowController is EditorWindowController {
            guard !seen.contains(ObjectIdentifier(window)) else { continue }
            let group = window.tabbedWindows ?? [window]
            group.forEach { seen.insert(ObjectIdentifier($0)) }

            var tabs: [SessionSnapshot.TabState] = []
            var selectedTab = 0
            for tabWindow in group {
                guard let controller = tabWindow.windowController as? EditorWindowController,
                      let document = controller.document as? TextDocument else { continue }
                let text = document.textStorage.string
                let needsBackup = document.isDocumentEdited || (document.fileURL == nil && !text.isEmpty)
                if needsBackup {
                    versions[document.sessionID] = document.editVersion
                    if backedUpVersions[document.sessionID] != document.editVersion
                        || !FileManager.default.fileExists(atPath: store.backupURL(for: document.sessionID).path) {
                        changedBackups[document.sessionID] = text
                    }
                }
                if tabWindow == window.tabGroup?.selectedWindow { selectedTab = tabs.count }
                let view = controller.viewState
                tabs.append(SessionSnapshot.TabState(
                    id: document.sessionID,
                    path: document.fileURL?.path,
                    hasBackup: needsBackup,
                    encoding: document.encoding.rawValue,
                    lineEnding: document.lineEnding.rawValue,
                    language: document.language.rawValue,
                    selectionLocation: view.selection.location,
                    selectionLength: view.selection.length,
                    topCharacter: view.topCharacter
                ))
            }
            guard !tabs.isEmpty else { continue }
            windows.append(SessionSnapshot.WindowState(
                frame: NSStringFromRect(window.frame),
                selectedTab: selectedTab,
                tabs: tabs
            ))
        }
        return (SessionSnapshot(windows: windows), changedBackups, versions)
    }

    // MARK: Restore

    /// Reopens the saved session. Returns the number of tabs restored.
    @discardableResult
    func restore() -> Int {
        guard isEnabled, let snapshot = store.load() else { return 0 }
        isRestoring = true
        defer { isRestoring = false }

        var restored = 0
        var frontWindow: NSWindow?
        // Back-to-front, so the window that was frontmost ends up in front.
        for windowState in snapshot.windows.reversed() {
            var groupWindows: [NSWindow] = []
            for tab in windowState.tabs {
                guard let (document, window) = openTab(tab) else { continue }
                if let previous = groupWindows.last {
                    previous.addTabbedWindow(window, ordered: .above)
                } else {
                    if let frame = windowState.frame { window.setFrame(NSRectFromString(frame), display: false) }
                    // Start a new window instead of tabbing into the previous one.
                    window.tabbingMode = .disallowed
                    document.showWindows()
                    window.tabbingMode = .preferred
                }
                groupWindows.append(window)
                restored += 1
            }
            guard !groupWindows.isEmpty else { continue }
            let selected = groupWindows[min(max(windowState.selectedTab, 0), groupWindows.count - 1)]
            selected.tabGroup?.selectedWindow = selected
            selected.makeKeyAndOrderFront(nil)
            frontWindow = selected
        }
        frontWindow?.makeKeyAndOrderFront(nil)

        // Backups of tabs that came back are already on disk and current.
        for document in NSDocumentController.shared.documents.compactMap({ $0 as? TextDocument }) where document.isDocumentEdited {
            backedUpVersions[document.sessionID] = document.editVersion
        }
        return restored
    }

    private func openTab(_ tab: SessionSnapshot.TabState) -> (TextDocument, NSWindow)? {
        let controller = NSDocumentController.shared
        let url = tab.path.map { URL(fileURLWithPath: $0) }
        let backup = tab.hasBackup ? store.backupText(for: tab.id) : nil
        let encoding = FileEncoding(rawValue: tab.encoding) ?? .utf8
        let lineEnding = LineEnding(rawValue: tab.lineEnding) ?? .lf

        if let url, controller.document(for: url) != nil { return nil }

        let document: TextDocument
        do {
            if let url, FileManager.default.fileExists(atPath: url.path) {
                guard let opened = try controller.makeDocument(withContentsOf: url, ofType: DocumentController.textType) as? TextDocument else { return nil }
                document = opened
                if let backup {
                    document.restoreUnsavedText(backup, encoding: encoding, lineEnding: lineEnding)
                } else {
                    document.restoreChosenEncoding(encoding)
                }
            } else if let backup {
                // Never saved, or the file has since been deleted: keep the text
                // (and the original path, so Save writes it back there).
                guard let untitled = try controller.makeUntitledDocument(ofType: DocumentController.textType) as? TextDocument else { return nil }
                document = untitled
                if let url { document.fileURL = url }
                document.restoreUnsavedText(backup, encoding: encoding, lineEnding: lineEnding)
            } else if url == nil {
                guard let untitled = try controller.makeUntitledDocument(ofType: DocumentController.textType) as? TextDocument else { return nil }
                document = untitled
            } else {
                return nil // Saved file that no longer exists and had no unsaved text.
            }
        } catch {
            NSLog("NotepadMac: could not restore \(tab.path ?? "untitled tab"): \(error)")
            return nil
        }

        document.sessionID = tab.id
        if let language = Language(rawValue: tab.language) { document.language = language }
        controller.addDocument(document)
        document.makeWindowControllers()
        guard let windowController = document.windowControllers.first as? EditorWindowController,
              let window = windowController.window else { return nil }
        let selection = NSRange(location: tab.selectionLocation, length: tab.selectionLength)
        DispatchQueue.main.async {
            windowController.restoreViewState(selection: selection, topCharacter: tab.topCharacter)
        }
        return (document, window)
    }
}
