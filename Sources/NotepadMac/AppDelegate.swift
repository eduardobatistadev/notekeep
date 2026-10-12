import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var restoredTabCount = 0

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        Settings.shared.applyAppearance()
        // Restore before AppKit decides whether to open an untitled document
        // and before files opened from Finder join as extra tabs.
        restoredTabCount = SessionManager.shared.restore()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        SessionManager.shared.startPeriodicBackup()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        restoredTabCount == 0 && NSDocumentController.shared.documents.isEmpty
    }

    /// Runs on every quit. AppKit only reviews documents when some are edited,
    /// so tabs without unsaved changes are snapshotted here instead.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        _ = SessionManager.shared.saveForTermination()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !SessionManager.shared.isEnabled {
            SessionManager.shared.discard()
        }
    }

    @objc func toggleRememberSession(_ sender: Any?) {
        Settings.shared.rememberSession.toggle()
        if Settings.shared.rememberSession {
            SessionManager.shared.save()
        } else {
            SessionManager.shared.discard()
        }
    }

    @objc func setAppearanceMode(_ sender: NSMenuItem) {
        guard AppearanceMode.allCases.indices.contains(sender.tag) else { return }
        Settings.shared.appearance = AppearanceMode.allCases[sender.tag]
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleRememberSession(_:)) {
            menuItem.state = Settings.shared.rememberSession ? .on : .off
        }
        if menuItem.action == #selector(setAppearanceMode(_:)) {
            menuItem.state = AppearanceMode.allCases.firstIndex(of: Settings.shared.appearance) == menuItem.tag ? .on : .off
        }
        return true
    }

    /// Editor windows prefer tabbing, so a new document joins the front window
    /// as a tab; this also backs the tab bar's "+" button.
    @objc func newWindowForTab(_ sender: Any?) {
        NSDocumentController.shared.newDocument(sender)
    }

    // Find commands live here so they work from the editor and the panel alike.

    @objc func showFindPanel(_ sender: Any?) {
        FindPanelController.shared.show()
    }

    @objc func findNextMatch(_ sender: Any?) {
        FindPanelController.shared.findNext(sender)
    }

    @objc func findPreviousMatch(_ sender: Any?) {
        FindPanelController.shared.findPrevious(sender)
    }
}
