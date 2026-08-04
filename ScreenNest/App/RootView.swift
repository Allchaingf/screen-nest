//  RootView.swift
//  Screen Nest
//
//  Splash → (first launch only) Onboarding → House Setup → Main.
//  There is no auth, no login, no welcome wall and no account screen anywhere.

import SwiftUI

enum RootPhase {
    case splash
    case onboarding
    case setup
    case main
}

struct RootView: View {
    @EnvironmentObject private var store: DataStore
    @AppStorage(NestDefaults.hasOnboarded) private var hasOnboarded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var phase: RootPhase = .splash

    var body: some View {
        ZStack {
            NestColor.ground.ignoresSafeArea()

            switch phase {
            case .splash:
                SplashView { advanceFromSplash() }
                    .transition(.opacity)

            case .onboarding:
                OnboardingView {
                    withAnimation(transitionAnimation) { phase = .setup }
                }
                .transition(entryTransition)

            case .setup:
                SetupView(store: store) {
                    withAnimation(transitionAnimation) { phase = .main }
                }
                .transition(entryTransition)

            case .main:
                MainTabView()
                    .transition(entryTransition)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background { store.saveNow() }
        }
    }

    private var transitionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : NestMotion.fill
    }

    /// The signature transition: content arrives the way the window fills.
    private var entryTransition: AnyTransition {
        reduceMotion ? .opacity : .nestFill
    }

    private func advanceFromSplash() {
        let next: RootPhase
        if !hasOnboarded {
            next = .onboarding
        } else if !store.profile.setupCompleted {
            next = .setup
        } else {
            next = .main
        }
        withAnimation(transitionAnimation) { phase = next }
    }
}
