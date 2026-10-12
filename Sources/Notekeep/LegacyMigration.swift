import Foundation

/// One-time move of data from the app's previous name (NotepadMac,
/// bundle id local.notepadmac): preferences and the saved session.
/// Runs before Settings or the session store are first used.
enum LegacyMigration {
    private static let legacyDefaultsDomain = "local.notepadmac"
    private static let doneKey = "migratedFromNotepadMac"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }

        if let legacy = UserDefaults.standard.persistentDomain(forName: legacyDefaultsDomain) {
            for key in ["fontSize", "wordWrap", "showLineNumbers", "tabWidth", "rememberSession", "appearance"]
            where defaults.object(forKey: key) == nil {
                if let value = legacy[key] { defaults.set(value, forKey: key) }
            }
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacySession = support.appendingPathComponent("NotepadMac/Session", isDirectory: true)
        let session = support.appendingPathComponent("Notekeep/Session", isDirectory: true)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: legacySession.path), !fileManager.fileExists(atPath: session.path) {
            do {
                try fileManager.createDirectory(at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: legacySession, to: session)
                let legacyFolder = legacySession.deletingLastPathComponent()
                if (try? fileManager.contentsOfDirectory(atPath: legacyFolder.path))?.isEmpty == true {
                    try? fileManager.removeItem(at: legacyFolder)
                }
            } catch {
                // Leave the old session in place and try again next launch.
                NSLog("Notekeep: could not migrate session: \(error)")
                return
            }
        }
        defaults.set(true, forKey: doneKey)
    }
}
