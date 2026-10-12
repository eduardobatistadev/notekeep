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

    /// AppKit calls this when the app quits. With the session snapshot on, the
    /// unsaved text is backed up instead of asking about each document, and
    /// the documents keep their edited state for the next launch.
    override func reviewUnsavedDocuments(
        withAlertTitle title: String?,
        cancellable: Bool,
        delegate: Any?,
        didReviewAllSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        let saved = MainActor.assumeIsolated { SessionManager.shared.saveForTermination() }
        guard saved else {
            super.reviewUnsavedDocuments(withAlertTitle: title, cancellable: cancellable, delegate: delegate,
                                         didReviewAllSelector: didReviewAllSelector, contextInfo: contextInfo)
            return
        }
        // Report "all reviewed" through the Objective-C callback:
        // - (void)documentController:(NSDocumentController *)c didReviewAll:(BOOL)flag contextInfo:(void *)info
        guard let delegate = delegate as AnyObject?, let selector = didReviewAllSelector else { return }
        typealias DidReviewAll = @convention(c) (AnyObject, Selector, AnyObject, ObjCBool, UnsafeMutableRawPointer?) -> Void
        let implementation = unsafeBitCast(delegate.method(for: selector), to: DidReviewAll.self)
        implementation(delegate, selector, self, true, contextInfo)
    }
}
