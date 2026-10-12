import AppKit

/// App-wide editor preferences, shared by every window like Notepad++'s
/// global view settings.
@MainActor
final class Settings {
    static let shared = Settings()
    static let didChange = Notification.Name("NotepadMacSettingsDidChange")

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "fontSize": 13.0,
            "wordWrap": false,
            "showLineNumbers": true,
            "tabWidth": 4,
        ])
    }

    var fontSize: CGFloat {
        get { CGFloat(defaults.double(forKey: "fontSize")) }
        set { defaults.set(Double(min(max(newValue, 8), 72)), forKey: "fontSize"); notify() }
    }

    var wordWrap: Bool {
        get { defaults.bool(forKey: "wordWrap") }
        set { defaults.set(newValue, forKey: "wordWrap"); notify() }
    }

    var showLineNumbers: Bool {
        get { defaults.bool(forKey: "showLineNumbers") }
        set { defaults.set(newValue, forKey: "showLineNumbers"); notify() }
    }

    var tabWidth: Int { max(1, defaults.integer(forKey: "tabWidth")) }

    var font: NSFont { NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) }

    /// Attributes for document text; syntax colors are layered on top as
    /// temporary layout attributes so they never touch the document or undo.
    var baseAttributes: [NSAttributedString.Key: Any] {
        let font = self.font
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = []
        paragraph.defaultTabInterval = spaceWidth * CGFloat(tabWidth)
        return [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
