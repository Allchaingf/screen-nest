//  SuitabilityEngine.swift
//  Screen Nest — the suitability check.
//
//  There is no score anywhere in this file, on purpose. The engine produces
//  sentences: one line per thing the parent would otherwise have to hold in
//  their head. A status is only ever a summary of those lines.
//
//  Not Yet  →  about age and content. It changes with a birthday.
//  Not Tonight → about the clock and the house rules. It changes on Saturday.

import Foundation

// MARK: - Status

enum SuitabilityStatus: String, CaseIterable {
    case fitsEveryone
    case fitsOlderOnly
    case needsAParent
    case notTonight
    case notYet

    var title: String {
        switch self {
        case .fitsEveryone: return "Fits Everyone"
        case .fitsOlderOnly: return "Fits Older Only"
        case .needsAParent: return "Needs a Parent"
        case .notTonight: return "Not Tonight"
        case .notYet: return "Not Yet"
        }
    }

    /// Sorting weight for "Fits Tonight" lists. Lower is better.
    var rank: Int {
        switch self {
        case .fitsEveryone: return 0
        case .fitsOlderOnly: return 1
        case .needsAParent: return 2
        case .notTonight: return 3
        case .notYet: return 4
        }
    }

    var isOffer: Bool { self == .fitsEveryone || self == .fitsOlderOnly }
}

enum ReasonTone {
    case positive, neutral, caution, blocking
}

enum ReasonSymbol {
    case certification, content, clock, rule, history, note, attention, unknown, screenTime, split
}

enum ReasonKind {
    /// Blocks because of age or what is in it — "Not Yet".
    case ageOrContent
    /// Blocks because of the clock or a rule — "Not Tonight".
    case timeOrRule
    /// Needs an adult in the room.
    case parentNeeded
    /// Information only, never blocks.
    case info
}

struct SuitabilityReason: Identifiable, Hashable {
    let id: UUID
    let tone: ReasonTone
    let symbol: ReasonSymbol
    let aspect: ContentAspect?
    let sentence: String
    let viewerId: UUID?
    let kind: ReasonKind

    init(id: UUID = UUID(),
         tone: ReasonTone,
         symbol: ReasonSymbol,
         aspect: ContentAspect? = nil,
         sentence: String,
         viewerId: UUID? = nil,
         kind: ReasonKind = .info) {
        self.id = id
        self.tone = tone
        self.symbol = symbol
        self.aspect = aspect
        self.sentence = sentence
        self.viewerId = viewerId
        self.kind = kind
    }

    var blocks: Bool { tone == .blocking }

    static func == (lhs: SuitabilityReason, rhs: SuitabilityReason) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Per-viewer verdict

struct ViewerVerdict: Identifiable, Hashable {
    var id: UUID { viewer.id }
    let viewer: Viewer
    let reasons: [SuitabilityReason]
    let blockedByAgeOrContent: Bool
    let needsAdult: Bool
    /// Filled when the block is about age: "Try again after his next birthday."
    let changesWhen: String?
}

// MARK: - Result

struct SuitabilityResult {
    let status: SuitabilityStatus
    let reasons: [SuitabilityReason]
    let viewerVerdicts: [ViewerVerdict]
    let windowMinutes: Int
    let runtimeMinutes: Int
    let fitsWindow: Bool
    let spareMinutes: Int
    /// "Not tonight — 104 minutes does not fit before bedtime. It fits on Saturday."
    let changesWhen: String?
    /// Short sentence for a Pick card.
    let headline: String
    let splitSuggestion: (first: Int, second: Int)?
    let brokenRules: [HouseRule]
    let hasContentDetail: Bool

    var blockingReasons: [SuitabilityReason] { reasons.filter(\.blocks) }
}

// MARK: - Input

struct SuitabilityContext {
    var title: Title
    var viewers: [Viewer]
    var rules: [HouseRule]
    var profile: HouseProfile
    var window: EveningWindow
    var date: Date
    /// Effective runtime — an episode's, when the evening is a series night.
    var runtimeOverride: Int?
    var previousMarks: [MarkedMoment]
    var warningNotes: [ContentNote]
    var watchCount: Int
    var enthusiasts: [Viewer]
    var screenTimeRemaining: [UUID: Int]
    var titlesAlreadyPlannedTonight: Int
    var nextRoomierDay: (dayName: String, minutes: Int)?
}

// MARK: - Engine

enum SuitabilityEngine {

    static func evaluate(_ context: SuitabilityContext) -> SuitabilityResult {
        let title = context.title
        let country = context.profile.ratingCountry
        let runtime = context.runtimeOverride ?? title.runtimeMinutes
        let windowMinutes = context.window.filmMinutes

        var shared: [SuitabilityReason] = []
        var verdicts: [ViewerVerdict] = []
        var brokenRules: [HouseRule] = []

        let certCode = title.certification(for: country)
        let cert = certCode.flatMap { country.certification(code: $0) }
        let certAge = cert?.minimumAge

        // ── 1. Certification ─────────────────────────────────────────────
        if let cert = cert {
            let tooYoung = context.viewers.filter { viewer in
                guard let age = viewer.age, !viewer.role.isGrownUp else { return false }
                return age < cert.minimumAge
            }
            if tooYoung.isEmpty {
                shared.append(SuitabilityReason(
                    tone: .positive, symbol: .certification,
                    sentence: "Certification \(cert.code) in \(country.countryName) (\(country.bodyName)). Everyone here is old enough.",
                    kind: .info))
            } else if cert.advisory {
                shared.append(SuitabilityReason(
                    tone: .caution, symbol: .certification,
                    sentence: "\(cert.code) is not an age bar — it is a request for your judgement.",
                    kind: .parentNeeded))
            }
            if cert.advisory && tooYoung.isEmpty {
                shared.append(SuitabilityReason(
                    tone: .neutral, symbol: .certification,
                    sentence: cert.note, kind: .info))
            }
        } else {
            shared.append(SuitabilityReason(
                tone: .caution, symbol: .unknown,
                sentence: "No certification for \(country.countryName). Decide for yourself, or add a content note.",
                kind: .info))
        }

        // ── 2. What it contains ──────────────────────────────────────────
        if !title.hasContentDetail {
            shared.append(SuitabilityReason(
                tone: .caution, symbol: .unknown,
                sentence: "No content details for this title. Add what you know, or watch it yourself first.",
                kind: .info))
        }

        for aspect in title.contentAspects {
            let sensitive = context.viewers.filter { $0.activeAspects.contains(aspect) }
            if sensitive.isEmpty {
                shared.append(SuitabilityReason(
                    tone: .neutral, symbol: .content, aspect: aspect,
                    sentence: "Contains: \(aspect.phrase). Nobody in this evening is sensitive to it.",
                    kind: .info))
            } else {
                let names = listed(sensitive.map(\.name))
                let verb = sensitive.count == 1 ? "is" : "are"
                shared.append(SuitabilityReason(
                    tone: .blocking, symbol: .content, aspect: aspect,
                    sentence: "Contains: \(aspect.phrase). \(names) \(verb) marked sensitive to this.",
                    kind: .ageOrContent))
            }
        }

        // ── 3. The clock ─────────────────────────────────────────────────
        let fitsWindow = runtime > 0 && runtime <= windowMinutes
        let spare = windowMinutes - runtime
        if runtime <= 0 {
            shared.append(SuitabilityReason(
                tone: .caution, symbol: .clock,
                sentence: "No running time recorded, so the evening window cannot be checked.",
                kind: .info))
        } else if fitsWindow {
            shared.append(SuitabilityReason(
                tone: .positive, symbol: .clock,
                sentence: "Runtime \(runtime) minutes. Tonight's window is \(windowMinutes) — it fits with \(spare) to spare.",
                kind: .info))
        } else {
            shared.append(SuitabilityReason(
                tone: .blocking, symbol: .clock,
                sentence: "Runtime \(runtime) minutes. Tonight's window is \(windowMinutes).",
                kind: .timeOrRule))
        }

        // ── 4. House rules ───────────────────────────────────────────────
        let isWeeknight = !Calendar.current.isDateInWeekend(context.date)
        for rule in context.rules where rule.isActive {
            guard let breach = breachSentence(rule: rule,
                                              title: title,
                                              runtime: runtime,
                                              country: country,
                                              viewers: context.viewers,
                                              window: context.window,
                                              isWeeknight: isWeeknight,
                                              alreadyPlanned: context.titlesAlreadyPlannedTonight)
            else { continue }
            brokenRules.append(rule)
            shared.append(SuitabilityReason(
                tone: .blocking,
                symbol: .rule,
                sentence: "House rule: \(breach.sentence)",
                kind: breach.kind))
        }

        // ── 5. What happened here before ─────────────────────────────────
        for note in context.warningNotes {
            let stamp = note.timecode.map { "At \($0) " } ?? ""
            let who = context.viewers.filter { note.whoReacted.contains($0.id) }
            let tail = who.isEmpty ? "" : " \(listed(who.map(\.name))) reacted last time."
            shared.append(SuitabilityReason(
                tone: .caution, symbol: .note,
                sentence: "\(stamp)\(note.whatHappens)\(tail)",
                kind: .info))
        }

        for mark in context.previousMarks where mark.kind.isCautionary {
            shared.append(SuitabilityReason(
                tone: .caution, symbol: .history,
                sentence: "Last time you marked a \(mark.kind.title.lowercased()) moment at \(mark.timecode).",
                kind: .info))
        }

        if context.watchCount > 0 {
            let times = context.watchCount == 1 ? "once" : "\(context.watchCount) times"
            if let fan = context.enthusiasts.first {
                shared.append(SuitabilityReason(
                    tone: .positive, symbol: .history,
                    sentence: "\(fan.name) has watched this \(times) and asks for it again.",
                    kind: .info))
            } else {
                shared.append(SuitabilityReason(
                    tone: .neutral, symbol: .history,
                    sentence: "Watched \(times) in this house.",
                    kind: .info))
            }
        }

        // ── 6. Per-viewer verdicts ───────────────────────────────────────
        for viewer in context.viewers {
            var lines: [SuitabilityReason] = []
            var blocked = false
            var needsAdult = false
            var changes: String? = nil

            if let cert = cert, let age = viewer.age, !viewer.role.isGrownUp, age < cert.minimumAge {
                if cert.adultAccompanimentAllowed {
                    needsAdult = true
                    lines.append(SuitabilityReason(
                        tone: .caution, symbol: .certification,
                        sentence: "Certification \(cert.code) in \(country.countryName). \(viewer.name) is \(age) — admitted with an adult.",
                        viewerId: viewer.id, kind: .parentNeeded))
                } else {
                    blocked = true
                    let gap = cert.minimumAge - age
                    changes = gap <= 1
                        ? "Not yet for \(viewer.name). Try again after the next birthday."
                        : "Not yet for \(viewer.name). This one is \(gap) years away."
                    lines.append(SuitabilityReason(
                        tone: .blocking, symbol: .certification,
                        sentence: "Certification \(cert.code) in \(country.countryName). \(viewer.name) is \(age).",
                        viewerId: viewer.id, kind: .ageOrContent))
                }
            }

            let hits = title.contentAspects.filter { viewer.activeAspects.contains($0) }
            for aspect in hits {
                blocked = true
                lines.append(SuitabilityReason(
                    tone: .blocking, symbol: .content, aspect: aspect,
                    sentence: "\(viewer.name) is marked sensitive to \(aspect.phrase).",
                    viewerId: viewer.id, kind: .ageOrContent))
            }

            // Attention span never blocks — it proposes a split.
            if runtime > 0, !viewer.role.isGrownUp, runtime > viewer.attentionSpanMinutes {
                lines.append(SuitabilityReason(
                    tone: .caution, symbol: .split,
                    sentence: "\(runtime) minutes is longer than \(viewer.name) usually manages in one sitting (\(viewer.attentionSpanMinutes)). Splitting it over two evenings is ordinary practice.",
                    viewerId: viewer.id, kind: .info))
            }

            if let remaining = context.screenTimeRemaining[viewer.id], runtime > 0, remaining < runtime {
                lines.append(SuitabilityReason(
                    tone: .caution, symbol: .screenTime,
                    sentence: "\(viewer.name) has \(remaining) minutes left this week. This one is \(runtime).",
                    viewerId: viewer.id, kind: .info))
            }

            for love in viewer.loves where matchesLove(love, title: title) {
                lines.append(SuitabilityReason(
                    tone: .positive, symbol: .history,
                    sentence: "\(love) — \(viewer.possessive) favourite.",
                    viewerId: viewer.id, kind: .info))
            }

            if lines.isEmpty {
                lines.append(SuitabilityReason(
                    tone: .positive, symbol: .content,
                    sentence: "Nothing here is marked against \(viewer.name).",
                    viewerId: viewer.id, kind: .info))
            }

            verdicts.append(ViewerVerdict(viewer: viewer,
                                          reasons: lines,
                                          blockedByAgeOrContent: blocked,
                                          needsAdult: needsAdult,
                                          changesWhen: changes))
        }

        // ── 7. Parent in the room ────────────────────────────────────────
        let adultPresent = context.viewers.contains { $0.role.isGrownUp }
        let parentRule = context.rules.first { rule in
            rule.isActive && rule.type == .parentMustWatchTogether &&
            context.viewers.contains { viewer in rule.applies(to: viewer) && !viewer.role.isGrownUp }
        }
        var parentNeeded = verdicts.contains(where: \.needsAdult)
        if parentRule != nil && !adultPresent {
            parentNeeded = true
        }
        if cert?.advisory == true && context.viewers.contains(where: { !$0.role.isGrownUp }) && !adultPresent {
            parentNeeded = true
        }

        // ── 8. Status ────────────────────────────────────────────────────
        let children = context.viewers.filter { !$0.role.isGrownUp }
        let blockedViewers = verdicts.filter(\.blockedByAgeOrContent)
        let timeOrRuleBlocked = shared.contains { $0.blocks && $0.kind == .timeOrRule }

        let status: SuitabilityStatus
        if !children.isEmpty && blockedViewers.count >= children.count {
            status = .notYet
        } else if context.viewers.isEmpty && !blockedViewers.isEmpty {
            status = .notYet
        } else if timeOrRuleBlocked {
            status = .notTonight
        } else if parentNeeded && !adultPresent {
            status = .needsAParent
        } else if !blockedViewers.isEmpty {
            status = .fitsOlderOnly
        } else {
            status = .fitsEveryone
        }

        // ── 9. When does this change? ────────────────────────────────────
        var changesWhen: String?
        switch status {
        case .notTonight:
            if !fitsWindow, runtime > 0 {
                if let roomier = context.nextRoomierDay, roomier.minutes >= runtime {
                    changesWhen = "Not tonight — \(runtime) minutes does not fit before bedtime. It fits on \(roomier.dayName)."
                } else {
                    changesWhen = "Not tonight — \(runtime) minutes does not fit before bedtime. An earlier start would give you the room."
                }
            } else if let rule = brokenRules.first {
                changesWhen = "Not tonight — \(rule.type.title.lowercased()). You can allow an exception on the review step."
            }
        case .notYet, .fitsOlderOnly:
            changesWhen = verdicts.compactMap(\.changesWhen).first
        case .needsAParent:
            changesWhen = "Add an adult to this evening, or watch it together."
        case .fitsEveryone:
            changesWhen = nil
        }

        // ── 10. Headline for a Pick card ─────────────────────────────────
        let headline = makeHeadline(status: status,
                                    runtime: runtime,
                                    spare: spare,
                                    fits: fitsWindow,
                                    viewers: context.viewers,
                                    verdicts: verdicts,
                                    enthusiasts: context.enthusiasts,
                                    title: title,
                                    blockingReason: shared.first(where: \.blocks))

        let shortestSpan = children.map(\.attentionSpanMinutes).min() ?? 90
        let split = WindowEngine.splitSuggestion(runtimeMinutes: runtime,
                                                 windowMinutes: max(windowMinutes, 1),
                                                 attentionSpan: shortestSpan)

        return SuitabilityResult(
            status: status,
            reasons: shared,
            viewerVerdicts: verdicts,
            windowMinutes: windowMinutes,
            runtimeMinutes: runtime,
            fitsWindow: fitsWindow,
            spareMinutes: spare,
            changesWhen: changesWhen,
            headline: headline,
            splitSuggestion: split,
            brokenRules: brokenRules,
            hasContentDetail: title.hasContentDetail
        )
    }

    // MARK: - Rules

    private struct Breach {
        let sentence: String
        let kind: ReasonKind
    }

    private static func breachSentence(rule: HouseRule,
                                       title: Title,
                                       runtime: Int,
                                       country: RatingCountry,
                                       viewers: [Viewer],
                                       window: EveningWindow,
                                       isWeeknight: Bool,
                                       alreadyPlanned: Int) -> Breach? {
        let covered = viewers.filter { rule.applies(to: $0) }
        guard !covered.isEmpty || viewers.isEmpty else { return nil }

        switch rule.type {
        case .maxCertificationPerAge:
            guard let limitCode = rule.certificationCode,
                  let limitRank = country.rank(of: limitCode),
                  let titleCode = title.certification(for: country),
                  let titleRank = country.rank(of: titleCode),
                  let ageBar = rule.age
            else { return nil }
            let affected = covered.filter { viewer in
                guard let age = viewer.age, !viewer.role.isGrownUp else { return false }
                return age < ageBar
            }
            guard !affected.isEmpty, titleRank > limitRank else { return nil }
            return Breach(sentence: "under \(ageBar), nothing above \(limitCode). This is \(titleCode).",
                          kind: .ageOrContent)

        case .noStrongLanguage:
            guard title.contentAspects.contains(.strongLanguage) else { return nil }
            return Breach(sentence: "no strong language. This title is marked with it.", kind: .ageOrContent)

        case .noRealisticViolence:
            guard title.contentAspects.contains(.realisticViolence) else { return nil }
            return Breach(sentence: "no realistic violence. This title is marked with it.", kind: .ageOrContent)

        case .noHorror:
            guard title.contentAspects.contains(.horror) else { return nil }
            return Breach(sentence: "no horror. This title is marked as horror.", kind: .ageOrContent)

        case .subtitlesOnlyAboveAge:
            guard let ageBar = rule.age,
                  title.originalName.trimmingCharacters(in: .whitespaces).isEmpty == false,
                  title.originalName.caseInsensitiveCompare(title.name) != .orderedSame
            else { return nil }
            let tooYoung = covered.filter { viewer in
                guard let age = viewer.age, !viewer.role.isGrownUp else { return false }
                return age < ageBar
            }
            guard !tooYoung.isEmpty else { return nil }
            return Breach(sentence: "subtitles only from age \(ageBar). \(listed(tooYoung.map(\.name))) would be reading along.",
                          kind: .ageOrContent)

        case .maxRuntimeOnWeeknights:
            guard isWeeknight, let cap = rule.minutes, runtime > cap else { return nil }
            return Breach(sentence: "maximum \(cap) minutes on weeknights. This is \(runtime).", kind: .timeOrRule)

        case .oneFilmPerEvening:
            guard alreadyPlanned >= 1 else { return nil }
            return Breach(sentence: "one film per evening. There is already one planned tonight.", kind: .timeOrRule)

        case .noScreensAfterTime:
            guard let cutoff = rule.time else { return nil }
            let finishAt = window.referenceTime.minutesFromMidnight + max(0, runtime)
            guard finishAt > cutoff.minutesFromMidnight else { return nil }
            let weekday = isWeeknight ? " on weeknights" : ""
            return Breach(sentence: "no screens after \(cutoff.display)\(weekday). This would run to \(TimeOfDay(minutesFromMidnight: finishAt).display).",
                          kind: .timeOrRule)

        case .parentMustWatchTogether:
            let hasAdult = viewers.contains { $0.role.isGrownUp }
            guard !hasAdult, covered.contains(where: { !$0.role.isGrownUp }) else { return nil }
            return Breach(sentence: "a parent has to watch this together. No adult is in this evening.",
                          kind: .parentNeeded)
        }
    }

    // MARK: - Sentence helpers

    private static func makeHeadline(status: SuitabilityStatus,
                                     runtime: Int,
                                     spare: Int,
                                     fits: Bool,
                                     viewers: [Viewer],
                                     verdicts: [ViewerVerdict],
                                     enthusiasts: [Viewer],
                                     title: Title,
                                     blockingReason: SuitabilityReason?) -> String {
        switch status {
        case .fitsEveryone:
            if fits, spare >= 0 {
                if let fan = enthusiasts.first {
                    return "\(runtime) minutes, fits with \(spare) to spare. \(fan.name) has been asking."
                }
                if viewers.count > 1 {
                    return "\(runtime) minutes, fits with \(spare) to spare. All \(viewers.count) are fine with it."
                }
                return "\(runtime) minutes, fits with \(spare) to spare."
            }
            return "Nothing is marked against tonight."
        case .fitsOlderOnly:
            let blocked = verdicts.filter(\.blockedByAgeOrContent).map(\.viewer.name)
            return "Fine for the older ones. Not for \(listed(blocked))."
        case .needsAParent:
            return "Fine with an adult in the room."
        case .notTonight:
            return blockingReason?.sentence ?? "Does not fit tonight."
        case .notYet:
            return blockingReason?.sentence ?? "Not for this house yet."
        }
    }

    private static func matchesLove(_ love: String, title: Title) -> Bool {
        let needle = love.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.count >= 3 else { return false }
        let haystack = ([title.name, title.shortDescription] + title.genres + title.personalTags)
            .joined(separator: " ")
            .lowercased()
        return haystack.contains(needle)
    }

    static func listed(_ names: [String]) -> String {
        switch names.count {
        case 0: return "Nobody"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
    }
}
