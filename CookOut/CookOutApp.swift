//
//  CookOutApp.swift
//  CookOut
//
//  Created by Bumblebee on 8/29/26.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct CookOutApp: App {
    @AppStorage("cookout.appearance.v2") private var appearanceRaw = AppAppearance.dark.rawValue
    @AppStorage("cookout.palette") private var paletteRaw = AppPalette.rainbow.rawValue

    init() {
#if os(macOS)
        // Loading the artwork directly keeps the Dock icon current even when
        // Launch Services has cached an older development icon.
        if let icon = NSImage(named: NSImage.Name("LaunchLogo")) {
            NSApplication.shared.applicationIconImage = icon
        } else if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                  let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.cookOutPalette, AppPalette(rawValue: paletteRaw) ?? .rainbow)
                .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
                .dynamicTypeSize(.xLarge ... .accessibility5)
        }
    }
}
