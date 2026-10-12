import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
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
