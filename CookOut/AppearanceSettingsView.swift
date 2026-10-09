import SwiftUI

struct AppearanceSettingsView: View {
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("cookout.appearance.v2") private var appearanceRaw = AppAppearance.light.rawValue
    @AppStorage("cookout.palette") private var paletteRaw = AppPalette.parchment.rawValue
    private var palette: AppPalette { AppPalette(rawValue: paletteRaw) ?? .parchment }

    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "A personal touch", title: "Make yourself at home.", subtitle: "A warm, quiet space for your everyday cooking. Choose the look that feels like you.")
                CookOutPanel(title: "Light & shade", subtitle: "Follow your device or choose your favorite.", symbol: "sun.max") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                        ForEach(AppAppearance.allCases) { option in
                            Button { appearanceRaw = option.rawValue } label: {
                                VStack(spacing: 14) {
                                    Image(systemName: option.symbol).font(.system(size: 28, weight: .light))
                                    Text(option.rawValue).font(.subheadline.weight(.medium))
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 24)
                                .background(palette.accent.opacity(appearanceRaw == option.rawValue ? 0.12 : 0.035), in: RoundedRectangle(cornerRadius: 16))
                                .overlay { RoundedRectangle(cornerRadius: 16).stroke(appearanceRaw == option.rawValue ? palette.accent : CookOutTheme.border(for: colorScheme)) }
                            }
                            .buttonStyle(CookOutPressStyle()).foregroundStyle(.primary)
                            .accessibilityAddTraits(appearanceRaw == option.rawValue ? .isSelected : [])
                        }
                    }
                }
                CookOutPanel(title: "Your palette", subtitle: "Soft color, with parchment at its heart.", symbol: "paintpalette") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 14)], spacing: 14) {
                        ForEach(AppPalette.allCases) { option in
                            Button { paletteRaw = option.rawValue } label: {
                                VStack(alignment: .leading, spacing: 20) {
                                    HStack(spacing: -8) {
                                        ForEach(Array(option.colors.enumerated()), id: \.offset) { _, color in
                                            Circle().fill(color).frame(width: 30, height: 30)
                                                .overlay { Circle().stroke(CookOutTheme.surface(for: colorScheme), lineWidth: 3) }
                                        }
                                    }
                                    HStack {
                                        Text(option.rawValue).font(.subheadline.weight(.medium))
                                        Spacer()
                                        Image(systemName: paletteRaw == option.rawValue ? "checkmark.circle.fill" : "circle").foregroundStyle(.secondary)
                                    }
                                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(option.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                                .overlay { RoundedRectangle(cornerRadius: 16).stroke(paletteRaw == option.rawValue ? option.accent : CookOutTheme.border(for: colorScheme)) }
                            }.buttonStyle(CookOutPressStyle()).foregroundStyle(.primary)
                                .accessibilityAddTraits(paletteRaw == option.rawValue ? .isSelected : [])
                        }
                    }
                }
                CookOutPanel(title: "A little preview", symbol: "eye") {
                    HStack(alignment: .top, spacing: 18) {
                        Image(systemName: "leaf").font(.system(size: 32, weight: .light)).foregroundStyle(palette.accent)
                            .frame(width: 70, height: 90).background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 12) {
                            Text("WEEKNIGHT FAVORITE").font(.caption2).tracking(2).foregroundStyle(.secondary)
                            Text("Fresh basil pasta").font(CookOutTypography.display(30, relativeTo: .title))
                            Text("Simple ingredients. A recipe worth coming back to.").foregroundStyle(.secondary)
                            Label("25 minutes · 2 servings", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: paletteRaw)
            .navigationTitle("Appearance")
            .toolbar {
                if !embedded { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }.tint(palette.accent)
    }
}
