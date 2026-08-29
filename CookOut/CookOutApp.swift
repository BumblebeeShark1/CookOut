//
//  CookOutApp.swift
//  CookOut
//
//  Created by Bumblebee on 8/29/26.
//

import SwiftUI

@main
struct CookOutApp: App {
    @AppStorage("cookout.appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage("cookout.palette") private var paletteRaw = AppPalette.rainbow.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.cookOutPalette, AppPalette(rawValue: paletteRaw) ?? .rainbow)
                .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
        }
    }
}
