import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    // The first NSDocumentController instance becomes the shared one, so the
    // subclass must be created before anything touches the shared controller.
    _ = DocumentController()
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.mainMenu = MainMenu.build()
    withExtendedLifetime(delegate) {
        app.run()
    }
}
