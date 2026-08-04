//  Components.swift
//  Screen Nest — the component library.
//
//  Signature motif: THE EVENING ARCH — a dotted 3pt amber arc with a small plum
//  moon at its right end. It appears on the splash, above the evening window and
//  in every empty state.
//
//  Signature elevation: a hard offset shadow, 4pt down and right, zero blur,
//  full-strength anchor ink. Nothing here is blurred, soft or translucent.

import SwiftUI

// MARK: - The evening arch

struct EveningArch: View {
    var dotSize: CGFloat = 3
    var dotCount: Int = 22
    var showMoon: Bool = true
    var tint: Color = NestColor.amber

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                ForEach(0..<dotCount, id: \.self) { index in
                    let t = CGFloat(index) / CGFloat(max(1, dotCount - 1))
                    let x = t * w
                    let y = h - sin(.pi * t) * (h - dotSize)
                    Circle()
                        .fill(tint)
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: x - dotSize / 2, y: y - dotSize / 2)
                }
                if showMoon {
                    Circle()
                        .fill(NestColor.plum)
                        .frame(width: dotSize * 3.2, height: dotSize * 3.2)
                        .offset(x: w - dotSize * 1.6, y: h - dotSize * 1.6)
                }
            }
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }
}

// MARK: - Rules and scales
//
// Every rule in the app is a 2pt dashed line. There are no hairlines.

struct MinuteTicks: View {
    var count: Int = 24
    var height: CGFloat = 6
    var emphasisEvery: Int = 6
    var colour: Color = NestColor.amber
    var alignment: VerticalAlignment = .top

    var body: some View {
        GeometryReader { geo in
            let step = count > 1 ? geo.size.width / CGFloat(count - 1) : geo.size.width
            Path { path in
                for index in 0..<count {
                    let x = CGFloat(index) * step
                    let long = emphasisEvery > 0 && index % emphasisEvery == 0
                    let h = long ? height : height * 0.55
                    let y0 = alignment == .top ? 0 : geo.size.height - h
                    path.move(to: CGPoint(x: x, y: y0))
                    path.addLine(to: CGPoint(x: x, y: y0 + h))
                }
            }
            .stroke(colour, style: StrokeStyle(lineWidth: NestStroke.mark, lineCap: .round))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Dotted amber rule — the divider used across the app.
struct TickRule: View {
    var colour: Color = NestColor.amber
    var body: some View {
        DottedRule(colour: colour)
            .padding(.vertical, NestSpace.xs)
    }
}

struct DottedRule: View {
    var colour: Color = NestColor.amber
    var dot: CGFloat = 3
    var spacing: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(colour, style: StrokeStyle(lineWidth: dot, lineCap: .round, dash: [0.01, spacing]))
        }
        .frame(height: dot)
        .accessibilityHidden(true)
    }
}

/// Solid rule used beside section headings.
struct SolidRule: View {
    var colour: Color = NestColor.hairline
    var body: some View {
        Rectangle()
            .fill(colour)
            .frame(height: NestStroke.hair)
            .accessibilityHidden(true)
    }
}

// MARK: - The window bar

struct WindowBar: View {
    var fraction: Double
    var filmFraction: Double? = nil
    var height: CGFloat = 14
    var tint: Color = NestColor.amber
    var trackColour: Color = NestColor.anchor.opacity(0.10)
    var overflow: Bool = false
    var showTicks: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showTicks {
                DottedRule(colour: NestColor.amber.opacity(0.5))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(trackColour)

                    if let film = filmFraction {
                        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                            .fill(NestColor.amber.opacity(0.30))
                            .frame(width: geo.size.width * clamp(film))
                    }

                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(overflow
                              ? LinearGradient(colors: [NestColor.stop, NestColor.stop],
                                               startPoint: .top, endPoint: .bottom)
                              : NestColor.amberGradient)
                        .frame(width: geo.size.width * clamp(fraction))
                }
            }
            .frame(height: height)
            .nestAnimation(reduceMotion ? NestMotion.settle : NestMotion.fill, value: clamp(fraction))
        }
        .accessibilityHidden(true)
    }

    private func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

struct WindowGauge: View {
    let title: String
    let minutes: Int
    var caption: String?
    var fraction: Double
    var filmFraction: Double?
    var overflow: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: NestSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(title)
                Spacer(minLength: NestSpace.s)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    CountUpNumber(value: max(0, minutes))
                        .font(NestFont.figure)
                        .foregroundColor(overflow ? NestColor.stop : NestColor.ink)
                    Text("min")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                }
            }
            WindowBar(fraction: fraction, filmFraction: filmFraction, overflow: overflow)
            if let caption = caption {
                Text(caption)
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A figure that counts up from zero when it appears.
struct CountUpNumber: View, Animatable {
    var value: Int
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(Int(shown.rounded()))")
            .onAppear { run() }
            .onChange(of: value) { _ in run() }
    }

    private func run() {
        guard !reduceMotion else {
            shown = Double(value)
            return
        }
        shown = 0
        withAnimation(.easeOut(duration: 0.4)) { shown = Double(value) }
    }
}

// MARK: - Labels and section heads

/// Every section label is UPPERCASE and letter-spaced.
struct SectionLabel: View {
    let text: String
    var colour: Color = NestColor.inkSoft

    init(_ text: String, colour: Color = NestColor.inkSoft) {
        self.text = text
        self.colour = colour
    }

    var body: some View {
        nestTracked(text.uppercased(), kern: 1.2)
            .font(NestFont.label)
            .foregroundColor(colour)
    }
}

/// Section heading: uppercase label, then a rule running out to the edge.
struct SectionHead<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: NestSpace.xs) {
            HStack(spacing: NestSpace.m) {
                SectionLabel(title)
                SolidRule()
                trailing()
            }
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension SectionHead where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// The screen title: Heavy Italic, UPPERCASE.
struct PageTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NestSpace.s) {
            nestTracked(title.uppercased(), kern: -0.5)
                .font(NestFont.display)
                .foregroundColor(NestColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(NestFont.body)
                    .foregroundColor(NestColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Surfaces

struct NestCard<Content: View>: View {
    var padding: CGFloat = NestSpace.l
    var tint: Color = NestColor.surface
    var glow: Bool = true
    var stroke: Color = NestColor.hairline
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NestRadius.card, style: .continuous)
                    .fill(tint)
                    .modifier(ConditionalGlow(active: glow))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NestRadius.card, style: .continuous)
                    .stroke(stroke, lineWidth: NestStroke.hair)
            )
    }
}

private struct ConditionalGlow: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.nestGlow() } else { content }
    }
}

/// A card that carries the amber gradient across its whole face.
struct NestAmberCard<Content: View>: View {
    var padding: CGFloat = NestSpace.l
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NestRadius.card, style: .continuous)
                    .fill(NestColor.amberGradient)
                    .nestGlow()
            )
            .overlay(
                RoundedRectangle(cornerRadius: NestRadius.card, style: .continuous)
                    .stroke(NestColor.anchor.opacity(0.25), lineWidth: NestStroke.hair)
            )
    }
}

struct NestPanel<Content: View>: View {
    let label: String
    var glow: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        NestCard(glow: glow) {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                HStack(spacing: NestSpace.m) {
                    SectionLabel(label)
                    SolidRule()
                }
                content()
            }
        }
    }
}

// MARK: - The ticket card
//
// Film cards are tickets: semicircular notches cut into both sides at the
// midpoint of the height.

struct TicketShape: Shape {
    var corner: CGFloat = NestRadius.card
    var notch: CGFloat = NestRadius.notch

    func path(in rect: CGRect) -> Path {
        let r = min(corner, min(rect.width, rect.height) / 2)
        let n = min(notch, rect.height / 3)
        let midY = rect.midY
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                          control: CGPoint(x: rect.maxX, y: rect.minY))

        // Right notch, bulging inward.
        path.addLine(to: CGPoint(x: rect.maxX, y: midY - n))
        path.addArc(center: CGPoint(x: rect.maxX, y: midY), radius: n,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                          control: CGPoint(x: rect.minX, y: rect.maxY))

        // Left notch, bulging inward.
        path.addLine(to: CGPoint(x: rect.minX, y: midY + n))
        path.addArc(center: CGPoint(x: rect.minX, y: midY), radius: n,
                    startAngle: .degrees(90), endAngle: .degrees(270), clockwise: true)

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Every film card in the app.
struct TicketCard<Content: View>: View {
    var padding: CGFloat = NestSpace.l
    var tint: Color = NestColor.surface
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .padding(.horizontal, NestSpace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TicketShape().fill(tint).nestGlow())
            .overlay(TicketShape().stroke(NestColor.hairline, lineWidth: NestStroke.hair))
    }
}

// MARK: - Poster
//
// With no image, the cover is a diagonal two-colour gradient derived from the
// title's own name, with its initial set very large at low opacity.

struct PosterShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: NestRadius.posterTop, style: .continuous)
    }
}

enum PosterArt {
    /// Two hues derived from a stable hash of the name.
    static func hues(for title: Title) -> (Color, Color) {
        var hash: UInt64 = 5381
        for byte in title.name.unicodeScalars {
            hash = (hash &* 33) &+ UInt64(byte.value)
        }
        let a = Double(hash % 360) / 360.0
        let b = Double((hash / 7) % 360) / 360.0
        return (
            Color(hue: a, saturation: 0.62, brightness: 0.78),
            Color(hue: b, saturation: 0.70, brightness: 0.52)
        )
    }

    static func initial(for title: Title) -> String {
        let trimmed = title.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1)).uppercased()
    }
}

struct PosterArtwork: View {
    let title: Title

    var body: some View {
        GeometryReader { geo in
            let hues = PosterArt.hues(for: title)
            ZStack {
                LinearGradient(colors: [hues.0, hues.1],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(PosterArt.initial(for: title))
                    .font(.system(size: min(96, geo.size.height * 0.66), weight: .heavy))
                    .foregroundColor(Color.white.opacity(0.25))
            }
        }
    }
}

struct PosterView: View {
    let title: Title
    var width: CGFloat = 92
    var showPoster: Bool = true
    var aspectRatio: CGFloat = 100.0 / 72.0

    var body: some View {
        Group {
            if showPoster, let image = PosterStore.shared.image(named: title.posterFileName) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                PosterArtwork(title: title)
            }
        }
        .frame(width: width, height: width * aspectRatio)
        .clipShape(PosterShape())
        .overlay(PosterShape().stroke(NestColor.anchor.opacity(0.25), lineWidth: NestStroke.hair))
    }
}

// MARK: - Viewer tokens

struct ViewerToken: View {
    let viewer: Viewer
    var size: CGFloat = 34
    var selected: Bool = true
    var showName: Bool = false

    private var hue: Color { NestColor.viewerHue(viewer.colourIndex) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(selected ? hue : NestColor.surfaceSunk)
                Circle()
                    .stroke(NestColor.anchor.opacity(selected ? 0.35 : 0.20),
                            lineWidth: NestStroke.hair)
                Text(viewer.initials)
                    .font(NestFont.tokenLetter(size * 0.42))
                    .foregroundColor(selected ? NestColor.inkOnAmber : NestColor.inkFaint)
            }
            .frame(width: size, height: size)

            if showName {
                Text(viewer.name)
                    .font(NestFont.micro)
                    .foregroundColor(selected ? NestColor.ink : NestColor.inkFaint)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewer.name)
    }
}

struct ViewerTokenRow: View {
    let viewers: [Viewer]
    var size: CGFloat = 28
    var limit: Int = 6

    var body: some View {
        HStack(spacing: -size * 0.24) {
            ForEach(Array(viewers.prefix(limit).enumerated()), id: \.element.id) { _, viewer in
                ViewerToken(viewer: viewer, size: size)
                    .background(Circle().fill(NestColor.surface))
            }
            if viewers.count > limit {
                Text("+\(viewers.count - limit)")
                    .font(NestFont.figureMicro)
                    .foregroundColor(NestColor.inkSoft)
                    .padding(.leading, size * 0.35)
            }
        }
    }
}

// MARK: - Status pill
//
// Active state is always carried by a fill, never by text colour alone.

struct StatusPill: View {
    let status: SuitabilityStatus
    var compact: Bool = false

    private var fill: Color {
        switch status {
        case .fitsEveryone:  return NestColor.go
        case .fitsOlderOnly: return NestColor.amber
        case .needsAParent:  return NestColor.plum
        case .notTonight:    return NestColor.stop
        case .notYet:        return NestColor.stop
        }
    }

    private var textColour: Color {
        status == .fitsOlderOnly ? NestColor.inkOnAmber : Color.white
    }

    var body: some View {
        nestTracked(status.title.uppercased(), kern: 0.8)
            .font(.system(size: compact ? 11 : 12, weight: .heavy))
            .foregroundColor(textColour)
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 5 : 7)
            .background(Capsule(style: .continuous).fill(fill))
    }
}

// MARK: - Reason row

struct ReasonRow: View {
    let reason: SuitabilityReason

    private var tint: Color {
        switch reason.tone {
        case .positive: return NestColor.go
        case .neutral:  return NestColor.plum
        case .caution:  return NestColor.amber
        case .blocking: return NestColor.stop
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: NestSpace.m) {
            ZStack {
                RoundedRectangle(cornerRadius: NestRadius.icon, style: .continuous)
                    .fill(tint)
                    .frame(width: 36, height: 36)
                if let aspect = reason.aspect {
                    AspectGlyph(aspect: aspect, size: 20, tint: .white, lineWidth: 2)
                } else {
                    ReasonSymbolGlyph(symbol: reason.symbol, tint: .white, size: 20)
                }
            }
            Text(reason.sentence)
                .font(NestFont.body)
                .foregroundColor(reason.tone == .neutral ? NestColor.inkSoft : NestColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ReasonSymbolGlyph: View {
    let symbol: ReasonSymbol
    var tint: Color = NestColor.ink
    var size: CGFloat = 20

    var body: some View {
        Group {
            switch symbol {
            case .certification: shape { p, s in
                p.addRoundedRect(in: CGRect(x: 0.12 * s, y: 0.18 * s, width: 0.76 * s, height: 0.64 * s),
                                 cornerSize: CGSize(width: 0.14 * s, height: 0.14 * s))
                p.move(to: CGPoint(x: 0.30 * s, y: 0.50 * s)); p.addLine(to: CGPoint(x: 0.70 * s, y: 0.50 * s))
            }
            case .clock: shape { p, s in
                p.addEllipse(in: CGRect(x: 0.12 * s, y: 0.12 * s, width: 0.76 * s, height: 0.76 * s))
                p.move(to: CGPoint(x: 0.50 * s, y: 0.50 * s)); p.addLine(to: CGPoint(x: 0.50 * s, y: 0.26 * s))
                p.move(to: CGPoint(x: 0.50 * s, y: 0.50 * s)); p.addLine(to: CGPoint(x: 0.70 * s, y: 0.58 * s))
            }
            case .rule: shape { p, s in
                p.move(to: CGPoint(x: 0.16 * s, y: 0.24 * s)); p.addLine(to: CGPoint(x: 0.84 * s, y: 0.24 * s))
                p.move(to: CGPoint(x: 0.16 * s, y: 0.50 * s)); p.addLine(to: CGPoint(x: 0.62 * s, y: 0.50 * s))
                p.move(to: CGPoint(x: 0.16 * s, y: 0.76 * s)); p.addLine(to: CGPoint(x: 0.84 * s, y: 0.76 * s))
            }
            case .history: shape { p, s in
                p.addArc(center: CGPoint(x: 0.50 * s, y: 0.52 * s), radius: 0.34 * s,
                         startAngle: .degrees(150), endAngle: .degrees(60), clockwise: false)
                p.move(to: CGPoint(x: 0.50 * s, y: 0.52 * s)); p.addLine(to: CGPoint(x: 0.50 * s, y: 0.30 * s))
            }
            case .note: shape { p, s in
                p.addRoundedRect(in: CGRect(x: 0.18 * s, y: 0.12 * s, width: 0.64 * s, height: 0.76 * s),
                                 cornerSize: CGSize(width: 0.10 * s, height: 0.10 * s))
                p.move(to: CGPoint(x: 0.32 * s, y: 0.36 * s)); p.addLine(to: CGPoint(x: 0.68 * s, y: 0.36 * s))
                p.move(to: CGPoint(x: 0.32 * s, y: 0.54 * s)); p.addLine(to: CGPoint(x: 0.60 * s, y: 0.54 * s))
            }
            case .attention, .split: shape { p, s in
                p.move(to: CGPoint(x: 0.16 * s, y: 0.32 * s)); p.addLine(to: CGPoint(x: 0.52 * s, y: 0.32 * s))
                p.move(to: CGPoint(x: 0.16 * s, y: 0.68 * s)); p.addLine(to: CGPoint(x: 0.52 * s, y: 0.68 * s))
                p.move(to: CGPoint(x: 0.66 * s, y: 0.20 * s)); p.addLine(to: CGPoint(x: 0.66 * s, y: 0.80 * s))
            }
            case .screenTime: shape { p, s in
                p.addRoundedRect(in: CGRect(x: 0.12 * s, y: 0.24 * s, width: 0.76 * s, height: 0.44 * s),
                                 cornerSize: CGSize(width: 0.08 * s, height: 0.08 * s))
                p.move(to: CGPoint(x: 0.34 * s, y: 0.84 * s)); p.addLine(to: CGPoint(x: 0.66 * s, y: 0.84 * s))
            }
            case .content: shape { p, s in
                p.addEllipse(in: CGRect(x: 0.18 * s, y: 0.18 * s, width: 0.64 * s, height: 0.64 * s))
                p.move(to: CGPoint(x: 0.34 * s, y: 0.54 * s)); p.addLine(to: CGPoint(x: 0.46 * s, y: 0.66 * s))
                p.addLine(to: CGPoint(x: 0.68 * s, y: 0.38 * s))
            }
            case .unknown: shape { p, s in
                p.addEllipse(in: CGRect(x: 0.16 * s, y: 0.16 * s, width: 0.68 * s, height: 0.68 * s))
                p.move(to: CGPoint(x: 0.50 * s, y: 0.30 * s)); p.addLine(to: CGPoint(x: 0.50 * s, y: 0.56 * s))
                p.move(to: CGPoint(x: 0.50 * s, y: 0.66 * s)); p.addLine(to: CGPoint(x: 0.50 * s, y: 0.70 * s))
            }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func shape(_ build: @escaping (inout Path, CGFloat) -> Void) -> some View {
        GlyphPath(build: build)
            .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

struct GlyphPath: Shape {
    let build: (inout Path, CGFloat) -> Void
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = min(rect.width, rect.height)
        build(&path, s)
        return path
    }
}

/// An icon in an amber square — the Settings row treatment.
struct IconTile: View {
    let symbol: ReasonSymbol
    var tint: Color = NestColor.inkOnAmber
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NestRadius.icon, style: .continuous)
                .fill(NestColor.amberGradient)
                .frame(width: size, height: size)
            ReasonSymbolGlyph(symbol: symbol, tint: tint, size: size * 0.55)
        }
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NestFont.heading)
            .foregroundColor(enabled ? (destructive ? .white : NestColor.inkOnAmber) : NestColor.inkFaint)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Group {
                    if !enabled {
                        RoundedRectangle(cornerRadius: NestRadius.button, style: .continuous)
                            .fill(NestColor.surfaceSunk)
                    } else if destructive {
                        RoundedRectangle(cornerRadius: NestRadius.button, style: .continuous)
                            .fill(NestColor.stop)
                    } else {
                        RoundedRectangle(cornerRadius: NestRadius.button, style: .continuous)
                            .fill(NestColor.amberGradient)
                    }
                }
                .shadow(color: NestColor.anchorSolid.opacity(configuration.isPressed || !enabled ? 0 : 1),
                        radius: 0,
                        x: configuration.isPressed || !enabled ? 0 : NestShadow.offset,
                        y: configuration.isPressed || !enabled ? 0 : NestShadow.offset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NestRadius.button, style: .continuous)
                    .stroke(NestColor.anchor.opacity(0.25), lineWidth: NestStroke.hair)
            )
            .offset(x: configuration.isPressed && enabled ? NestShadow.offset : 0,
                    y: configuration.isPressed && enabled ? NestShadow.offset : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = NestColor.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NestFont.heading)
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: NestRadius.button, style: .continuous)
                    .fill(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NestRadius.button, style: .continuous)
                    .stroke(tint, lineWidth: NestStroke.mark)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var tint: Color = NestColor.amberSunk
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NestFont.smallMedium)
            .foregroundColor(tint)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct PrimaryButton: View {
    let title: String
    var busyTitle: String = "Saving…"
    var enabled: Bool = true
    var busy: Bool = false
    var destructive: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            guard enabled, !busy else { return }
            NestHaptics.tap()
            action()
        } label: {
            HStack(spacing: NestSpace.s) {
                if busy { BusyTicks() }
                Text(busy ? busyTitle : title)
            }
        }
        .buttonStyle(PrimaryButtonStyle(enabled: enabled && !busy, destructive: destructive))
        .disabled(!enabled || busy)
    }
}

struct BusyTicks: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.18)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.18) % 3
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(NestColor.inkOnAmber.opacity(index == step ? 1 : 0.35))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 14)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Chips

struct NestChip: View {
    let title: String
    var selected: Bool = false
    var tint: Color = NestColor.amber
    var glyph: ContentAspect? = nil
    var action: (() -> Void)? = nil

    /// Amber is light enough to take the anchor ink; every other fill takes white.
    private var foreground: Color {
        guard selected else { return NestColor.ink }
        return tint == NestColor.amber ? NestColor.inkOnAmber : .white
    }

    var body: some View {
        let content = HStack(spacing: 7) {
            if let glyph = glyph {
                AspectGlyph(aspect: glyph, size: 17, tint: foreground, lineWidth: 2)
            }
            Text(title)
                .font(NestFont.smallMedium)
                .foregroundColor(foreground)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(
            Group {
                if selected {
                    Capsule(style: .continuous).fill(
                        tint == NestColor.amber
                        ? AnyShapeStyle(NestColor.amberGradient)
                        : AnyShapeStyle(tint)
                    )
                } else {
                    Capsule(style: .continuous).fill(NestColor.surface)
                }
            }
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(selected ? Color.clear : NestColor.border, lineWidth: NestStroke.hair)
        )

        if let action = action {
            Button {
                NestHaptics.tap()
                action()
            } label: { content }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// Wrapping chip cloud — no horizontal scrolling, everything visible at once.
struct ChipFlow<Item: Hashable, Label: View>: View {
    let items: [Item]
    var spacing: CGFloat = NestSpace.s
    @ViewBuilder var label: (Item) -> Label

    @State private var height: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            self.layout(width: geo.size.width)
        }
        .frame(height: height)
    }

    private func layout(width: CGFloat) -> some View {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                label(item)
                    .alignmentGuide(.leading) { dimension in
                        if x + dimension.width > width {
                            x = 0
                            y -= rowHeight + spacing
                            rowHeight = 0
                        }
                        let result = x
                        x += dimension.width + spacing
                        rowHeight = max(rowHeight, dimension.height)
                        if item == items.last { x = 0 }
                        return -result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = y
                        if item == items.last { y = 0 }
                        return -result
                    }
            }
        }
        .background(
            GeometryReader { proxy -> Color in
                let measured = proxy.size.height
                DispatchQueue.main.async {
                    if abs(self.height - measured) > 0.5 { self.height = measured }
                }
                return Color.clear
            }
        )
    }
}

// MARK: - States

struct EmptyStateView: View {
    let title: String
    let message: String
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: NestSpace.l) {
            EveningArch()
                .frame(width: 160)
                .padding(.bottom, NestSpace.s)
            nestTracked(title.uppercased(), kern: -0.3)
                .font(.system(size: 22, weight: .heavy).italic())
                .foregroundColor(NestColor.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(NestFont.body)
                .foregroundColor(NestColor.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if primaryTitle != nil || secondaryTitle != nil {
                VStack(spacing: NestSpace.m) {
                    if let primaryTitle = primaryTitle, let primaryAction = primaryAction {
                        PrimaryButton(title: primaryTitle, action: primaryAction)
                    }
                    if let secondaryTitle = secondaryTitle, let secondaryAction = secondaryAction {
                        Button(secondaryTitle) {
                            NestHaptics.tap()
                            secondaryAction()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.top, NestSpace.xs)
            }
        }
        .padding(.horizontal, NestSpace.l)
        .padding(.vertical, NestSpace.xl)
        .frame(maxWidth: .infinity)
    }
}

struct LoadingStateView: View {
    var message: String = "Reading your evenings…"

    var body: some View {
        VStack(spacing: NestSpace.l) {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                WindowBar(fraction: t, height: 10, showTicks: false)
                    .frame(width: 170)
            }
            Text(message)
                .font(NestFont.small)
                .foregroundColor(NestColor.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NestSpace.xxl)
    }
}

struct ErrorStateView: View {
    let title: String
    let message: String
    var retryTitle: String = "Try Again"
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: NestSpace.m) {
            ZStack {
                RoundedRectangle(cornerRadius: NestRadius.icon, style: .continuous)
                    .fill(NestColor.stop)
                    .frame(width: 44, height: 44)
                ReasonSymbolGlyph(symbol: .unknown, tint: .white, size: 24)
            }
            nestTracked(title.uppercased(), kern: -0.3)
                .font(.system(size: 20, weight: .heavy).italic())
                .foregroundColor(NestColor.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(NestFont.body)
                .foregroundColor(NestColor.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry = retry {
                Button(retryTitle) {
                    NestHaptics.tap()
                    retry()
                }
                .buttonStyle(SecondaryButtonStyle(tint: NestColor.stop))
                .padding(.top, NestSpace.xs)
            }
        }
        .padding(NestSpace.l)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: NestRadius.card, style: .continuous)
                .fill(NestColor.stopWash)
                .nestGlow()
        )
        .overlay(
            RoundedRectangle(cornerRadius: NestRadius.card, style: .continuous)
                .stroke(NestColor.stop, lineWidth: NestStroke.hair)
        )
    }
}

// MARK: - Toast

struct NestToast: Equatable {
    let message: String
    var isError: Bool = false
}

struct ToastOverlay: View {
    let toast: NestToast?

    var body: some View {
        VStack {
            Spacer()
            if let toast = toast {
                HStack(spacing: NestSpace.s) {
                    ReasonSymbolGlyph(symbol: toast.isError ? .unknown : .content,
                                      tint: NestColor.onAnchor, size: 18)
                    Text(toast.message)
                        .font(NestFont.smallMedium)
                        .foregroundColor(NestColor.onAnchor)
                }
                .padding(.horizontal, NestSpace.l)
                .padding(.vertical, NestSpace.m)
                .background(Capsule(style: .continuous).fill(NestColor.anchor).nestGlowTight())
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, NestSpace.tabInset)
            }
        }
        .animation(NestMotion.base, value: toast)
        .allowsHitTesting(false)
    }
}

// MARK: - Screen scaffold

struct NestScreen<Content: View>: View {
    var bottomInset: CGFloat = NestSpace.tabInset
    @ViewBuilder var content: () -> Content

    @Environment(\.nestDensity) private var density

    var body: some View {
        ZStack {
            NestColor.ground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: NestSpace.xl * density.scale) {
                    content()
                }
                .padding(.horizontal, NestSpace.gutter)
                .padding(.top, NestSpace.l)
                .padding(.bottom, bottomInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct SheetScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    var closeTitle: String = "Close"
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            NestColor.ground.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        nestTracked(title.uppercased(), kern: -0.4)
                            .font(NestFont.displaySmall)
                            .foregroundColor(NestColor.ink)
                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(NestFont.small)
                                .foregroundColor(NestColor.inkSoft)
                        }
                    }
                    Spacer(minLength: NestSpace.s)
                    Button(closeTitle) {
                        NestHaptics.tap()
                        onClose()
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                .padding(.horizontal, NestSpace.gutter)
                .padding(.top, NestSpace.xl)
                .padding(.bottom, NestSpace.m)

                DottedRule()
                    .padding(.horizontal, NestSpace.gutter)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: NestSpace.l) {
                        content()
                    }
                    .padding(.horizontal, NestSpace.gutter)
                    .padding(.top, NestSpace.l)
                    .padding(.bottom, NestSpace.huge)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
