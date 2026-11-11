import SwiftUI

enum RunsRenderer {
    private static let maxRunsPerLine = 180
    private static let maxCharsPerLine = 512

    /// Build per-line attributed strings for efficient LazyVStack rendering.
    static func buildLines(from lines: [[TerminalRun]], fontSize: CGFloat) -> [AttributedString] {
        let theme = TerminalColors.current
        let defaultFG = theme.foreground
        let defaultBG = theme.background
        let baseFont = Font.system(size: fontSize, weight: .regular, design: .monospaced)
        let boldFont = Font.system(size: fontSize, weight: .bold, design: .monospaced)
        let italicFont = baseFont.italic()
        let boldItalicFont = boldFont.italic()

        return lines.map { runs in
            var line = AttributedString()

            if runs.isEmpty {
                // Empty line — use a space so Text has correct line height
                var attrs = AttributeContainer()
                attrs.font = baseFont
                line.append(AttributedString(" ", attributes: attrs))
                return line
            }

            var remainingChars = maxCharsPerLine
            for run in runs.prefix(maxRunsPerLine) {
                guard remainingChars > 0 else {
                    break
                }

                if run.t.isEmpty {
                    continue
                }

                let text: String
                let runLength = run.t.count
                if runLength <= remainingChars {
                    text = run.t
                    remainingChars -= runLength
                } else {
                    text = String(run.t.prefix(remainingChars))
                    remainingChars = 0
                }

                var attrs = AttributeContainer()

                attrs.font = run.i == true ? (run.b == true ? boldItalicFont : italicFont)
                    : (run.b == true ? boldFont : baseFont)

                let fgColor: Color
                if run.fg == "_defBg" {
                    fgColor = defaultBG
                } else if run.fg == "_defFg" {
                    fgColor = defaultFG
                } else {
                    fgColor = theme.color(for: run.fg) ?? defaultFG
                }
                attrs.foregroundColor = (run.d == true) ? fgColor.opacity(0.5) : fgColor

                if run.bg == "_defFg" {
                    attrs.backgroundColor = defaultFG
                } else if run.bg == "_defBg" {
                    attrs.backgroundColor = defaultBG
                } else if let bg = theme.color(for: run.bg) {
                    attrs.backgroundColor = bg
                }

                if run.u == true {
                    attrs.underlineStyle = .single
                }

                line.append(AttributedString(Self.forceTextPresentation(text), attributes: attrs))
            }

            return line
        }
    }

    /// Characters that Apple renders as emoji by default but should be text glyphs
    /// in a terminal context. Appending U+FE0E forces text presentation.
    private static let emojiProne: Set<Unicode.Scalar> = {
        var s = Set<Unicode.Scalar>()
        // Common terminal symbols that get emoji-ified
        let ranges: [(UInt32, UInt32)] = [
            (0x23E9, 0x23FA),   // ⏩–⏺ (transport/media symbols)
            (0x25A0, 0x25FF),   // ■–◿ (geometric shapes)
            (0x2600, 0x26FF),   // ☀–⛿ (misc symbols)
            (0x2700, 0x27BF),   // ✀–➿ (dingbats)
            (0x2B05, 0x2B55),   // ⬅–⭕ (arrows, shapes)
        ]
        for (lo, hi) in ranges {
            for v in lo...hi {
                if let sc = Unicode.Scalar(v) { s.insert(sc) }
            }
        }
        // Individual characters
        for ch: UInt32 in [0x2328, 0x23CF, 0x25B6, 0x25C0, 0x2934, 0x2935, 0x203C, 0x2049] {
            if let sc = Unicode.Scalar(ch) { s.insert(sc) }
        }
        return s
    }()

    /// Insert U+FE0E after any character that Apple might render as emoji.
    private static func forceTextPresentation(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { emojiProne.contains($0) }) else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        for char in text {
            result.append(char)
            if char.unicodeScalars.count == 1,
               let scalar = char.unicodeScalars.first,
               emojiProne.contains(scalar) {
                result.append("\u{FE0E}")
            }
        }
        return result
    }

    /// Legacy single-string builder (used by watch PhoneBridge for backward compat).
    static func build(from lines: [[TerminalRun]], fontSize: CGFloat) -> AttributedString {
        let perLine = buildLines(from: lines, fontSize: fontSize)
        var result = AttributedString()
        for (i, line) in perLine.enumerated() {
            if i > 0 { result.append(AttributedString("\n")) }
            result.append(line)
        }
        return result
    }
}
