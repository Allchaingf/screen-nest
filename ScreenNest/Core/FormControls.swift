//  FormControls.swift
//  Screen Nest — bespoke form controls.
//
//  No `Form`, no `List`, no system pickers. Every control is drawn from the same
//  tokens as the rest of the app, and every one of them reports its error against
//  the specific field that failed.

import SwiftUI

// MARK: - Field shell

struct FieldShell<Content: View>: View {
    let label: String
    var hint: String?
    var error: String?
    var required: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: NestSpace.s) {
            HStack(spacing: 5) {
                SectionLabel(label)
                if required {
                    Circle()
                        .fill(NestColor.amber)
                        .frame(width: 4, height: 4)
                        .padding(.bottom, 5)
                }
            }
            content()
            if let error = error {
                HStack(alignment: .top, spacing: 6) {
                    ReasonSymbolGlyph(symbol: .unknown, tint: NestColor.stop, size: 13)
                    Text(error)
                        .font(NestFont.small)
                        .foregroundColor(NestColor.stop)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            } else if let hint = hint {
                Text(hint)
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .nestAnimation(NestMotion.settle, value: error ?? "")
    }
}

private struct FieldBackground: ViewModifier {
    let invalid: Bool
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, NestSpace.l)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                    .fill(NestColor.surface)
                    .nestGlowTight()
            )
            .overlay(
                RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                    .stroke(invalid ? NestColor.stop : (focused ? NestColor.amber : NestColor.border),
                            lineWidth: invalid || focused ? NestStroke.heavy : NestStroke.hair)
            )
    }
}

// MARK: - Text

struct NestTextField: View {
    let placeholder: String
    @Binding var text: String
    var invalid: Bool = false
    var keyboard: UIKeyboardType = .default
    var capitalisation: UITextAutocapitalizationType = .sentences

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(NestFont.body)
            .foregroundColor(NestColor.ink)
            .keyboardType(keyboard)
            .autocapitalization(capitalisation)
            .disableAutocorrection(keyboard == .emailAddress)
            .focused($focused)
            .modifier(FieldBackground(invalid: invalid, focused: focused))
    }
}

struct NestTextArea: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 92
    var invalid: Bool = false

    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(NestFont.body)
                    .foregroundColor(NestColor.inkFaint)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(NestFont.body)
                .foregroundColor(NestColor.ink)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .focused($focused)
        }
        .modifier(FieldBackground(invalid: invalid, focused: focused))
    }
}

// MARK: - Numbers

struct NestNumberField: View {
    let placeholder: String
    @Binding var value: Int?
    var suffix: String?
    var invalid: Bool = false

    @FocusState private var focused: Bool
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: NestSpace.s) {
            TextField(placeholder, text: $text)
                .font(NestFont.figureSmall)
                .foregroundColor(NestColor.ink)
                .keyboardType(.numberPad)
                .focused($focused)
                .onChange(of: text) { newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue { text = digits }
                    value = digits.isEmpty ? nil : Int(digits)
                }
            if let suffix = suffix {
                Text(suffix)
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkFaint)
            }
        }
        .modifier(FieldBackground(invalid: invalid, focused: focused))
        .onAppear {
            text = value.map(String.init) ?? ""
        }
    }
}

/// Stepper drawn from the app's own marks. Long-press repeats.
struct NestStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...600
    var step: Int = 1
    var suffix: String = "min"

    var body: some View {
        HStack(spacing: 0) {
            stepButton(symbol: false) { adjust(-step) }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(NestFont.figureSmall)
                    .foregroundColor(NestColor.ink)
                Text(suffix)
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkFaint)
            }
            Spacer(minLength: 0)
            stepButton(symbol: true) { adjust(step) }
        }
        .padding(.horizontal, NestSpace.s)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                .fill(NestColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                .stroke(NestColor.hairline, lineWidth: NestStroke.hair)
        )
    }

    private func adjust(_ delta: Int) {
        let next = min(range.upperBound, max(range.lowerBound, value + delta))
        if next != value {
            value = next
            NestHaptics.tap()
        }
    }

    private func stepButton(symbol plus: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: NestRadius.icon, style: .continuous)
                    .fill(NestColor.amberGradient)
                    .frame(width: 42, height: 34)
                GlyphPath { path, s in
                    path.move(to: CGPoint(x: 0.22 * s, y: 0.5 * s))
                    path.addLine(to: CGPoint(x: 0.78 * s, y: 0.5 * s))
                    if plus {
                        path.move(to: CGPoint(x: 0.5 * s, y: 0.22 * s))
                        path.addLine(to: CGPoint(x: 0.5 * s, y: 0.78 * s))
                    }
                }
                .stroke(NestColor.inkOnAmber, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 16, height: 16)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Slider with the app's tick texture

struct NestSlider: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 5
    var suffix: String = "min"
    var caption: ((Int) -> String)? = nil

    @State private var dragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: NestSpace.s) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(NestFont.figure)
                    .foregroundColor(NestColor.ink)
                Text(suffix)
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkFaint)
                Spacer()
                if let caption = caption {
                    Text(caption(value))
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                }
            }

            GeometryReader { geo in
                let width = geo.size.width
                let span = Double(range.upperBound - range.lowerBound)
                let fraction = span > 0 ? Double(value - range.lowerBound) / span : 0
                ZStack(alignment: .leading) {
                    MinuteTicks(count: 21, height: 6, emphasisEvery: 5, colour: NestColor.hairline)
                        .frame(height: 6)
                        .offset(y: -13)

                    Capsule()
                        .fill(NestColor.anchor.opacity(0.10))
                        .frame(height: 12)

                    Capsule()
                        .fill(NestColor.amberGradient)
                        .frame(width: max(12, width * CGFloat(fraction)), height: 12)

                    Circle()
                        .fill(NestColor.surface)
                        .overlay(Circle().stroke(NestColor.anchor, lineWidth: NestStroke.mark))
                        .frame(width: dragging ? 30 : 26, height: dragging ? 30 : 26)
                        .offset(x: max(0, min(width - 26, width * CGFloat(fraction) - 13)))
                        .nestGlowTight()
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            dragging = true
                            update(x: gesture.location.x, width: width)
                        }
                        .onEnded { _ in dragging = false }
                )
                .animation(NestMotion.snap, value: dragging)
            }
            .frame(height: 30)
        }
    }

    private func update(x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let fraction = Double(max(0, min(width, x)) / width)
        let span = Double(range.upperBound - range.lowerBound)
        let raw = Double(range.lowerBound) + fraction * span
        let stepped = (raw / Double(step)).rounded() * Double(step)
        let clamped = min(range.upperBound, max(range.lowerBound, Int(stepped)))
        if clamped != value {
            value = clamped
            NestHaptics.tap()
        }
    }
}

// MARK: - Toggle

struct NestToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Button {
            NestHaptics.tap()
            isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: NestSpace.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(NestFont.bodyMedium)
                        .foregroundColor(NestColor.ink)
                        .multilineTextAlignment(.leading)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(NestFont.small)
                            .foregroundColor(NestColor.inkSoft)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: NestSpace.s)
                NestSwitch(isOn: isOn)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The switch is a small window bar: the lamp fills as it comes on.
struct NestSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn
                      ? AnyShapeStyle(NestColor.amberGradient)
                      : AnyShapeStyle(NestColor.surfaceSunk))
                .frame(width: 52, height: 30)
            Capsule()
                .stroke(NestColor.anchor.opacity(0.25), lineWidth: NestStroke.hair)
                .frame(width: 52, height: 30)
            Circle()
                .fill(isOn ? NestColor.inkOnAmber : NestColor.inkFaint)
                .frame(width: 22, height: 22)
                .padding(.horizontal, 4)
        }
        .animation(NestMotion.snap, value: isOn)
        .accessibilityHidden(true)
    }
}

// MARK: - Segmented choice

struct NestSegmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let titleFor: (Option) -> String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                let active = option == selection
                Button {
                    NestHaptics.tap()
                    withAnimation(NestMotion.snap) { selection = option }
                } label: {
                    Text(titleFor(option))
                        .font(NestFont.smallMedium)
                        .foregroundColor(active ? NestColor.inkOnAmber : NestColor.inkSoft)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            Capsule(style: .continuous)
                                .fill(active
                                      ? AnyShapeStyle(NestColor.amberGradient)
                                      : AnyShapeStyle(Color.clear))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous).fill(NestColor.surfaceSunk)
        )
        .overlay(
            Capsule(style: .continuous).stroke(NestColor.border, lineWidth: NestStroke.hair)
        )
    }
}

/// Vertical option list for longer choices — every option visible, no wheel.
/// Supports a genuinely empty selection, so a required choice can start unmade.
struct NestOptionList<Option: Hashable>: View {
    let options: [Option]
    private let selected: Option?
    private let select: (Option) -> Void
    let titleFor: (Option) -> String
    var detailFor: ((Option) -> String?)? = nil

    init(options: [Option],
         selection: Binding<Option>,
         titleFor: @escaping (Option) -> String,
         detailFor: ((Option) -> String?)? = nil) {
        self.options = options
        self.selected = selection.wrappedValue
        self.select = { selection.wrappedValue = $0 }
        self.titleFor = titleFor
        self.detailFor = detailFor
    }

    /// Nothing is marked until the choice is actually made.
    init(options: [Option],
         optionalSelection: Binding<Option?>,
         titleFor: @escaping (Option) -> String,
         detailFor: ((Option) -> String?)? = nil) {
        self.options = options
        self.selected = optionalSelection.wrappedValue
        self.select = { optionalSelection.wrappedValue = $0 }
        self.titleFor = titleFor
        self.detailFor = detailFor
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                let active = option == selected
                Button {
                    NestHaptics.tap()
                    withAnimation(NestMotion.snap) { select(option) }
                } label: {
                    HStack(alignment: .top, spacing: NestSpace.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(titleFor(option))
                                .font(NestFont.bodyMedium)
                                .foregroundColor(NestColor.ink)
                                .multilineTextAlignment(.leading)
                            if let detail = detailFor?(option), !detail.isEmpty {
                                Text(detail)
                                    .font(NestFont.small)
                                    .foregroundColor(NestColor.inkSoft)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: NestSpace.s)
                        ZStack {
                            Circle()
                                .fill(active
                                      ? AnyShapeStyle(NestColor.amberGradient)
                                      : AnyShapeStyle(Color.clear))
                                .frame(width: 24, height: 24)
                            Circle()
                                .stroke(active ? NestColor.anchor.opacity(0.25) : NestColor.border,
                                        lineWidth: NestStroke.mark)
                                .frame(width: 24, height: 24)
                            if active {
                                Circle().fill(NestColor.inkOnAmber).frame(width: 9, height: 9)
                            }
                        }
                        .padding(.top, 2)
                    }
                    .padding(.vertical, NestSpace.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < options.count - 1 {
                    Rectangle()
                        .fill(NestColor.hairline)
                        .frame(height: NestStroke.hair)
                }
            }
        }
        .padding(.horizontal, NestSpace.l)
        .background(
            RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                .fill(NestColor.surface)
                .nestGlow()
        )
        .overlay(
            RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                .stroke(NestColor.hairline, lineWidth: NestStroke.hair)
        )
    }
}

// MARK: - Time

/// Bedtimes and cut-offs are set with a dial, not a system wheel: hours step by
/// one, minutes by five, and the reading stays in the serif face throughout.
struct NestTimeField: View {
    @Binding var time: TimeOfDay
    var presets: [TimeOfDay] = [
        TimeOfDay(hour: 19, minute: 0),
        TimeOfDay(hour: 19, minute: 30),
        TimeOfDay(hour: 20, minute: 0),
        TimeOfDay(hour: 20, minute: 30),
        TimeOfDay(hour: 21, minute: 0)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            HStack(spacing: NestSpace.m) {
                unit(label: "hour", value: time.hour) { delta in
                    time = TimeOfDay(minutesFromMidnight: time.minutesFromMidnight + delta * 60)
                }
                Text(":")
                    .font(NestFont.figure)
                    .foregroundColor(NestColor.inkFaint)
                unit(label: "minute", value: time.minute, pad: true) { delta in
                    time = TimeOfDay(minutesFromMidnight: time.minutesFromMidnight + delta * 5)
                }
            }

            if !presets.isEmpty {
                HStack(spacing: NestSpace.s) {
                    ForEach(presets, id: \.self) { preset in
                        NestChip(title: preset.display,
                                 selected: preset == time,
                                 action: {
                            withAnimation(NestMotion.snap) { time = preset }
                        })
                    }
                }
            }
        }
    }

    private func unit(label: String, value: Int, pad: Bool = false,
                      change: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 4) {
            arrow(up: true) { change(1) }
            Text(pad ? String(format: "%02d", value) : "\(value)")
                .font(NestFont.figure)
                .foregroundColor(NestColor.ink)
                .frame(minWidth: 52)
            arrow(up: false) { change(-1) }
            SectionLabel(label)
        }
        .padding(.vertical, NestSpace.s)
        .padding(.horizontal, NestSpace.m)
        .background(
            RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                .fill(NestColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                .stroke(NestColor.hairline, lineWidth: NestStroke.hair)
        )
    }

    private func arrow(up: Bool, action: @escaping () -> Void) -> some View {
        Button {
            NestHaptics.tap()
            action()
        } label: {
            GlyphPath { path, s in
                if up {
                    path.move(to: CGPoint(x: 0.18 * s, y: 0.66 * s))
                    path.addLine(to: CGPoint(x: 0.50 * s, y: 0.32 * s))
                    path.addLine(to: CGPoint(x: 0.82 * s, y: 0.66 * s))
                } else {
                    path.move(to: CGPoint(x: 0.18 * s, y: 0.34 * s))
                    path.addLine(to: CGPoint(x: 0.50 * s, y: 0.68 * s))
                    path.addLine(to: CGPoint(x: 0.82 * s, y: 0.34 * s))
                }
            }
            .stroke(NestColor.amberSunk, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: 22, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Date

/// Calendar strip: fourteen days, chosen by tapping. Enough for planning an
/// evening and nothing more.
struct NestDateStrip: View {
    @Binding var date: Date
    var daysBack: Int = 2
    var daysForward: Int = 12

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (-daysBack...daysForward).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NestSpace.s) {
                ForEach(days, id: \.self) { day in
                    let active = Calendar.current.isDate(day, inSameDayAs: date)
                    Button {
                        NestHaptics.tap()
                        withAnimation(NestMotion.snap) { date = day }
                    } label: {
                        VStack(spacing: 3) {
                            nestTracked(shortWeekday(day).lowercased(), kern: 0.8)
                                .font(NestFont.label)
                                .foregroundColor(active ? NestColor.ink : NestColor.inkFaint)
                            Text(dayNumber(day))
                                .font(NestFont.posterTitle(19))
                                .foregroundColor(active ? NestColor.ink : NestColor.inkSoft)
                            Circle()
                                .fill(Calendar.current.isDateInWeekend(day) ? NestColor.plum : Color.clear)
                                .frame(width: 4, height: 4)
                        }
                        .frame(width: 46)
                        .padding(.vertical, NestSpace.s)
                        .background(
                            RoundedRectangle(cornerRadius: NestRadius.chip, style: .continuous)
                                .fill(active ? NestColor.amberWash : NestColor.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: NestRadius.chip, style: .continuous)
                                .stroke(active ? NestColor.amber : NestColor.hairline,
                                        lineWidth: active ? 1.5 : NestStroke.hair)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func shortWeekday(_ day: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: day)
    }

    private func dayNumber(_ day: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: day)
    }
}

// MARK: - Search

struct NestSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: NestSpace.s) {
            GlyphPath { path, s in
                path.addEllipse(in: CGRect(x: 0.10 * s, y: 0.10 * s, width: 0.56 * s, height: 0.56 * s))
                path.move(to: CGPoint(x: 0.62 * s, y: 0.62 * s))
                path.addLine(to: CGPoint(x: 0.90 * s, y: 0.90 * s))
            }
            .stroke(NestColor.inkFaint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 17, height: 17)

            TextField(placeholder, text: $text)
                .font(NestFont.body)
                .foregroundColor(NestColor.ink)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit { onSubmit?() }

            if !text.isEmpty {
                Button {
                    NestHaptics.tap()
                    text = ""
                } label: {
                    GlyphPath { path, s in
                        path.move(to: CGPoint(x: 0.25 * s, y: 0.25 * s))
                        path.addLine(to: CGPoint(x: 0.75 * s, y: 0.75 * s))
                        path.move(to: CGPoint(x: 0.75 * s, y: 0.25 * s))
                        path.addLine(to: CGPoint(x: 0.25 * s, y: 0.75 * s))
                    }
                    .stroke(NestColor.inkFaint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 15, height: 15)
                }
                .buttonStyle(.plain)
            }
        }
        .modifier(FieldBackground(invalid: false, focused: focused))
    }
}

// MARK: - Rows

/// A tappable settings / navigation row.
struct NestRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var tint: Color = NestColor.ink
    @ViewBuilder var trailing: () -> Trailing
    var action: (() -> Void)?

    var body: some View {
        let content = HStack(alignment: .center, spacing: NestSpace.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(NestFont.bodyMedium)
                    .foregroundColor(tint)
                    .multilineTextAlignment(.leading)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: NestSpace.s)
            trailing()
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())

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

extension NestRow where Trailing == Chevron {
    init(_ title: String, subtitle: String? = nil, tint: Color = NestColor.ink, action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, tint: tint, trailing: { Chevron() }, action: action)
    }
}

struct Chevron: View {
    var body: some View {
        GlyphPath { path, s in
            path.move(to: CGPoint(x: 0.35 * s, y: 0.18 * s))
            path.addLine(to: CGPoint(x: 0.68 * s, y: 0.50 * s))
            path.addLine(to: CGPoint(x: 0.35 * s, y: 0.82 * s))
        }
        .stroke(NestColor.inkFaint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        .frame(width: 13, height: 13)
        .accessibilityHidden(true)
    }
}

/// Stack of rows inside one card with tick separators.
struct NestRowGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, NestSpace.l)
        .background(
            RoundedRectangle(cornerRadius: NestRadius.card, style: .continuous)
                .fill(NestColor.surface)
                .nestGlow()
        )
        .overlay(
            RoundedRectangle(cornerRadius: NestRadius.card, style: .continuous)
                .stroke(NestColor.hairline, lineWidth: NestStroke.hair)
        )
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(NestColor.hairline)
            .frame(height: NestStroke.hair)
    }
}
