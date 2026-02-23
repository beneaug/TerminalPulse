import SwiftUI

struct TerminalTheme {
    let black: Color
    let red: Color
    let green: Color
    let yellow: Color
    let blue: Color
    let magenta: Color
    let cyan: Color
    let white: Color
    let brBlack: Color
    let brRed: Color
    let brGreen: Color
    let brYellow: Color
    let brBlue: Color
    let brMagenta: Color
    let brCyan: Color
    let brWhite: Color
    let foreground: Color
    let background: Color

    /// Pre-built lookup table — created once per theme, not per call.
    let namedColors: [String: Color]

    init(black: Color, red: Color, green: Color, yellow: Color,
         blue: Color, magenta: Color, cyan: Color, white: Color,
         brBlack: Color, brRed: Color, brGreen: Color, brYellow: Color,
         brBlue: Color, brMagenta: Color, brCyan: Color, brWhite: Color,
         foreground: Color, background: Color) {
        self.black = black; self.red = red; self.green = green; self.yellow = yellow
        self.blue = blue; self.magenta = magenta; self.cyan = cyan; self.white = white
        self.brBlack = brBlack; self.brRed = brRed; self.brGreen = brGreen; self.brYellow = brYellow
        self.brBlue = brBlue; self.brMagenta = brMagenta; self.brCyan = brCyan; self.brWhite = brWhite
        self.foreground = foreground; self.background = background
        self.namedColors = [
            "black": black, "red": red, "green": green, "yellow": yellow,
            "blue": blue, "magenta": magenta, "cyan": cyan, "white": white,
            "brBlack": brBlack, "brRed": brRed, "brGreen": brGreen, "brYellow": brYellow,
            "brBlue": brBlue, "brMagenta": brMagenta, "brCyan": brCyan, "brWhite": brWhite,
        ]
    }

    func color(for name: String?) -> Color? {
        guard let name else { return nil }
        if let named = namedColors[name] {
            return named
        }
        if name.hasPrefix("#"), name.count == 7 {
            return Color(hex: name)
        }
        return nil
    }
}

enum TerminalColors {
    // MARK: - Theme Definitions

    static let defaultTheme = TerminalTheme(
        black: Color(red: 0.1, green: 0.1, blue: 0.1),
        red: Color(red: 0.8, green: 0.2, blue: 0.2),
        green: Color(red: 0.2, green: 0.8, blue: 0.2),
        yellow: Color(red: 0.8, green: 0.8, blue: 0.2),
        blue: Color(red: 0.3, green: 0.5, blue: 0.9),
        magenta: Color(red: 0.8, green: 0.3, blue: 0.8),
        cyan: Color(red: 0.3, green: 0.8, blue: 0.8),
        white: Color(red: 0.75, green: 0.75, blue: 0.75),
        brBlack: Color(red: 0.4, green: 0.4, blue: 0.4),
        brRed: Color(red: 1.0, green: 0.33, blue: 0.33),
        brGreen: Color(red: 0.33, green: 1.0, blue: 0.33),
        brYellow: Color(red: 1.0, green: 1.0, blue: 0.33),
        brBlue: Color(red: 0.45, green: 0.65, blue: 1.0),
        brMagenta: Color(red: 1.0, green: 0.45, blue: 1.0),
        brCyan: Color(red: 0.45, green: 1.0, blue: 1.0),
        brWhite: .white,
        foreground: Color(red: 0.85, green: 0.85, blue: 0.85),
        background: .black
    )

    static let solarizedTheme = TerminalTheme(
        black: Color(hex: "#073642") ?? .gray,
        red: Color(hex: "#dc322f") ?? .gray,
        green: Color(hex: "#859900") ?? .gray,
        yellow: Color(hex: "#b58900") ?? .gray,
        blue: Color(hex: "#268bd2") ?? .gray,
        magenta: Color(hex: "#d33682") ?? .gray,
        cyan: Color(hex: "#2aa198") ?? .gray,
        white: Color(hex: "#eee8d5") ?? .gray,
        brBlack: Color(hex: "#586e75") ?? .gray,
        brRed: Color(hex: "#cb4b16") ?? .gray,
        brGreen: Color(hex: "#859900") ?? .gray,
        brYellow: Color(hex: "#b58900") ?? .gray,
        brBlue: Color(hex: "#268bd2") ?? .gray,
        brMagenta: Color(hex: "#6c71c4") ?? .gray,
        brCyan: Color(hex: "#2aa198") ?? .gray,
        brWhite: Color(hex: "#fdf6e3") ?? .gray,
        foreground: Color(hex: "#839496") ?? .gray,
        background: Color(hex: "#002b36") ?? .gray
    )

    static let draculaTheme = TerminalTheme(
        black: Color(hex: "#21222c") ?? .gray,
        red: Color(hex: "#ff5555") ?? .gray,
        green: Color(hex: "#50fa7b") ?? .gray,
        yellow: Color(hex: "#f1fa8c") ?? .gray,
        blue: Color(hex: "#bd93f9") ?? .gray,
        magenta: Color(hex: "#ff79c6") ?? .gray,
        cyan: Color(hex: "#8be9fd") ?? .gray,
        white: Color(hex: "#f8f8f2") ?? .gray,
        brBlack: Color(hex: "#6272a4") ?? .gray,
        brRed: Color(hex: "#ff6e6e") ?? .gray,
        brGreen: Color(hex: "#69ff94") ?? .gray,
        brYellow: Color(hex: "#ffffa5") ?? .gray,
        brBlue: Color(hex: "#d6acff") ?? .gray,
        brMagenta: Color(hex: "#ff92df") ?? .gray,
        brCyan: Color(hex: "#a4ffff") ?? .gray,
        brWhite: .white,
        foreground: Color(hex: "#f8f8f2") ?? .gray,
        background: Color(hex: "#282a36") ?? .gray
    )

    static let gruvboxTheme = TerminalTheme(
        black: Color(hex: "#282828") ?? .gray,
        red: Color(hex: "#cc241d") ?? .gray,
        green: Color(hex: "#98971a") ?? .gray,
        yellow: Color(hex: "#d79921") ?? .gray,
        blue: Color(hex: "#458588") ?? .gray,
        magenta: Color(hex: "#b16286") ?? .gray,
        cyan: Color(hex: "#689d6a") ?? .gray,
        white: Color(hex: "#a89984") ?? .gray,
        brBlack: Color(hex: "#928374") ?? .gray,
        brRed: Color(hex: "#fb4934") ?? .gray,
        brGreen: Color(hex: "#b8bb26") ?? .gray,
        brYellow: Color(hex: "#fabd2f") ?? .gray,
        brBlue: Color(hex: "#83a598") ?? .gray,
        brMagenta: Color(hex: "#d3869b") ?? .gray,
        brCyan: Color(hex: "#8ec07c") ?? .gray,
        brWhite: Color(hex: "#ebdbb2") ?? .gray,
        foreground: Color(hex: "#ebdbb2") ?? .gray,
        background: Color(hex: "#1d2021") ?? .gray
    )

    private static let themes: [String: TerminalTheme] = [
        "default": defaultTheme,
        "solarized": solarizedTheme,
        "dracula": draculaTheme,
        "gruvbox": gruvboxTheme,
    ]

    /// Cached theme — avoids reading UserDefaults on every color lookup.
    private static var _cachedTheme: TerminalTheme?
    private static var _cachedThemeKey: String?

    static var current: TerminalTheme {
        let key = UserDefaults.standard.string(forKey: "colorTheme") ?? "default"
        if key == _cachedThemeKey, let cached = _cachedTheme {
            return cached
        }
        let theme = themes[key] ?? defaultTheme
        _cachedThemeKey = key
        _cachedTheme = theme
        return theme
    }

    /// Call after changing the theme to invalidate the cache.
    static func invalidateCache() {
        _cachedThemeKey = nil
        _cachedTheme = nil
    }

    // MARK: - Convenience accessors (backwards compatible)

    static var defaultForeground: Color { current.foreground }
    static var defaultBackground: Color { current.background }

    static func color(for name: String?) -> Color? {
        current.color(for: name)
    }
}

extension Color {
    init?(hex: String) {
        var h = hex
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        let r = Double((val >> 16) & 0xFF) / 255.0
        let g = Double((val >> 8) & 0xFF) / 255.0
        let b = Double(val & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
