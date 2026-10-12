import Foundation

public enum TokenKind: Sendable, CaseIterable {
    case comment
    case string
    case number
    case keyword
    case preprocessor
    case tag
    case attribute
    case heading
}

public struct TokenRule: Sendable {
    public let kind: TokenKind
    /// Must not contain capturing groups: rules are combined into one
    /// alternation and each rule is identified by its group number.
    public let pattern: String

    public init(_ kind: TokenKind, _ pattern: String) {
        self.kind = kind
        self.pattern = pattern
    }
}

public enum CommentSyntax: Equatable, Sendable {
    case line(String)
    case block(open: String, close: String)
}

public enum Language: String, CaseIterable, Sendable {
    case plainText
    case c
    case cpp
    case csharp
    case java
    case javascript
    case typescript
    case swift
    case go
    case rust
    case python
    case ruby
    case php
    case shell
    case sql
    case html
    case xml
    case css
    case json
    case yaml
    case ini
    case markdown

    public var displayName: String {
        switch self {
        case .plainText: return "Texto simples"
        case .c: return "C"
        case .cpp: return "C++"
        case .csharp: return "C#"
        case .java: return "Java"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .swift: return "Swift"
        case .go: return "Go"
        case .rust: return "Rust"
        case .python: return "Python"
        case .ruby: return "Ruby"
        case .php: return "PHP"
        case .shell: return "Shell"
        case .sql: return "SQL"
        case .html: return "HTML"
        case .xml: return "XML"
        case .css: return "CSS"
        case .json: return "JSON"
        case .yaml: return "YAML"
        case .ini: return "INI"
        case .markdown: return "Markdown"
        }
    }

    public var fileExtensions: [String] {
        switch self {
        case .plainText: return ["txt", "text", "log"]
        case .c: return ["c", "h"]
        case .cpp: return ["cpp", "cc", "cxx", "hpp", "hh", "hxx", "ino", "m", "mm"]
        case .csharp: return ["cs"]
        case .java: return ["java", "kt", "kts", "gradle", "scala"]
        case .javascript: return ["js", "mjs", "cjs", "jsx"]
        case .typescript: return ["ts", "mts", "cts", "tsx"]
        case .swift: return ["swift"]
        case .go: return ["go"]
        case .rust: return ["rs"]
        case .python: return ["py", "pyw", "pyi"]
        case .ruby: return ["rb", "rake", "gemspec"]
        case .php: return ["php", "phtml"]
        case .shell: return ["sh", "bash", "zsh", "fish", "command"]
        case .sql: return ["sql"]
        case .html: return ["html", "htm", "xhtml", "vue", "svelte"]
        case .xml: return ["xml", "plist", "svg", "xsd", "xsl", "csproj", "storyboard", "xib"]
        case .css: return ["css", "scss", "less"]
        case .json: return ["json", "jsonc", "geojson"]
        case .yaml: return ["yaml", "yml"]
        case .ini: return ["ini", "cfg", "conf", "toml", "properties", "env", "editorconfig"]
        case .markdown: return ["md", "markdown", "mdown"]
        }
    }

    /// Chooses a language from the file extension, then from a shebang line.
    public static func detect(fileName: String?, content: String) -> Language {
        if let fileName {
            let ext = (fileName as NSString).pathExtension.lowercased()
            if !ext.isEmpty, let match = allCases.first(where: { $0.fileExtensions.contains(ext) }) {
                return match
            }
            let base = (fileName as NSString).lastPathComponent.lowercased()
            if [".bashrc", ".zshrc", ".profile", ".bash_profile", ".zprofile"].contains(base) { return .shell }
            if [".gitconfig", ".npmrc"].contains(base) { return .ini }
        }
        if content.hasPrefix("#!") {
            let firstLine = content.prefix(while: { $0 != "\n" })
            if firstLine.contains("python") { return .python }
            if firstLine.contains("ruby") { return .ruby }
            if firstLine.contains("node") { return .javascript }
            if firstLine.contains("php") { return .php }
            if firstLine.contains("sh") { return .shell }
        }
        if content.hasPrefix("<?xml") { return .xml }
        return .plainText
    }

    public var commentSyntax: CommentSyntax? {
        switch self {
        case .plainText, .json, .markdown: return nil
        case .c, .cpp, .csharp, .java, .javascript, .typescript, .swift, .go, .rust, .php: return .line("//")
        case .python, .ruby, .shell, .yaml: return .line("#")
        case .sql: return .line("--")
        case .ini: return .line(";")
        case .html, .xml: return .block(open: "<!--", close: "-->")
        case .css: return .block(open: "/*", close: "*/")
        }
    }

    // MARK: - Highlighting rules

    private static let blockComment = TokenRule(.comment, #"/\*[\s\S]*?(?:\*/|\z)"#)
    private static let slashComment = TokenRule(.comment, #"//[^\n]*"#)
    private static let hashComment = TokenRule(.comment, #"#[^\n]*"#)
    private static let doubleString = TokenRule(.string, #""(?:[^"\\\n]|\\.)*"?"#)
    private static let singleString = TokenRule(.string, #"'(?:[^'\\\n]|\\.)*'?"#)
    private static let backtickString = TokenRule(.string, #"`(?:[^`\\]|\\.)*`?"#)
    private static let number = TokenRule(.number, #"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)[uUlLfFdDmM]*\b"#)
    private static let cPreprocessor = TokenRule(.preprocessor, #"^[ \t]*#[ \t]*[a-z]+(?:[^\n\\]|\\[\s\S])*"#)

    private static func keywords(_ words: String, caseInsensitive: Bool = false) -> TokenRule {
        let alternation = words.split(separator: " ").joined(separator: "|")
        let body = caseInsensitive ? "(?i:\(alternation))" : "(?:\(alternation))"
        return TokenRule(.keyword, "\\b\(body)\\b")
    }

    private static let cKeywords = "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while bool true false NULL _Bool"
    private static let cppKeywords = cKeywords + " alignas alignof and asm catch class constexpr consteval constinit co_await co_return co_yield concept decltype delete dynamic_cast explicit export friend mutable namespace new noexcept not nullptr operator or override final private protected public reinterpret_cast requires static_assert static_cast template this thread_local throw try typeid typename using virtual wchar_t nil self super id @interface @implementation @end @property @protocol"

    /// Rules in priority order; at any position the earliest-starting match
    /// wins, and ties go to the rule listed first.
    public var rules: [TokenRule] {
        switch self {
        case .plainText:
            return []
        case .c:
            return [Self.blockComment, Self.slashComment, Self.cPreprocessor, Self.doubleString, Self.singleString, Self.number, Self.keywords(Self.cKeywords)]
        case .cpp:
            return [Self.blockComment, Self.slashComment, Self.cPreprocessor, Self.doubleString, Self.singleString, Self.number, Self.keywords(Self.cppKeywords)]
        case .csharp:
            return [Self.blockComment, Self.slashComment, Self.cPreprocessor,
                    TokenRule(.string, #"@"(?:[^"]|"")*"?"#), Self.doubleString, Self.singleString, Self.number,
                    Self.keywords("abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly record ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using var virtual void volatile while async await get set init value yield where")]
        case .java:
            return [Self.blockComment, Self.slashComment, TokenRule(.preprocessor, #"@\w+"#), Self.doubleString, Self.singleString, Self.number,
                    Self.keywords("abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new null package private protected public return short static strictfp super switch synchronized this throw throws transient true false try var void volatile while record sealed permits yield fun val when object companion data override open internal lateinit")]
        case .javascript, .typescript:
            let base = "async await break case catch class const continue debugger default delete do else export extends false finally for from function get if import in instanceof let new null of return set static super switch this throw true try typeof undefined var void while with yield"
            let words = self == .typescript ? base + " abstract any as asserts boolean declare enum implements infer interface is keyof namespace never number private protected public readonly satisfies string symbol type unknown" : base
            return [Self.blockComment, Self.slashComment, Self.backtickString, Self.doubleString, Self.singleString, Self.number, Self.keywords(words)]
        case .swift:
            return [Self.blockComment, Self.slashComment, TokenRule(.string, #""""[\s\S]*?(?:"""|\z)"#), Self.doubleString,
                    TokenRule(.preprocessor, #"(?:@\w+|#\w+)"#), Self.number,
                    Self.keywords("actor associatedtype async await break case catch class continue default defer deinit do else enum extension fallthrough false fileprivate for func guard if import in init inout internal is let nil open operator private protocol public repeat rethrows return self Self some any static struct subscript super switch throw throws true try typealias var where while weak unowned lazy mutating nonmutating override final required convenience dynamic indirect consuming borrowing sending nonisolated isolated")]
        case .go:
            return [Self.blockComment, Self.slashComment, Self.backtickString, Self.doubleString, Self.singleString, Self.number,
                    Self.keywords("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var nil true false iota bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any")]
        case .rust:
            return [Self.blockComment, Self.slashComment, TokenRule(.preprocessor, #"#!?\[[^\]\n]*\]"#), Self.doubleString,
                    TokenRule(.string, #"'(?:[^'\\\n]|\\.)'"#), Self.number,
                    Self.keywords("as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Some None Result Ok Err Box")]
        case .python:
            return [Self.hashComment, TokenRule(.string, #"[rRbBfFuU]{0,2}(?:"""[\s\S]*?(?:"""|\z)|'''[\s\S]*?(?:'''|\z))"#),
                    TokenRule(.string, #"[rRbBfFuU]{0,2}(?:"(?:[^"\\\n]|\\.)*"?|'(?:[^'\\\n]|\\.)*'?)"#),
                    TokenRule(.preprocessor, #"^[ \t]*@[\w.]+"#), Self.number,
                    Self.keywords("False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case self print len range")]
        case .ruby:
            return [Self.hashComment, Self.doubleString, Self.singleString, TokenRule(.preprocessor, #":[A-Za-z_]\w*|@{1,2}\w+"#), Self.number,
                    Self.keywords("BEGIN END alias and begin break case class def do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield require require_relative attr_accessor attr_reader puts")]
        case .php:
            return [Self.blockComment, Self.slashComment, Self.hashComment, Self.doubleString, Self.singleString,
                    TokenRule(.preprocessor, #"\$\w+|<\?php|\?>"#), Self.number,
                    Self.keywords("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile enum extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new null or print private protected public readonly require require_once return static switch throw trait try true false unset use var while yield", caseInsensitive: true)]
        case .shell:
            return [TokenRule(.comment, #"(?:^|(?<=[ \t;]))#[^\n]*"#), Self.doubleString, TokenRule(.string, #"'[^']*'?"#),
                    TokenRule(.preprocessor, #"\$(?:\{[^}\n]*\}|\w+|[@*#?$!0-9-])"#), Self.number,
                    Self.keywords("if then else elif fi case esac for select while until do done in function time return exit break continue local export readonly declare unset shift source alias echo printf read set test true false cd")]
        case .sql:
            return [Self.blockComment, TokenRule(.comment, #"--[^\n]*"#), Self.singleString, TokenRule(.string, #""[^"\n]*"?"#), Self.number,
                    Self.keywords("add all alter and any as asc begin between by case cast check column commit constraint create cross database default delete desc distinct drop else end exists foreign from full group having if in index inner insert into is join key left like limit not null offset on or order outer primary references returning right rollback select set table then top transaction truncate union unique update values view when where with int integer varchar char text date datetime timestamp boolean decimal float bigint serial count sum avg min max", caseInsensitive: true)]
        case .html, .xml:
            return [TokenRule(.comment, #"<!--[\s\S]*?(?:-->|\z)"#), TokenRule(.preprocessor, #"<!\[CDATA\[[\s\S]*?(?:\]\]>|\z)|<[!?][^>\n]*>?"#),
                    TokenRule(.tag, #"</?[A-Za-z_][\w:.-]*|/?>"#), TokenRule(.attribute, #"\b[\w:.-]+(?=\s*=\s*["'])"#),
                    TokenRule(.string, #"(?<==)\s*(?:"[^"]*"|'[^']*')"#), TokenRule(.number, #"&#?\w+;"#)]
        case .css:
            return [Self.blockComment, Self.doubleString, Self.singleString, TokenRule(.keyword, #"@[\w-]+|!important"#),
                    TokenRule(.attribute, #"(?<![\w-])[\w-]+(?=\s*:[^\n{]*;)"#), TokenRule(.number, #"#[0-9a-fA-F]{3,8}\b|-?\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|s|ms|deg|fr|pt)?\b"#),
                    TokenRule(.tag, #"[.#][A-Za-z_][\w-]*"#)]
        case .json:
            return [TokenRule(.attribute, #""(?:[^"\\\n]|\\.)*"(?=\s*:)"#), Self.doubleString, Self.slashComment, Self.blockComment,
                    TokenRule(.number, #"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#), Self.keywords("true false null")]
        case .yaml:
            return [TokenRule(.comment, #"(?:^|(?<=\s))#[^\n]*"#), TokenRule(.heading, #"^(?:---|\.\.\.)[ \t]*$"#),
                    TokenRule(.attribute, #"^[ \t]*(?:- )?[^\s:#'"][^:\n#]*(?=:(?:\s|$))"#), Self.doubleString, Self.singleString,
                    TokenRule(.preprocessor, #"[&*][\w-]+|![\w!/-]+"#), Self.number, Self.keywords("true false null yes no on off True False Null")]
        case .ini:
            return [TokenRule(.comment, #"^[ \t]*[;#][^\n]*"#), TokenRule(.heading, #"^[ \t]*\[[^\]\n]*\]"#),
                    TokenRule(.attribute, #"^[ \t]*[^=:\n;#\[][^=:\n]*(?=[=:])"#), Self.doubleString, Self.singleString, Self.number,
                    Self.keywords("true false yes no on off")]
        case .markdown:
            return [TokenRule(.string, #"^[ \t]*(?:```|~~~)[\s\S]*?(?:^[ \t]*(?:```|~~~)[ \t]*$|\z)"#), TokenRule(.heading, #"^#{1,6}[ \t][^\n]*|^[^\n]+\n(?:=+|-+)[ \t]*$"#),
                    TokenRule(.comment, #"^[ \t]*>[^\n]*|<!--[\s\S]*?(?:-->|\z)"#), TokenRule(.string, #"`[^`\n]+`"#),
                    TokenRule(.attribute, #"!?\[[^\]\n]*\]\([^)\n]*\)"#), TokenRule(.keyword, #"\*\*[^*\n]+\*\*|__[^_\n]+__"#),
                    TokenRule(.preprocessor, #"^[ \t]*(?:[-*+]|\d+[.)])(?=[ \t])"#)]
        }
    }
}
