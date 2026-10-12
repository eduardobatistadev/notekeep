import Foundation

/// UTF-16 offsets of every line start, for line numbers and caret position.
public struct LineIndex: Sendable {
    /// Always begins with 0; a trailing newline produces a final empty line.
    public private(set) var lineStarts: [Int]
    public private(set) var length: Int

    public init(text: NSString) {
        var starts = [0]
        let length = text.length
        let chunkSize = 64 * 1024
        var buffer = [unichar](repeating: 0, count: chunkSize)
        var offset = 0
        while offset < length {
            let count = min(chunkSize, length - offset)
            text.getCharacters(&buffer, range: NSRange(location: offset, length: count))
            for i in 0..<count where buffer[i] == 0x0A {
                starts.append(offset + i + 1)
            }
            offset += count
        }
        self.lineStarts = starts
        self.length = length
    }

    public init(text: String) {
        self.init(text: text as NSString)
    }

    public var lineCount: Int { lineStarts.count }

    /// Zero-based line containing the UTF-16 offset.
    public func line(at offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Zero-based column of the offset within its line.
    public func column(at offset: Int) -> Int {
        offset - lineStarts[line(at: offset)]
    }
}
