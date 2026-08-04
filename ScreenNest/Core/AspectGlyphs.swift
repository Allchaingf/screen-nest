//  AspectGlyphs.swift
//  Screen Nest
//
//  Content is described by a row of quiet drawn marks — never stock horror art,
//  never a bleeding icon. Every glyph is a stroked path so it reads the same on
//  cream paper and in lamplight.

import SwiftUI

struct AspectGlyphShape: Shape {
    let aspect: ContentAspect

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let o = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: o.x + x * s, y: o.y + y * s)
        }
        var path = Path()

        switch aspect {

        case .loudNoises:
            // Three widening arcs leaving a small source.
            path.addEllipse(in: CGRect(x: o.x + 0.14 * s, y: o.y + 0.42 * s, width: 0.16 * s, height: 0.16 * s))
            for (i, r) in [0.20, 0.33, 0.46].enumerated() {
                _ = i
                path.move(to: p(0.40, 0.50 - CGFloat(r) * 0.72))
                path.addQuadCurve(
                    to: p(0.40, 0.50 + CGFloat(r) * 0.72),
                    control: p(0.40 + CGFloat(r) * 1.05, 0.50)
                )
            }

        case .jumpScares:
            // A single sharp step — the moment the picture snaps.
            path.move(to: p(0.18, 0.72))
            path.addLine(to: p(0.42, 0.72))
            path.addLine(to: p(0.42, 0.28))
            path.addLine(to: p(0.66, 0.28))
            path.addLine(to: p(0.66, 0.58))
            path.addLine(to: p(0.84, 0.58))

        case .darkness:
            // A crescent: the room with the light off.
            path.addArc(center: p(0.50, 0.50), radius: 0.32 * s,
                        startAngle: .degrees(58), endAngle: .degrees(302), clockwise: false)
            path.addArc(center: p(0.66, 0.50), radius: 0.30 * s,
                        startAngle: .degrees(300), endAngle: .degrees(60), clockwise: true)

        case .animalInDanger:
            // A paw print, set gently.
            path.addEllipse(in: CGRect(x: o.x + 0.32 * s, y: o.y + 0.46 * s, width: 0.36 * s, height: 0.30 * s))
            for x in [0.24, 0.43, 0.62] {
                path.addEllipse(in: CGRect(x: o.x + CGFloat(x) * s, y: o.y + 0.22 * s,
                                           width: 0.15 * s, height: 0.18 * s))
            }
            path.addEllipse(in: CGRect(x: o.x + 0.74 * s, y: o.y + 0.38 * s,
                                       width: 0.14 * s, height: 0.16 * s))

        case .parentSeparation:
            // Two figures with a measured gap between them.
            path.addEllipse(in: CGRect(x: o.x + 0.10 * s, y: o.y + 0.20 * s, width: 0.20 * s, height: 0.20 * s))
            path.move(to: p(0.20, 0.44)); path.addLine(to: p(0.20, 0.78))
            path.addEllipse(in: CGRect(x: o.x + 0.68 * s, y: o.y + 0.30 * s, width: 0.16 * s, height: 0.16 * s))
            path.move(to: p(0.76, 0.48)); path.addLine(to: p(0.76, 0.78))
            path.move(to: p(0.36, 0.60)); path.addLine(to: p(0.44, 0.60))
            path.move(to: p(0.50, 0.60)); path.addLine(to: p(0.58, 0.60))

        case .characterDeath:
            // A hill and a single upright marker. No skulls, no crosses of the ghoulish sort.
            path.move(to: p(0.12, 0.76))
            path.addQuadCurve(to: p(0.88, 0.76), control: p(0.50, 0.60))
            path.move(to: p(0.50, 0.72)); path.addLine(to: p(0.50, 0.26))
            path.move(to: p(0.34, 0.40)); path.addLine(to: p(0.66, 0.40))

        case .bullying:
            // A group, and one apart from it.
            for x in [0.16, 0.34, 0.52] {
                path.addEllipse(in: CGRect(x: o.x + CGFloat(x) * s, y: o.y + 0.34 * s,
                                           width: 0.17 * s, height: 0.17 * s))
            }
            path.addEllipse(in: CGRect(x: o.x + 0.74 * s, y: o.y + 0.56 * s,
                                       width: 0.17 * s, height: 0.17 * s))
            path.move(to: p(0.72, 0.34)); path.addLine(to: p(0.90, 0.34))

        case .medicalScenes:
            path.move(to: p(0.50, 0.20)); path.addLine(to: p(0.50, 0.80))
            path.move(to: p(0.22, 0.50)); path.addLine(to: p(0.78, 0.50))
            path.addRoundedRect(in: CGRect(x: o.x + 0.12 * s, y: o.y + 0.12 * s,
                                           width: 0.76 * s, height: 0.76 * s),
                                cornerSize: CGSize(width: 0.20 * s, height: 0.20 * s))

        case .sadEndings:
            // A single drop.
            path.move(to: p(0.50, 0.16))
            path.addQuadCurve(to: p(0.76, 0.56), control: p(0.74, 0.34))
            path.addArc(center: p(0.50, 0.58), radius: 0.26 * s,
                        startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            path.addQuadCurve(to: p(0.50, 0.16), control: p(0.26, 0.34))

        case .fastCutting:
            // Four bars of unequal length — the rhythm of the edit.
            let ys: [CGFloat] = [0.22, 0.40, 0.58, 0.76]
            let ws: [CGFloat] = [0.66, 0.34, 0.76, 0.46]
            for (y, w) in zip(ys, ws) {
                path.move(to: p(0.16, y)); path.addLine(to: p(0.16 + w, y))
            }

        case .suspense:
            // A clock face with the hand nearly at the top.
            path.addEllipse(in: CGRect(x: o.x + 0.14 * s, y: o.y + 0.14 * s,
                                       width: 0.72 * s, height: 0.72 * s))
            path.move(to: p(0.50, 0.50)); path.addLine(to: p(0.50, 0.26))
            path.move(to: p(0.50, 0.50)); path.addLine(to: p(0.68, 0.60))

        case .realisticViolence:
            // A shield with a fracture through it.
            path.move(to: p(0.50, 0.14))
            path.addLine(to: p(0.82, 0.28))
            path.addQuadCurve(to: p(0.50, 0.86), control: p(0.82, 0.70))
            path.addQuadCurve(to: p(0.18, 0.28), control: p(0.18, 0.70))
            path.closeSubpath()
            path.move(to: p(0.44, 0.28)); path.addLine(to: p(0.56, 0.48))
            path.addLine(to: p(0.42, 0.58)); path.addLine(to: p(0.54, 0.76))

        case .strongLanguage:
            // A speech bubble with a struck-through line.
            path.addRoundedRect(in: CGRect(x: o.x + 0.12 * s, y: o.y + 0.18 * s,
                                           width: 0.76 * s, height: 0.50 * s),
                                cornerSize: CGSize(width: 0.16 * s, height: 0.16 * s))
            path.move(to: p(0.32, 0.68)); path.addLine(to: p(0.28, 0.86)); path.addLine(to: p(0.48, 0.68))
            path.move(to: p(0.28, 0.43)); path.addLine(to: p(0.72, 0.43))

        case .horror:
            // A door standing ajar.
            path.addRect(CGRect(x: o.x + 0.18 * s, y: o.y + 0.14 * s,
                                width: 0.50 * s, height: 0.72 * s))
            path.move(to: p(0.68, 0.14))
            path.addLine(to: p(0.86, 0.22))
            path.addLine(to: p(0.86, 0.78))
            path.addLine(to: p(0.68, 0.86))
            path.move(to: p(0.74, 0.52)); path.addLine(to: p(0.78, 0.52))
        }

        return path
    }
}

/// A drawn content mark on its own tile.
struct AspectGlyph: View {
    let aspect: ContentAspect
    var size: CGFloat = 22
    var tint: Color = NestColor.inkSoft
    var lineWidth: CGFloat = 2

    var body: some View {
        AspectGlyphShape(aspect: aspect)
            .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - The nest mark
//
// The app's own glyph: a soft screen resting inside a cradle. Used on the splash,
// the empty states and the single celebration.

struct NestMarkShape: Shape {
    /// 0 = cradle only, 1 = screen fully lit and seated.
    var seat: CGFloat = 1

    var animatableData: CGFloat {
        get { seat }
        set { seat = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let o = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }

        var path = Path()
        // The cradle: an open bowl.
        path.move(to: p(0.06, 0.54))
        path.addQuadCurve(to: p(0.94, 0.54), control: p(0.50, 1.02))

        // The screen, seated by `seat`.
        let lift = (1 - seat) * 0.20
        let top = 0.16 - lift
        let bottom = 0.60 - lift
        path.addRoundedRect(
            in: CGRect(x: o.x + 0.18 * s, y: o.y + top * s,
                       width: 0.64 * s, height: (bottom - top) * s),
            cornerSize: CGSize(width: 0.11 * s, height: 0.11 * s)
        )
        return path
    }
}

struct NestMark: View {
    var size: CGFloat = 40
    var tint: Color = NestColor.amber
    var fill: Color = .clear
    var seat: CGFloat = 1
    var lineWidth: CGFloat = 2.4

    var body: some View {
        ZStack {
            NestMarkShape(seat: seat)
                .fill(fill)
            NestMarkShape(seat: seat)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
