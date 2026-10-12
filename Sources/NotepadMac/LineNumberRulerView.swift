import AppKit
import EditorCore

/// Gutter with line numbers for a TextKit 1 text view.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    var lineIndex = LineIndex(text: "") {
        didSet { updateThickness() }
    }
    var currentLine = 0 {
        didSet { if currentLine != oldValue { needsDisplay = true } }
    }
    var font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular) {
        didSet { updateThickness() }
    }

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        clipsToBounds = true
        updateThickness()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    private func updateThickness() {
        let digits = max(3, String(lineIndex.lineCount).count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        let thickness = ceil(CGFloat(digits) * digitWidth + 16)
        if abs(ruleThickness - thickness) > 0.5 {
            ruleThickness = thickness
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Since macOS 14 views do not clip to bounds by default and dirtyRect
        // may extend past them; painting it all would cover the text view.
        let rect = dirtyRect.intersection(bounds)
        guard !rect.isEmpty else { return }
        NSColor.controlBackgroundColor.setFill()
        rect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()
        drawHashMarksAndLabels(in: rect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let length = (textView.string as NSString).length
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let originY = convert(NSPoint.zero, from: textView).y + textView.textContainerOrigin.y

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
        let current: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]

        var line = lineIndex.line(at: charRange.location)
        while line < lineIndex.lineCount {
            let start = lineIndex.lineStarts[line]
            if start > NSMaxRange(charRange) { break }
            let fragment: NSRect
            if start >= length {
                fragment = layoutManager.extraLineFragmentRect
                if fragment.isEmpty { break }
            } else {
                fragment = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
            }
            let label = "\(line + 1)" as NSString
            let labelHeight = label.size(withAttributes: normal).height
            let y = originY + fragment.minY + (fragment.height - labelHeight) / 2
            label.draw(in: NSRect(x: 4, y: y, width: ruleThickness - 12, height: labelHeight),
                       withAttributes: line == currentLine ? current : normal)
            line += 1
        }
    }
}
