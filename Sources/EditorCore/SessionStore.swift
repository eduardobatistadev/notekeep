import Foundation

/// What is needed to bring every tab back after a quit or crash, like
/// Notepad++'s session snapshot.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    public var version = 1
    public var windows: [WindowState]

    public init(windows: [WindowState]) {
        self.windows = windows
    }

    /// One window and its tabs, left to right.
    public struct WindowState: Codable, Equatable, Sendable {
        public var frame: String?
        public var selectedTab: Int
        public var tabs: [TabState]

        public init(frame: String?, selectedTab: Int, tabs: [TabState]) {
            self.frame = frame
            self.selectedTab = selectedTab
            self.tabs = tabs
        }
    }

    public struct TabState: Codable, Equatable, Sendable {
        public var id: UUID
        /// File on disk, or nil for a never-saved tab.
        public var path: String?
        /// Unsaved text lives in the backup file named `<id>.txt`.
        public var hasBackup: Bool
        public var encoding: String
        public var lineEnding: String
        public var language: String
        public var selectionLocation: Int
        public var selectionLength: Int
        /// UTF-16 offset of the first visible line.
        public var topCharacter: Int

        public init(
            id: UUID, path: String?, hasBackup: Bool, encoding: String, lineEnding: String, language: String,
            selectionLocation: Int, selectionLength: Int, topCharacter: Int
        ) {
            self.id = id
            self.path = path
            self.hasBackup = hasBackup
            self.encoding = encoding
            self.lineEnding = lineEnding
            self.language = language
            self.selectionLocation = selectionLocation
            self.selectionLength = selectionLength
            self.topCharacter = topCharacter
        }
    }
}

/// Stores the session as `session.json` plus one UTF-8 backup per tab with
/// unsaved text. Backups are written before the snapshot that references
/// them, and unreferenced backups are deleted only afterwards, so a crash at
/// any point leaves a loadable session.
public final class SessionStore {
    public let directory: URL
    private var sessionURL: URL { directory.appendingPathComponent("session.json") }
    private var backupDirectory: URL { directory.appendingPathComponent("backups", isDirectory: true) }

    public init(directory: URL) {
        self.directory = directory
    }

    public func backupURL(for id: UUID) -> URL {
        backupDirectory.appendingPathComponent("\(id.uuidString).txt")
    }

    /// Nil when there is no session or it cannot be decoded.
    public func load() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: sessionURL) else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    public func backupText(for id: UUID) -> String? {
        guard let data = try? Data(contentsOf: backupURL(for: id)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Writes changed backups, then the snapshot, then removes backups the
    /// snapshot no longer references.
    public func write(_ snapshot: SessionSnapshot, changedBackups: [UUID: String]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        for (id, text) in changedBackups {
            try Data(text.utf8).write(to: backupURL(for: id), options: .atomic)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: sessionURL, options: .atomic)

        let referenced = Set(snapshot.windows.flatMap(\.tabs).filter(\.hasBackup).map { "\($0.id.uuidString).txt" })
        for name in (try? fileManager.contentsOfDirectory(atPath: backupDirectory.path)) ?? [] where !referenced.contains(name) {
            try? fileManager.removeItem(at: backupDirectory.appendingPathComponent(name))
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: sessionURL)
        try? FileManager.default.removeItem(at: backupDirectory)
    }
}
