import SwiftUI

enum RunsRenderer {
    /// Build per-line attributed strings for efficient LazyVStack rendering.
    static func buildLines(from lines: [[TerminalRun]], fontSize: CGFloat) -> [AttributedString] {
        let theme = TerminalColors.current
        let defaultFG = theme.foreground
        let defaultBG = theme.background
        let baseFont = Font.system(size: fontSize, weight: .regular, design: .monospaced)

        return lines.map { runs in
            var line = AttributedString()

            if runs.isEmpty {
                // Empty line — use a space so Text has correct line height
                var attrs = AttributeContainer()
                attrs.font = baseFont
                line.append(AttributedString(" ", attributes: attrs))
                return line
            }

            for run in runs {
                var attrs = AttributeContainer()

                let weight: Font.Weight = (run.b == true) ? .bold : .regular
                attrs.font = .system(size: fontSize, weight: weight, design: .monospaced)

                if run.i == true {
                    attrs.font = .system(size: fontSize, weight: weight, design: .monospaced).italic()
                }

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

                line.append(AttributedString(run.t, attributes: attrs))
            }

            return line
        }
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
