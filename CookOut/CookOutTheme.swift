import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: Self { self }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
    var symbol: String {
        switch self { case .system: "circle.lefthalf.filled"; case .light: "sun.max.fill"; case .dark: "moon.stars.fill" }
    }
}

enum AppPalette: String, CaseIterable, Identifiable {
    case rainbow = "Rainbow", sunset = "Sunset", garden = "Garden", berry = "Berry", ocean = "Ocean"
    var id: Self { self }
    var colors: [Color] {
        switch self {
        case .rainbow: [CookOutTheme.coral, CookOutTheme.orange, CookOutTheme.mango, CookOutTheme.mint, .cyan, CookOutTheme.berry]
        case .sunset: [CookOutTheme.orange, CookOutTheme.coral, .pink]
        case .garden: [CookOutTheme.mint, .teal, CookOutTheme.mango]
        case .berry: [CookOutTheme.berry, .pink, CookOutTheme.coral]
        case .ocean: [.blue, .cyan, .teal]
        }
    }
    var accent: Color { colors[0] }
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing) }
    func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.075, green: 0.075, blue: 0.09) : Color(red: 0.98, green: 0.97, blue: 0.95)
    }
    var softGradient: LinearGradient {
        LinearGradient(colors: [colors[0].opacity(0.14), colors.last!.opacity(0.07), .clear], startPoint: .top, endPoint: .bottom)
    }
}

private struct CookOutPaletteKey: EnvironmentKey { static let defaultValue = AppPalette.rainbow }
extension EnvironmentValues {
    var cookOutPalette: AppPalette {
        get { self[CookOutPaletteKey.self] }
        set { self[CookOutPaletteKey.self] = newValue }
    }
}

enum CookOutTheme {
    static let orange = Color(red: 1.0, green: 0.45, blue: 0.12)
    static let coral = Color(red: 0.98, green: 0.29, blue: 0.32)
    static let mango = Color(red: 1.0, green: 0.72, blue: 0.18)
    static let mint = Color(red: 0.20, green: 0.68, blue: 0.48)
    static let berry = Color(red: 0.60, green: 0.27, blue: 0.72)
    static let hero = LinearGradient(colors: [orange, coral], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let rainbow = LinearGradient(
        colors: [coral, orange, mango, mint, .cyan, berry],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let softBackground = LinearGradient(colors: [orange.opacity(0.10), berry.opacity(0.05), Color.clear], startPoint: .top, endPoint: .bottom)
}

extension MealType {
    var tint: Color {
        switch self {
        case .breakfast: CookOutTheme.mango
        case .lunch: CookOutTheme.mint
        case .dinner: CookOutTheme.coral
        case .dessert: CookOutTheme.berry
        case .snack: CookOutTheme.orange
        case .drink: .cyan
        case .other: .indigo
        }
    }
}
