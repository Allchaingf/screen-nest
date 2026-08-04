//  OnboardingModule.swift
//  Screen Nest
//
//  Four pages, and the progress IS the evening window filling a quarter at a
//  time. No page dots, no paged carousel, no drag: the bar at the top is the
//  only indicator, and each page draws a live diagram of the thing it explains.
//
//  VIPER: OnboardingPresenter holds the step, the Router hands control back to
//  the root once the last page is torn off.

import SwiftUI

// MARK: - Entity

struct OnboardingPage: Identifiable {
    let id: Int
    let title: String
    let body: String
    let footnote: String
}

// MARK: - Interactor

protocol OnboardingInteracting {
    var pages: [OnboardingPage] { get }
    func markSeen()
}

struct OnboardingInteractor: OnboardingInteracting {
    let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            title: "Not Every Rating Fits Your Child",
            body: "A certificate is an average of every child in the country. Yours is one child, with one set of things that land badly and one set that lands well.",
            footnote: "A rating says “10+”. It does not know that this child cannot watch an animal get hurt."
        ),
        OnboardingPage(
            id: 1,
            title: "Set the Rules of Your House",
            body: "What is allowed here, and what is not. Rules sit above any rating — and you can break one on purpose, with the reason written down.",
            footnote: "The app never forbids anything. It explains, and you decide."
        ),
        OnboardingPage(
            id: 2,
            title: "Add Your Viewers",
            body: "Everyone who watches, with their age, what they love, and what they cannot sit through yet. Sensitivities carry a date, because children change.",
            footnote: "What frightened a five-year-old is often a favourite at seven."
        ),
        OnboardingPage(
            id: 3,
            title: "Plan Your First Evening",
            body: "Bedtime minus now, minus settling, minus the pauses you know are coming. If the film does not fit in what is left, choosing it was never the problem.",
            footnote: "Window = bedtime − now − settling time − expected pauses"
        )
    ]

    func markSeen() {
        UserDefaults.standard.set(true, forKey: NestDefaults.hasOnboarded)
    }
}

// MARK: - Presenter

final class OnboardingPresenter: ObservableObject {
    @Published private(set) var index: Int = 0

    private let interactor: OnboardingInteracting
    private let onComplete: () -> Void

    init(interactor: OnboardingInteracting = OnboardingInteractor(), onComplete: @escaping () -> Void) {
        self.interactor = interactor
        self.onComplete = onComplete
    }

    var pages: [OnboardingPage] { interactor.pages }
    var page: OnboardingPage { pages[min(index, pages.count - 1)] }
    var isLast: Bool { index >= pages.count - 1 }
    /// The window fills a quarter per page — this is the only progress indicator.
    var fill: Double { Double(index + 1) / Double(pages.count) }

    var primaryTitle: String { isLast ? "Set Up Your House" : "Continue" }

    func advance() {
        if isLast {
            finish()
        } else {
            withAnimation(NestMotion.base) { index += 1 }
        }
    }

    func back() {
        guard index > 0 else { return }
        withAnimation(NestMotion.base) { index -= 1 }
    }

    func skip() { finish() }

    private func finish() {
        interactor.markSeen()
        onComplete()
    }
}

// MARK: - View

struct OnboardingView: View {
    @StateObject private var presenter: OnboardingPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onComplete: @escaping () -> Void) {
        _presenter = StateObject(wrappedValue: OnboardingPresenter(onComplete: onComplete))
    }

    var body: some View {
        ZStack {
            NestColor.ground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // Progress: the evening window, a quarter at a time.
                VStack(alignment: .leading, spacing: NestSpace.s) {
                    HStack {
                        SectionLabel("the evening so far")
                        Spacer()
                        Text("\(presenter.index + 1) of \(presenter.pages.count)")
                            .font(NestFont.figureMicro)
                            .foregroundColor(NestColor.inkFaint)
                    }
                    WindowBar(fraction: presenter.fill, height: 12)
                }
                .padding(.horizontal, NestSpace.gutter)
                .padding(.top, NestSpace.l)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: NestSpace.xl) {

                        OnboardingDiagram(index: presenter.index)
                            .frame(height: 208)
                            .frame(maxWidth: .infinity)
                            .padding(.top, NestSpace.l)

                        VStack(alignment: .leading, spacing: NestSpace.m) {
                            nestTracked(presenter.page.title.uppercased(), kern: -0.5)
                                .font(NestFont.display)
                                .foregroundColor(NestColor.ink)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(presenter.page.body)
                                .font(NestFont.body)
                                .foregroundColor(NestColor.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(alignment: .top, spacing: NestSpace.s) {
                                Rectangle()
                                    .fill(NestColor.amber)
                                    .frame(width: 4)
                                Text(presenter.page.footnote)
                                    .font(NestFont.quote)
                                    .foregroundColor(NestColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, NestSpace.xs)
                        }
                        .id(presenter.index)
                        .transition(pageTransition)
                    }
                    .padding(.horizontal, NestSpace.gutter)
                    .padding(.bottom, NestSpace.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: NestSpace.m) {
                    DottedRule()

                    PrimaryButton(title: presenter.primaryTitle) {
                        presenter.advance()
                    }

                    HStack {
                        if presenter.index > 0 {
                            Button("Back") { presenter.back() }
                                .buttonStyle(QuietButtonStyle())
                        }
                        Spacer()
                        Button("Skip to setup") { presenter.skip() }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
                .padding(.horizontal, NestSpace.gutter)
                .padding(.bottom, NestSpace.l)
            }
        }
    }

    private var pageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            )
    }
}

// MARK: - Live diagrams
//
// Each page draws the idea it is explaining, from the same components the app
// itself uses. Nothing here is decoration.

struct OnboardingDiagram: View {
    let index: Int

    var body: some View {
        Group {
            switch index {
            case 0: ratingDiagram
            case 1: rulesDiagram
            case 2: viewersDiagram
            default: windowDiagram
            }
        }
        .animation(NestMotion.base, value: index)
    }

    // 1 — the certificate is an average; your child is a point on the line.
    private var ratingDiagram: some View {
        NestCard(glow: true) {
            VStack(alignment: .leading, spacing: NestSpace.l) {
                SectionLabel("certificate 7+ · everyone aged 7")
                ZStack(alignment: .leading) {
                    Capsule().fill(NestColor.surfaceSunk).frame(height: 10)
                    Capsule().fill(NestColor.amber.opacity(0.5)).frame(width: 150, height: 10)
                    HStack(spacing: 0) {
                        Spacer().frame(width: 44)
                        Circle()
                            .fill(NestColor.viewerHue(1))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(NestColor.surface, lineWidth: 2))
                    }
                }
                .frame(height: 20)

                HStack(spacing: NestSpace.s) {
                    ForEach([ContentAspect.animalInDanger, .darkness, .loudNoises], id: \.self) { aspect in
                        NestChip(title: aspect.title,
                                 selected: aspect == .animalInDanger,
                                 tint: NestColor.stop,
                                 glyph: aspect)
                    }
                }

                Text("This child, marked sensitive to one of them.")
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkSoft)
            }
        }
    }

    // 2 — rules stack above the rating.
    private var rulesDiagram: some View {
        NestCard(glow: true) {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                ForEach(Array(["No horror", "90 minutes on weeknights", "Nothing after 20:30"].enumerated()),
                        id: \.offset) { position, rule in
                    HStack(spacing: NestSpace.m) {
                        ReasonSymbolGlyph(symbol: .rule, tint: NestColor.amberSunk, size: 18)
                        Text(rule)
                            .font(NestFont.bodyMedium)
                            .foregroundColor(NestColor.ink)
                        Spacer()
                        if position == 2 {
                            nestTracked("exception allowed", kern: 0.8)
                                .font(NestFont.label)
                                .foregroundColor(NestColor.plum)
                        }
                    }
                    .padding(.vertical, NestSpace.s)
                    .padding(.horizontal, NestSpace.m)
                    .background(
                        RoundedRectangle(cornerRadius: NestRadius.chip, style: .continuous)
                            .fill(NestColor.surfaceSunk)
                    )
                    .offset(x: CGFloat(position) * 8)
                }
            }
        }
    }

    // 3 — viewers as coloured tokens, each with their own marks.
    private var viewersDiagram: some View {
        NestCard(glow: true) {
            HStack(spacing: NestSpace.l) {
                ForEach(Array(["Marco", "Sofia", "You"].enumerated()), id: \.offset) { position, name in
                    VStack(spacing: NestSpace.s) {
                        ZStack {
                            Circle()
                                .fill(NestColor.viewerHue(position).opacity(0.20))
                            Circle()
                                .stroke(NestColor.viewerHue(position), lineWidth: 2)
                            Text(String(name.prefix(1)))
                                .font(NestFont.tokenLetter(20))
                                .foregroundColor(NestColor.viewerHue(position))
                        }
                        .frame(width: 54, height: 54)

                        Text(name)
                            .font(NestFont.smallMedium)
                            .foregroundColor(NestColor.ink)

                        HStack(spacing: 5) {
                            ForEach(marks(for: position), id: \.self) { aspect in
                                AspectGlyph(aspect: aspect, size: 18, tint: NestColor.inkSoft, lineWidth: 2)
                            }
                        }
                        .frame(height: 16)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func marks(for position: Int) -> [ContentAspect] {
        switch position {
        case 0: return [.animalInDanger, .loudNoises]
        case 1: return [.sadEndings]
        default: return []
        }
    }

    // 4 — the window, with the film sitting inside what is actually left.
    private var windowDiagram: some View {
        NestCard(glow: true) {
            VStack(alignment: .leading, spacing: NestSpace.l) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel("bedtime 20:30 · now 18:40")
                    Spacer()
                    Text("80")
                        .font(NestFont.figure)
                        .foregroundColor(NestColor.ink)
                    Text("min")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkFaint)
                }

                VStack(spacing: 4) {
                    MinuteTicks(count: 23, height: 5, emphasisEvery: 6, colour: NestColor.hairline)
                    GeometryReader { geo in
                        let segments: [(CGFloat, Color, String)] = [
                            (0.66, NestColor.amber, "film"),
                            (0.10, NestColor.plum.opacity(0.65), "pause"),
                            (0.24, NestColor.viewerHue(5).opacity(0.65), "settling")
                        ]
                        HStack(spacing: 2) {
                            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(segment.1)
                                    nestTracked(segment.2, kern: 0.6)
                                        .font(NestFont.label)
                                        .foregroundColor(NestColor.inkOnAmber)
                                }
                                .frame(width: max(24, geo.size.width * segment.0 - 2))
                            }
                        }
                    }
                    .frame(height: 26)
                }

                Text("A film of 92 minutes would not fit. One of 78 would, with time to settle.")
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

}
