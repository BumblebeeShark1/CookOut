import SwiftUI
import CoreText

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
    case parchment = "Parchment", rainbow = "Rainbow", sunset = "Sunset", garden = "Garden", berry = "Berry", ocean = "Ocean"
    var id: Self { self }
    var colors: [Color] {
        switch self {
        case .parchment: [CookOutTheme.olive, CookOutTheme.sage]
        case .rainbow: [CookOutTheme.coral, CookOutTheme.orange, CookOutTheme.mango, CookOutTheme.mint, CookOutTheme.seaGlass, CookOutTheme.berry]
        case .sunset: [CookOutTheme.orange, CookOutTheme.coral, CookOutTheme.berry]
        case .garden: [CookOutTheme.mint, CookOutTheme.seaGlass, CookOutTheme.mango]
        case .berry: [CookOutTheme.berry, CookOutTheme.coral, CookOutTheme.orange]
        case .ocean: [CookOutTheme.slate, CookOutTheme.seaGlass, CookOutTheme.sage]
        }
    }
    var accent: Color { colors[0] }
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing) }
    func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? CookOutTheme.graphene : CookOutTheme.parchment
    }
    var softGradient: LinearGradient {
        LinearGradient(colors: [colors[0].opacity(0.14), colors.last!.opacity(0.07), .clear], startPoint: .top, endPoint: .bottom)
    }
    func ambientGradient(for scheme: ColorScheme) -> LinearGradient {
        let strength = scheme == .dark ? 0.025 : 0.035
        return LinearGradient(colors: [colors[0].opacity(strength), colors.last!.opacity(strength * 0.45), .clear], startPoint: .top, endPoint: .bottom)
    }
}

private struct CookOutPaletteKey: EnvironmentKey { static let defaultValue = AppPalette.parchment }
extension EnvironmentValues {
    var cookOutPalette: AppPalette {
        get { self[CookOutPaletteKey.self] }
        set { self[CookOutPaletteKey.self] = newValue }
    }
}

enum CookOutTheme {
    static let parchment = Color(red: 0.94, green: 0.90, blue: 0.83)
    static let ivory = Color(red: 0.99, green: 0.97, blue: 0.92)
    static let ink = Color(red: 0.23, green: 0.25, blue: 0.19)
    static let olive = Color(red: 0.32, green: 0.38, blue: 0.24)
    static let sage = Color(red: 0.48, green: 0.53, blue: 0.38)
    static let graphene = Color(red: 0.10, green: 0.11, blue: 0.09)
    static let grapheneRaised = Color(red: 0.15, green: 0.16, blue: 0.13)
    static let orange = Color(red: 0.58, green: 0.35, blue: 0.20)
    static let coral = Color(red: 0.65, green: 0.32, blue: 0.27)
    static let mango = Color(red: 0.57, green: 0.44, blue: 0.17)
    static let seaGlass = Color(red: 0.28, green: 0.47, blue: 0.46)
    static let slate = Color(red: 0.39, green: 0.42, blue: 0.47)
    static let mint = olive
    static let berry = Color(red: 0.47, green: 0.36, blue: 0.43)
    static let hero = LinearGradient(colors: [olive, sage], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let rainbow = LinearGradient(
        colors: [coral, orange, mango, mint, seaGlass, berry],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let softBackground = LinearGradient(colors: [orange.opacity(0.10), berry.opacity(0.05), Color.clear], startPoint: .top, endPoint: .bottom)

    static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? grapheneRaised : ivory
    }

    static func border(for scheme: ColorScheme) -> Color {
        (scheme == .dark ? Color.white : ink).opacity(0.12)
    }

    static func motion(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88)
    }
}

enum CookOutTypography {
    // A licensed Klop OTF/TTF added to the app's resources is registered on-device.
    // Missing or invalid font files leave all titles readable with the serif fallback.
    static let displayName: String? = {
        for ext in ["otf", "ttf"] {
            for url in Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
                where url.lastPathComponent.lowercased().contains("klop") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        let names = CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
        return names.sorted().first { $0.lowercased().hasPrefix("klop") }
    }()

    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        if let displayName { return .custom(displayName, size: size, relativeTo: style) }
        return .custom("Georgia", size: size, relativeTo: style)
    }
}

struct CookOutPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

private struct CookOutCanvas: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cookOutPalette) private var palette

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(palette.background(for: colorScheme))
            .tint(palette.accent)
    }
}

extension View {
    func cookOutCanvas() -> some View { modifier(CookOutCanvas()) }
}

extension FolderColor {
    var tint: Color {
        switch self {
        case .coral: CookOutTheme.coral
        case .orange: CookOutTheme.orange
        case .mango: CookOutTheme.mango
        case .mint: CookOutTheme.mint
        case .cyan: CookOutTheme.seaGlass
        case .berry: CookOutTheme.berry
        case .indigo: CookOutTheme.slate
        }
    }
}

extension MealType {
    var tint: Color {
        switch self {
        case .breakfast: CookOutTheme.mango
        case .lunch: CookOutTheme.mint
        case .dinner: CookOutTheme.coral
        case .dessert: CookOutTheme.berry
        case .snack: CookOutTheme.orange
        case .drink: CookOutTheme.seaGlass
        case .other: CookOutTheme.slate
        }
    }
}
