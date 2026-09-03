import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("cookout.appearance.v2") private var appearanceRaw = AppAppearance.dark.rawValue
    @AppStorage("cookout.palette") private var paletteRaw = AppPalette.rainbow.rawValue

    private var palette: AppPalette { AppPalette(rawValue: paletteRaw) ?? .rainbow }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { option in
                            Label(option.rawValue, systemImage: option.symbol).tag(option.rawValue)
                        }
                    }.pickerStyle(.segmented)
                }
                Section("Color theme") {
                    ForEach(AppPalette.allCases) { option in
                        Button { paletteRaw = option.rawValue } label: {
                            HStack {
                                Circle().fill(option.gradient).frame(width: 34, height: 34)
                                Text(option.rawValue).foregroundStyle(.primary)
                                Spacer()
                                if paletteRaw == option.rawValue { Image(systemName: "checkmark.circle.fill").foregroundStyle(option.accent) }
                            }
                        }
                    }
                }
                Section("Preview") {
                    VStack(alignment: .leading, spacing: 12) {
                        Capsule().fill(palette.gradient).frame(height: 5)
                        Label("Mom's favorite recipe", systemImage: "heart.fill").font(.headline)
                        Text("Colorful accents with a calm, readable background.").foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background(for: colorScheme))
            .navigationTitle("Appearance")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(palette.accent)
    }
}
