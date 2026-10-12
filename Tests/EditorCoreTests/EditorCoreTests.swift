import XCTest
@testable import EditorCore

final class FileEncodingTests: XCTestCase {
    func testDetectsBOMs() {
        XCTAssertEqual(FileEncoding.decode(Data([0xEF, 0xBB, 0xBF, 0x61])).encoding, .utf8BOM)
        XCTAssertEqual(FileEncoding.decode(Data([0xEF, 0xBB, 0xBF, 0x61])).text, "a")
        XCTAssertEqual(FileEncoding.decode(Data([0xFF, 0xFE, 0x61, 0x00])).encoding, .utf16LE)
        XCTAssertEqual(FileEncoding.decode(Data([0xFE, 0xFF, 0x00, 0x61])).text, "a")
    }

    func testUTF8ThenWindows1252Fallback() {
        XCTAssertEqual(FileEncoding.decode("ação".data(using: .utf8)!).encoding, .utf8)
        let ansi = FileEncoding.decode(Data([0x61, 0xE7, 0xE3, 0x6F, 0x80]))
        XCTAssertEqual(ansi.encoding, .windows1252)
        XCTAssertEqual(ansi.text, "ação€")
        // 0x81 is undefined in Windows-1252, so Latin-1 must take it.
        XCTAssertEqual(FileEncoding.decode(Data([0x61, 0x81])).encoding, .latin1)
    }

    func testRoundTripsEveryEncoding() throws {
        for encoding in FileEncoding.allCases {
            let text = "olá, mundo\n"
            let data = try XCTUnwrap(encoding.encode(text), "\(encoding)")
            XCTAssertEqual(FileEncoding.decode(data, as: encoding), text, "\(encoding)")
        }
    }

    func testRefusesLossyEncoding() {
        XCTAssertNil(FileEncoding.windows1252.encode("emoji 🙂"))
        XCTAssertNotNil(FileEncoding.utf8.encode("emoji 🙂"))
    }
}

final class LineEndingTests: XCTestCase {
    func testDetection() {
        XCTAssertEqual(LineEnding.detect(in: "a\r\nb\r\nc"), .crlf)
        XCTAssertEqual(LineEnding.detect(in: "a\nb\n"), .lf)
        XCTAssertEqual(LineEnding.detect(in: "a\rb\r"), .cr)
        XCTAssertEqual(LineEnding.detect(in: "abc"), .lf)
        XCTAssertEqual(LineEnding.detect(in: "a\r\nb\nc\r\n"), .crlf)
    }

    func testNormalizeAndApply() {
        let normalized = LineEnding.normalize("a\r\nb\rc\n")
        XCTAssertEqual(normalized, "a\nb\nc\n")
        XCTAssertEqual(LineEnding.crlf.apply(to: normalized), "a\r\nb\r\nc\r\n")
        XCTAssertEqual(LineEnding.cr.apply(to: normalized), "a\rb\rc\r")
    }
}

final class LineIndexTests: XCTestCase {
    func testLinesAndColumns() {
        let index = LineIndex(text: "ab\ncd\n")
        XCTAssertEqual(index.lineStarts, [0, 3, 6])
        XCTAssertEqual(index.line(at: 0), 0)
        XCTAssertEqual(index.line(at: 2), 0)
        XCTAssertEqual(index.line(at: 3), 1)
        XCTAssertEqual(index.column(at: 4), 1)
        XCTAssertEqual(index.line(at: 6), 2)
        XCTAssertEqual(LineIndex(text: "").lineCount, 1)
    }
}

final class SearchEngineTests: XCTestCase {
    func testFindNextWrapsAndRespectsOptions() throws {
        let text = "Foo foo food" as NSString
        let engine = try SearchEngine(options: SearchOptions(pattern: "foo", wholeWord: true))
        XCTAssertEqual(engine.findNext(in: text, after: NSRange(location: 0, length: 0), wrap: true), NSRange(location: 0, length: 3))
        XCTAssertEqual(engine.findNext(in: text, after: NSRange(location: 0, length: 3), wrap: true), NSRange(location: 4, length: 3))
        XCTAssertEqual(engine.findNext(in: text, after: NSRange(location: 4, length: 3), wrap: true), NSRange(location: 0, length: 3))
        XCTAssertNil(engine.findNext(in: text, after: NSRange(location: 4, length: 3), wrap: false))
        XCTAssertEqual(engine.count(in: text), 2)

        let caseSensitive = try SearchEngine(options: SearchOptions(pattern: "foo", matchCase: true))
        XCTAssertEqual(caseSensitive.count(in: text), 2)
    }

    func testFindPrevious() throws {
        let text = "a1 a2 a3" as NSString
        let engine = try SearchEngine(options: SearchOptions(pattern: "a\\d", isRegex: true))
        XCTAssertEqual(engine.findPrevious(in: text, before: NSRange(location: 6, length: 2), wrap: true), NSRange(location: 3, length: 2))
        XCTAssertEqual(engine.findPrevious(in: text, before: NSRange(location: 0, length: 2), wrap: true), NSRange(location: 6, length: 2))
    }

    func testLiteralModeEscapesPatternAndReplacement() throws {
        let engine = try SearchEngine(options: SearchOptions(pattern: "a.b"))
        let result = engine.replaceAll(in: "a.b axb", with: "$1")
        XCTAssertEqual(result.text, "$1 axb")
        XCTAssertEqual(result.count, 1)
    }

    func testRegexReplacementWithGroupsAndEscapes() throws {
        let engine = try SearchEngine(options: SearchOptions(pattern: "(\\w+),(\\w+)", isRegex: true))
        XCTAssertEqual(engine.replaceAll(in: "a,b c,d", with: "$2\\t$1\\n").text, "b\ta\n d\tc\n")
    }

    func testEmptyMatchesAdvance() throws {
        let text = "a\nb" as NSString
        let engine = try SearchEngine(options: SearchOptions(pattern: "^", isRegex: true))
        let first = try XCTUnwrap(engine.findNext(in: text, after: NSRange(location: 0, length: 0), wrap: false))
        XCTAssertEqual(first, NSRange(location: 2, length: 0))
    }

    func testInvalidRegex() {
        XCTAssertThrowsError(try SearchEngine(options: SearchOptions(pattern: "(", isRegex: true))) { error in
            XCTAssertEqual(error as? SearchError, .invalidRegex("("))
        }
        XCTAssertThrowsError(try SearchEngine(options: SearchOptions(pattern: "")))
    }

    func testExactMatchForReplace() throws {
        let text = "x foo y" as NSString
        let engine = try SearchEngine(options: SearchOptions(pattern: "fo+", isRegex: true))
        XCTAssertNotNil(engine.match(exactly: NSRange(location: 2, length: 3), in: text))
        XCTAssertNil(engine.match(exactly: NSRange(location: 2, length: 2), in: text))
    }
}

final class SyntaxTokenizerTests: XCTestCase {
    func testEveryLanguageCompilesWithoutCapturingGroups() {
        for language in Language.allCases {
            let tokenizer = SyntaxTokenizer(language: language)
            XCTAssertTrue(tokenizer.isValid, "\(language) rules do not compile")
            XCTAssertEqual(tokenizer.captureGroupCount, language.rules.count, "\(language) rule has a capturing group")
        }
    }

    func testEarliestConstructWins() {
        let text = #"let s = "// not a comment" // real"# as NSString
        let tokens = SyntaxTokenizer(language: .swift).tokens(in: text)
        XCTAssertEqual(tokens.map(\.kind), [.keyword, .string, .comment])
        XCTAssertEqual(text.substring(with: tokens[1].range), #""// not a comment""#)
        XCTAssertEqual(text.substring(with: tokens[2].range), "// real")
    }

    func testMultilineBlockComment() {
        let text = "int a; /* one\ntwo */ return 1;" as NSString
        let kinds = SyntaxTokenizer(language: .c).tokens(in: text).map(\.kind)
        XCTAssertEqual(kinds, [.keyword, .comment, .keyword, .number])
    }

    func testKeywordsNeedWordBoundaries() {
        let tokens = SyntaxTokenizer(language: .python).tokens(in: "format = iffy" as NSString)
        XCTAssertTrue(tokens.isEmpty)
    }
}

final class LanguageDetectionTests: XCTestCase {
    func testDetection() {
        XCTAssertEqual(Language.detect(fileName: "main.swift", content: ""), .swift)
        XCTAssertEqual(Language.detect(fileName: "INDEX.HTML", content: ""), .html)
        XCTAssertEqual(Language.detect(fileName: "script", content: "#!/usr/bin/env python3\n"), .python)
        XCTAssertEqual(Language.detect(fileName: "run", content: "#!/bin/bash\n"), .shell)
        XCTAssertEqual(Language.detect(fileName: nil, content: "hello"), .plainText)
    }
}

final class LineOperationsTests: XCTestCase {
    private func apply(_ edit: TextEdit?, to text: String) -> String {
        guard let edit else { return text }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testDuplicate() {
        let text = "a\nb\nc"
        let middle = LineOperations.duplicateLines(in: text as NSString, selection: NSRange(location: 2, length: 0))
        XCTAssertEqual(apply(middle, to: text), "a\nb\nb\nc")
        XCTAssertEqual(middle.selection, NSRange(location: 4, length: 0))
        let last = LineOperations.duplicateLines(in: text as NSString, selection: NSRange(location: 4, length: 0))
        XCTAssertEqual(apply(last, to: text), "a\nb\nc\nc")
        XCTAssertEqual(last.selection, NSRange(location: 6, length: 0))
    }

    func testDelete() {
        let text = "a\nb\nc"
        XCTAssertEqual(apply(LineOperations.deleteLines(in: text as NSString, selection: NSRange(location: 2, length: 0)), to: text), "a\nc")
        let last = LineOperations.deleteLines(in: text as NSString, selection: NSRange(location: 4, length: 0))
        XCTAssertEqual(apply(last, to: text), "a\nb")
        XCTAssertEqual(last.selection, NSRange(location: 2, length: 0))
        XCTAssertEqual(apply(LineOperations.deleteLines(in: "only" as NSString, selection: NSRange(location: 1, length: 0)), to: "only"), "")
    }

    func testMoveUpAndDown() {
        let text = "a\nb\nc"
        let up = LineOperations.moveLinesUp(in: text as NSString, selection: NSRange(location: 4, length: 0))
        XCTAssertEqual(apply(up, to: text), "a\nc\nb")
        XCTAssertEqual(up?.selection, NSRange(location: 2, length: 0))
        let down = LineOperations.moveLinesDown(in: text as NSString, selection: NSRange(location: 2, length: 1))
        XCTAssertEqual(apply(down, to: text), "a\nc\nb")
        XCTAssertEqual(down?.selection, NSRange(location: 4, length: 1))
        XCTAssertNil(LineOperations.moveLinesUp(in: text as NSString, selection: NSRange(location: 0, length: 0)))
        XCTAssertNil(LineOperations.moveLinesDown(in: text as NSString, selection: NSRange(location: 4, length: 0)))
    }

    func testSelectionEndingAtLineStartExcludesNextLine() {
        let range = LineOperations.coveredLines(in: "a\nb\nc" as NSString, selection: NSRange(location: 0, length: 2))
        XCTAssertEqual(range, NSRange(location: 0, length: 2))
    }

    func testToggleLineComment() {
        let text = "  a\n    b\n"
        let selection = NSRange(location: 0, length: (text as NSString).length)
        let commented = apply(LineOperations.toggleComment(in: text as NSString, selection: selection, syntax: .line("//")), to: text)
        XCTAssertEqual(commented, "  // a\n  //   b\n")
        let restored = apply(LineOperations.toggleComment(in: commented as NSString, selection: NSRange(location: 0, length: (commented as NSString).length), syntax: .line("//")), to: commented)
        XCTAssertEqual(restored, text)
    }

    func testToggleBlockComment() {
        let text = "<p>x</p>"
        let commented = apply(LineOperations.toggleComment(in: text as NSString, selection: NSRange(location: 0, length: 0), syntax: .block(open: "<!--", close: "-->")), to: text)
        XCTAssertEqual(commented, "<!-- <p>x</p> -->")
        let restored = apply(LineOperations.toggleComment(in: commented as NSString, selection: NSRange(location: 0, length: 0), syntax: .block(open: "<!--", close: "-->")), to: commented)
        XCTAssertEqual(restored, text)
    }

    func testTrimAndSort() {
        XCTAssertEqual(apply(LineOperations.trimTrailingWhitespace(in: "a  \nb\t\n" as NSString, selection: NSRange(location: 0, length: 0)), to: "a  \nb\t\n"), "a\nb\n")
        XCTAssertNil(LineOperations.trimTrailingWhitespace(in: "a\n" as NSString, selection: NSRange(location: 0, length: 0)))
        XCTAssertEqual(apply(LineOperations.sortLines(in: "c\na10\na2\n" as NSString, selection: NSRange(location: 0, length: 0)), to: "c\na10\na2\n"), "a2\na10\nc\n")
    }
}

final class SaveRoundTripTests: XCTestCase {
    /// Mirrors TextDocument: decode → detect EOL → normalize → (edit) → apply EOL → encode.
    func testOpenThenSavePreservesBytes() throws {
        let files: [Data] = [
            Data([0x61, 0xE7, 0xE3, 0x6F, 0x0D, 0x0A, 0x62, 0x0D, 0x0A]),        // ANSI + CRLF
            Data([0xEF, 0xBB, 0xBF]) + "olá\nmundo\n".data(using: .utf8)!,      // UTF-8 BOM + LF
            Data([0xFF, 0xFE]) + "x\ry".data(using: .utf16LittleEndian)!,       // UTF-16 LE + CR
        ]
        for original in files {
            let decoded = FileEncoding.decode(original)
            let ending = LineEnding.detect(in: decoded.text)
            let inMemory = LineEnding.normalize(decoded.text)
            let saved = try XCTUnwrap(decoded.encoding.encode(ending.apply(to: inMemory)))
            XCTAssertEqual(saved, original, "\(decoded.encoding) \(ending)")
        }
    }
}

final class SessionStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SessionStoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func tab(_ id: UUID, path: String? = nil, backup: Bool) -> SessionSnapshot.TabState {
        SessionSnapshot.TabState(id: id, path: path, hasBackup: backup, encoding: "utf8", lineEnding: "crlf",
                                 language: "swift", selectionLocation: 3, selectionLength: 2, topCharacter: 10)
    }

    func testRoundTripsSnapshotAndBackups() throws {
        let store = SessionStore(directory: directory)
        XCTAssertNil(store.load())
        let saved = UUID(), untitled = UUID()
        let snapshot = SessionSnapshot(windows: [
            .init(frame: "{{10, 20}, {800, 600}}", selectedTab: 1, tabs: [tab(saved, path: "/tmp/a.swift", backup: false), tab(untitled, backup: true)]),
        ])
        try store.write(snapshot, changedBackups: [untitled: "texto não salvo\n"])
        XCTAssertEqual(store.load(), snapshot)
        XCTAssertEqual(store.backupText(for: untitled), "texto não salvo\n")
        XCTAssertNil(store.backupText(for: saved))
    }

    func testRemovesUnreferencedBackupsAndKeepsUnchangedOnes() throws {
        let store = SessionStore(directory: directory)
        let kept = UUID(), dropped = UUID()
        try store.write(SessionSnapshot(windows: [.init(frame: nil, selectedTab: 0, tabs: [tab(kept, backup: true), tab(dropped, backup: true)])]),
                        changedBackups: [kept: "a", dropped: "b"])
        // Next snapshot: `kept` unchanged (not rewritten), `dropped` closed.
        try store.write(SessionSnapshot(windows: [.init(frame: nil, selectedTab: 0, tabs: [tab(kept, backup: true)])]), changedBackups: [:])
        XCTAssertEqual(store.backupText(for: kept), "a")
        XCTAssertNil(store.backupText(for: dropped))
    }

    func testCorruptSessionLoadsAsNil() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: directory.appendingPathComponent("session.json"))
        XCTAssertNil(SessionStore(directory: directory).load())
    }

    func testClear() throws {
        let store = SessionStore(directory: directory)
        let id = UUID()
        try store.write(SessionSnapshot(windows: [.init(frame: nil, selectedTab: 0, tabs: [tab(id, backup: true)])]), changedBackups: [id: "x"])
        store.clear()
        XCTAssertNil(store.load())
        XCTAssertNil(store.backupText(for: id))
    }
}
