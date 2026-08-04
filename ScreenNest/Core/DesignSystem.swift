//  DesignSystem.swift
//  Screen Nest
//
//  Single source of truth for colour, type, shape, spacing, elevation and motion.
//  No screen in this app may declare a colour, a font or a spring of its own.
//
//  VISUAL DIRECTION — loud, warm and printed.
//  Saturated cream paper, an amber gradient that carries every action, plum for
//  the evening, and one anchor ink used for the tab bar, the headlines, every
//  border and EVERY shadow. Shadows are hard offsets with zero blur, so the app
//  reads like something screen-printed rather than something rendered.
//  No thin weights. No serif faces. No hairlines. No soft shadows. No white.

import SwiftUI
import UIKit

// MARK: - Hex plumbing

extension UIColor {
    convenience init(nestHex: UInt32) {
        self.init(
            red: CGFloat((nestHex >> 16) & 0xFF) / 255.0,
            green: CGFloat((nestHex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(nestHex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

extension Color {
    init(nestHex: UInt32) { self.init(UIColor(nestHex: nestHex)) }

    /// A colour that resolves against the *rendered* interface style, so the in-app
    /// theme override in Settings genuinely repaints everything.
    static func nestDynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(nestHex: dark)
                : UIColor(nestHex: light)
        })
    }
}

// MARK: - Palette

enum NestColor {

    // The anchor. Tab bar, headlines, every border, every shadow.
    static let anchor        = Color.nestDynamic(0x241F1A, 0xF6EBD6)
    static let anchorSolid   = Color(nestHex: 0x241F1A)

    // Ground & surfaces — saturated cream, never washed out, never white.
    static let ground        = Color.nestDynamic(0xFFF3DC, 0x241F1A)
    static let groundDeep    = Color.nestDynamic(0xF6E4C4, 0x1A1613)
    static let surface       = Color.nestDynamic(0xFFFBF2, 0x332C25)
    static let surfaceSunk   = Color.nestDynamic(0xF6E7CC, 0x1E1A16)
    static let surfaceRaised = Color.nestDynamic(0xFFFBF2, 0x3D342B)

    // Line work — 1.5pt minimum, always the anchor at low alpha.
    static let hairline      = Color.nestDynamic(0x241F1A, 0xF6EBD6).opacity(0.12)
    static let hairlineSoft  = Color.nestDynamic(0x241F1A, 0xF6EBD6).opacity(0.08)
    static let border        = Color.nestDynamic(0x241F1A, 0xF6EBD6).opacity(0.20)

    // Ink
    static let ink           = Color.nestDynamic(0x241F1A, 0xFFF3DC)
    static let inkSoft       = Color.nestDynamic(0x241F1A, 0xFFF3DC).opacity(0.55)
    static let inkFaint      = Color.nestDynamic(0x241F1A, 0xFFF3DC).opacity(0.40)
    static let inkOnAmber    = Color(nestHex: 0x241F1A)
    static let onAnchor      = Color.nestDynamic(0xFFF3DC, 0x241F1A)

    // Amber — always a gradient where there is room for one.
    static let amberTop      = Color.nestDynamic(0xF2B03C, 0xF7BC55)
    static let amberBottom   = Color.nestDynamic(0xE0982A, 0xE5A337)
    static let amber         = Color.nestDynamic(0xE0982A, 0xEBA83C)
    static let amberSunk     = Color.nestDynamic(0xB87A16, 0xF2B03C)
    static let amberWash     = Color.nestDynamic(0xFBE3B4, 0x3E3222)
    static let amberGlow     = Color.nestDynamic(0xE0982A, 0xEBA83C)

    static let plum          = Color.nestDynamic(0x7A4A63, 0xC98FAE)
    static let plumSoft      = Color.nestDynamic(0xE4CFD9, 0x3B2B34)
    static let plumWash      = Color.nestDynamic(0xE4CFD9, 0x3B2B34)

    static let go            = Color.nestDynamic(0x4E9A5B, 0x6DBE7B)
    static let goWash        = Color.nestDynamic(0xD6EBDA, 0x24331F)

    static let stop          = Color.nestDynamic(0xC0392B, 0xE4695B)
    static let stopWash      = Color.nestDynamic(0xF6D9D5, 0x3A211D)

    /// The amber gradient. Every primary surface that carries an action uses it.
    static var amberGradient: LinearGradient {
        LinearGradient(colors: [amberTop, amberBottom], startPoint: .top, endPoint: .bottom)
    }

    static var amberGradientDiagonal: LinearGradient {
        LinearGradient(colors: [amberTop, amberBottom],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Watch mode: the one dark screen. Fixed in both themes.
    static let watchGround   = Color(nestHex: 0x241F1A)
    static let watchGroundLo = Color(nestHex: 0x1A1613)
    static let watchInk      = Color(nestHex: 0xFFF3DC)
    static let watchInkSoft  = Color(nestHex: 0xFFF3DC).opacity(0.60)
    static let watchAmber    = Color(nestHex: 0xF2B03C)
    static let watchPlum     = Color(nestHex: 0xC98FAE)

    /// Viewer tokens — saturated, warm, never pastel.
    static let viewerHues: [Color] = [
        Color.nestDynamic(0xE0982A, 0xF2B03C),   // amber
        Color.nestDynamic(0x7A4A63, 0xC98FAE),   // plum
        Color.nestDynamic(0x4E9A5B, 0x6DBE7B),   // leaf
        Color.nestDynamic(0xC0392B, 0xE4695B),   // clay
        Color.nestDynamic(0xB87A16, 0xE0A54A),   // honey
        Color.nestDynamic(0x6B7F3A, 0x9BB25C),   // olive
        Color.nestDynamic(0xA0522D, 0xCE7A4E),   // terracotta
        Color.nestDynamic(0x4A5C8A, 0x8095C4)    // dusk
    ]

    static func viewerHue(_ index: Int) -> Color {
        viewerHues[((index % viewerHues.count) + viewerHues.count) % viewerHues.count]
    }
}

// MARK: - Type
//
// SF Pro only. Display Heavy Italic for screen titles, Heavy for figures,
// Bold/Semibold/Medium/Regular for everything else. No Light, Thin or
// Ultralight anywhere. No serif anywhere.

enum NestFont {
    /// Screen title — set UPPERCASE by PageTitle.
    static let display      = Font.system(size: 34, weight: .heavy).italic()
    static let displaySmall = Font.system(size: 27, weight: .heavy).italic()

    static let title        = Font.system(size: 20, weight: .bold)
    static let titleTight   = Font.system(size: 20, weight: .bold)
    static let quote        = Font.system(size: 17, weight: .semibold)

    static let heading      = Font.system(size: 17, weight: .bold)
    static let body         = Font.system(size: 16, weight: .regular)
    static let bodyMedium   = Font.system(size: 16, weight: .medium)
    static let small        = Font.system(size: 13, weight: .medium)
    static let smallMedium  = Font.system(size: 13, weight: .semibold)
    static let micro        = Font.system(size: 12, weight: .medium)
    /// Section label — set UPPERCASE and tracked by SectionLabel.
    static let label        = Font.system(size: 13, weight: .semibold)

    static let figureHuge   = Font.system(size: 56, weight: .heavy)
    static let figure       = Font.system(size: 34, weight: .heavy)
    static let figureSmall  = Font.system(size: 17, weight: .bold)
    static let figureMicro  = Font.system(size: 13, weight: .bold)

    static let watchClock   = Font.system(size: 64, weight: .heavy)
    static let watchSub     = Font.system(size: 16, weight: .semibold)
    static let watchTitle   = Font.system(size: 22, weight: .bold)
    static let watchButton  = Font.system(size: 20, weight: .bold)

    static let markWord     = Font.system(size: 11, weight: .heavy)

    /// Size-driven faces that scale with the shape they sit in.
    static func tokenLetter(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy)
    }
    static func posterTitle(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }
}

/// Letter-spaced text. `Text.tracking(_:)` is iOS 16+, so tracking is applied
/// through an AttributedString kern attribute to stay on the iOS 15 floor.
func nestTracked(_ string: String, kern: CGFloat = 1.2) -> Text {
    var attributed = AttributedString(string)
    attributed.kern = kern
    return Text(attributed)
}

// MARK: - Spacing, radii, strokes

enum NestSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 22
    static let xxl: CGFloat = 30
    static let huge: CGFloat = 40

    static let gutter: CGFloat = 18
    /// Room left under scroll content so the tab bar never covers a control.
    static let tabInset: CGFloat = 116
}

enum NestRadius {
    static let card: CGFloat = 16
    static let panel: CGFloat = 16
    static let chip: CGFloat = 20
    static let button: CGFloat = 14
    static let field: CGFloat = 14
    static let icon: CGFloat = 10
    static let posterTop: CGFloat = 10
    static let posterBottom: CGFloat = 10
    /// Ticket notch cut into the sides of a film card.
    static let notch: CGFloat = 12
}

enum NestStroke {
    /// There are no hairlines in this app.
    static let hair: CGFloat = 1.5
    static let mark: CGFloat = 2
    static let heavy: CGFloat = 2.5
}

// MARK: - Elevation
//
// One device only: a hard offset shadow, 4pt down and 4pt right, zero blur,
// full-strength anchor ink. Nothing in this app is blurred or soft.

enum NestShadow {
    static let offset: CGFloat = 4
    static let offsetTight: CGFloat = 3
}

extension View {
    func nestGlow(_ strength: Double = 1.0) -> some View {
        shadow(color: NestColor.anchorSolid.opacity(strength <= 0 ? 0 : 1),
               radius: 0,
               x: NestShadow.offset * CGFloat(min(1, strength)),
               y: NestShadow.offset * CGFloat(min(1, strength)))
    }

    func nestGlowTight(_ strength: Double = 1.0) -> some View {
        shadow(color: NestColor.anchorSolid.opacity(strength <= 0 ? 0 : 1),
               radius: 0,
               x: NestShadow.offsetTight * CGFloat(min(1, strength)),
               y: NestShadow.offsetTight * CGFloat(min(1, strength)))
    }

    /// The press: the shadow collapses and the control moves into where it was.
    func nestPressed(_ pressed: Bool, offset: CGFloat = NestShadow.offset) -> some View {
        self
            .offset(x: pressed ? offset : 0, y: pressed ? offset : 0)
            .shadow(color: NestColor.anchorSolid.opacity(pressed ? 0 : 1),
                    radius: 0,
                    x: pressed ? 0 : offset,
                    y: pressed ? 0 : offset)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

// MARK: - Motion

enum NestMotion {
    static let base   = Animation.spring(response: 0.34, dampingFraction: 0.78)
    static let snap   = Animation.easeOut(duration: 0.08)
    static let fill   = Animation.spring(response: 0.42, dampingFraction: 0.80)
    static let settle = Animation.easeOut(duration: 0.20)
    static let lamp   = Animation.easeInOut(duration: 0.4)

    /// The tab pill sliding under a new section.
    static let tabPill = Animation.interpolatingSpring(stiffness: 300, damping: 22)

    /// List cards arriving from below, 0.04s apart.
    static func stagger(_ index: Int, step: Double = 0.04, cap: Int = 10) -> Animation {
        base.delay(Double(min(index, cap)) * step)
    }
}

struct NestAnimated: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: AnyHashable

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .easeInOut(duration: 0.18) : animation, value: value)
    }
}

extension View {
    func nestAnimation<V: Hashable>(_ animation: Animation, value: V) -> some View {
        modifier(NestAnimated(animation: animation, value: AnyHashable(value)))
    }

    /// Cards rise 20pt into place, staggered by their position in the list.
    func nestRise(_ index: Int) -> some View {
        modifier(NestRise(index: index))
    }
}

private struct NestRise: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .offset(y: shown || reduceMotion ? 0 : 20)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(NestMotion.stagger(index)) { shown = true }
            }
    }
}

// MARK: - Haptics

enum NestHaptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func firm() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Theme + density preferences (Settings → Appearance)

enum NestTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Match Device"
        case .light:  return "Daylight"
        case .dark:   return "Lamplight"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

enum NestDensity: String, CaseIterable, Identifiable {
    case cosy, compact
    var id: String { rawValue }
    var title: String { self == .cosy ? "Cosy" : "Compact" }
    var scale: CGFloat { self == .cosy ? 1.0 : 0.76 }
}

private struct NestDensityKey: EnvironmentKey {
    static let defaultValue: NestDensity = .cosy
}

extension EnvironmentValues {
    var nestDensity: NestDensity {
        get { self[NestDensityKey.self] }
        set { self[NestDensityKey.self] = newValue }
    }
}

// MARK: - Storage keys used by @AppStorage across the app

enum NestDefaults {
    static let theme = "settings.theme"
    static let density = "settings.density"
    static let showPosters = "settings.showPosters"
    static let hasOnboarded = "app.hasOnboarded"
    static let notifEveningSoon = "notif.eveningSoon"
    static let notifReactions = "notif.reactions"
    static let notifUnfinished = "notif.unfinished"
    static let notifWeeklyReset = "notif.weeklyReset"
    static let notifAuthorised = "notif.authorised"
    static let tmdbEnabled = "external.enabled"
}
