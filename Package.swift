// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Notekeep",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Notekeep", targets: ["Notekeep"]),
    ],
    targets: [
        // Pure text logic (encodings, line endings, search, highlighting rules,
        // line operations). No AppKit, so it is fully unit-testable.
        .target(name: "EditorCore"),
        .executableTarget(name: "Notekeep", dependencies: ["EditorCore"]),
        .testTarget(name: "EditorCoreTests", dependencies: ["EditorCore"]),
    ]
)
