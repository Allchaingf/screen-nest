//  ScreenNestApp.swift
//  Screen Nest
//
//  Entry point. Splash → (first launch only) Onboarding → House Setup → Main.
//  There is no account, no login and no welcome wall anywhere in this app.

import SwiftUI

@main
struct ScreenNestApp: App {

    @StateObject private var store = DataStore.shared
    @AppStorage(NestDefaults.theme) private var themeRaw: String = NestTheme.system.rawValue
    @AppStorage(NestDefaults.density) private var densityRaw: String = NestDensity.cosy.rawValue

    private var theme: NestTheme { NestTheme(rawValue: themeRaw) ?? .system }
    private var density: NestDensity { NestDensity(rawValue: densityRaw) ?? .cosy }

    init() {
        NestAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.nestDensity, density)
                .preferredColorScheme(theme.colorScheme)
                .tint(NestColor.amber)
        }
    }
}

/// UIKit-level appearance so system-drawn chrome matches the paper.
enum NestAppearance {
    static func apply() {
        UITextView.appearance().backgroundColor = .clear
        UIScrollView.appearance().keyboardDismissMode = .interactive
    }
}
