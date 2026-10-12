// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NotepadMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NotepadMac", targets: ["NotepadMac"]),
    ],
    targets: [
        // Pure text logic (encodings, line endings, search, highlighting rules,
        // line operations). No AppKit, so it is fully unit-testable.
        .target(name: "EditorCore"),
        .executableTarget(name: "NotepadMac", dependencies: ["EditorCore"]),
        .testTarget(name: "EditorCoreTests", dependencies: ["EditorCore"]),
    ]
)
