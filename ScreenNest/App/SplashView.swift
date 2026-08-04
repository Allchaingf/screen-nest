//  SplashView.swift
//  Screen Nest
//
//  A seamless 2.0-second loop: the evening bar makes exactly one pass, the moon
//  crosses exactly one arc, and each viewer dot lights as the bar reaches it.
//  Because every element completes a whole cycle, the frame the splash exits on
//  is always a deliberate one — there is no staged sequence to interrupt.
//
//  Exit is the app's signature transition: the fill.

import SwiftUI

struct SplashView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didFinish = false

    private let period: Double = 2.0

    var body: some View {
        ZStack {
            NestColor.ground.ignoresSafeArea()

            if reduceMotion {
                scene(phase: 0.62)
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let phase = (t.truncatingRemainder(dividingBy: period)) / period
                    scene(phase: phase)
                }
            }
        }
        .onAppear(perform: scheduleFinish)
    }

    private func scheduleFinish() {
        guard !didFinish else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard !didFinish else { return }
            didFinish = true
            onFinish()
        }
    }

    // MARK: - Scene

    @ViewBuilder
    private func scene(phase: Double) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // The evening arch, at full strength.
            EveningArch(dotSize: 3, dotCount: 24)
                .frame(width: 230, height: 60)
                .padding(.bottom, NestSpace.xl)

            nestTracked("SCREEN NEST", kern: -0.5)
                .font(.system(size: 40, weight: .heavy).italic())
                .foregroundColor(NestColor.ink)

            nestTracked("EVENINGS THAT FIT YOUR HOUSE", kern: 1.2)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(NestColor.inkSoft)
                .padding(.top, NestSpace.s)

            Spacer(minLength: 0)

            // The loading bar makes exactly one pass per loop.
            VStack(spacing: NestSpace.l) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NestColor.anchor.opacity(0.10))
                        .frame(width: 210, height: 10)
                    Capsule()
                        .fill(NestColor.amberGradient)
                        .frame(width: 210 * CGFloat(phase), height: 10)
                }

                HStack(spacing: NestSpace.xl) {
                    ForEach(Array([0.25, 0.5, 0.75].enumerated()), id: \.offset) { index, centre in
                        Circle()
                            .fill(NestColor.viewerHue(index))
                            .frame(width: 10, height: 10)
                            .opacity(0.30 + 0.70 * pulse(phase: phase, centre: centre))
                    }
                }
            }
            .padding(.bottom, 84)
        }
    }

    /// A wrapped bump so each dot returns to exactly where it started.
    private func pulse(phase: Double, centre: Double) -> Double {
        let raw = abs(phase - centre)
        let distance = min(raw, 1 - raw)
        return max(0, 1 - distance / 0.16)
    }
}

// MARK: - The signature transition: the fill

struct FillReveal: ViewModifier {
    var progress: CGFloat

    func body(content: Content) -> some View {
        content.mask(
            GeometryReader { geo in
                Rectangle()
                    .frame(width: max(0, geo.size.width * progress), height: geo.size.height)
            }
        )
    }
}

extension AnyTransition {
    /// Content arrives the way the evening window fills: left to right.
    static var nestFill: AnyTransition {
        .modifier(active: FillReveal(progress: 0), identity: FillReveal(progress: 1))
    }
}
