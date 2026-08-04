//  InsightsEngine.swift
//  Screen Nest — what actually happened.
//
//  Built only from completed evenings. Under three evenings there is nothing
//  honest to say, so the section says that instead of drawing an empty chart.

import Foundation

struct InsightBar: Identifiable, Hashable {
    var id: String { label }
    let label: String
    /// 0…1 of the widest bar in the set.
    let fraction: Double
    let caption: String
    let highlighted: Bool
}

struct Insight: Identifiable, Hashable {
    let id: String
    let title: String
    /// The finding, in a sentence.
    let headline: String
    let detail: String
    let bars: [InsightBar]
    /// Evenings this insight was computed from.
    let eveningIds: [UUID]
    /// Set when the insight offers something to act on.
    let action: InsightAction?
}

enum InsightAction: Hashable {
    case markGrownOut(viewerId: UUID, sensitivityId: UUID, viewerName: String, aspect: ContentAspect)
    case openTitle(titleId: UUID, name: String)

    var title: String {
        switch self {
        case .markGrownOut(_, _, let name, let aspect):
            return "Mark \(aspect.title.lowercased()) grown out of for \(name)"
        case .openTitle(_, let name):
            return "Open \(name)"
        }
    }
}

enum InsightsEngine {

    static let minimumEvenings = 3

    static func completed(_ document: AppDocument) -> [Evening] {
        document.evenings.filter { $0.state == .completed }
    }

    static func canBuild(_ document: AppDocument) -> Bool {
        completed(document).count >= minimumEvenings
    }

    static func build(_ document: AppDocument) -> [Insight] {
        let evenings = completed(document)
        guard evenings.count >= minimumEvenings else { return [] }

        var insights: [Insight] = []
        if let insight = runtimeThatWorks(evenings, document: document) { insights.append(insight) }
        if let insight = genresThatLand(evenings, document: document) { insights.append(insight) }
        if let insight = stoppedEarly(evenings) { insights.append(insight) }
        if let insight = certificationsFollowed(evenings, document: document) { insights.append(insight) }
        if let insight = sensitivitiesThatFaded(evenings, document: document) { insights.append(insight) }
        if let insight = mostRewatched(evenings, document: document) { insights.append(insight) }
        if let insight = timeToChoose(evenings) { insights.append(insight) }
        if let insight = splitEvenings(evenings) { insights.append(insight) }
        return insights
    }

    // MARK: - Runtime that actually works

    private struct Bucket {
        let label: String
        let range: Range<Int>
    }

    private static let buckets: [Bucket] = [
        Bucket(label: "under 30", range: 0..<30),
        Bucket(label: "30–60", range: 30..<60),
        Bucket(label: "60–90", range: 60..<90),
        Bucket(label: "90–120", range: 90..<120),
        Bucket(label: "over 120", range: 120..<10_000)
    ]

    private static func runtimeThatWorks(_ evenings: [Evening], document: AppDocument) -> Insight? {
        var finished: [Int: Int] = [:]
        var total: [Int: Int] = [:]
        var ids: [Int: [UUID]] = [:]

        for evening in evenings {
            let runtime = evening.plannedRuntimeMinutes
            guard runtime > 0, let index = buckets.firstIndex(where: { $0.range.contains(runtime) }) else { continue }
            total[index, default: 0] += 1
            ids[index, default: []].append(evening.id)
            if evening.outcome == .finished { finished[index, default: 0] += 1 }
        }
        guard total.values.reduce(0, +) >= minimumEvenings else { return nil }

        let bars: [InsightBar] = buckets.enumerated().compactMap { index, bucket in
            guard let count = total[index], count > 0 else { return nil }
            let done = finished[index] ?? 0
            let rate = Double(done) / Double(count)
            return InsightBar(label: bucket.label,
                              fraction: rate,
                              caption: "\(done) of \(count) finished",
                              highlighted: false)
        }
        guard !bars.isEmpty else { return nil }

        let best = bars.max { lhs, rhs in
            if lhs.fraction == rhs.fraction { return lhs.label < rhs.label }
            return lhs.fraction < rhs.fraction
        }
        let marked = bars.map {
            InsightBar(label: $0.label, fraction: $0.fraction, caption: $0.caption,
                       highlighted: $0.label == best?.label)
        }

        let headline: String
        if let best = best, best.fraction > 0 {
            headline = "Films of \(best.label) minutes get finished most often in this house."
        } else {
            headline = "Nothing has been finished yet at any length."
        }

        return Insight(
            id: "runtime",
            title: "Runtime That Actually Works",
            headline: headline,
            detail: "This is the length at which your children reach the end, rather than the length a film happens to be.",
            bars: marked,
            eveningIds: ids.values.flatMap { $0 },
            action: nil
        )
    }

    // MARK: - Genres that land

    private static func genresThatLand(_ evenings: [Evening], document: AppDocument) -> Insight? {
        var scores: [String: [Int]] = [:]
        var ids: [String: [UUID]] = [:]

        for evening in evenings {
            let genres = evening.titleSnapshot?.genres ?? []
            let weights = evening.reactions.compactMap { $0.impression?.weight }
            guard !genres.isEmpty, !weights.isEmpty else { continue }
            for genre in genres {
                scores[genre, default: []].append(contentsOf: weights)
                ids[genre, default: []].append(evening.id)
            }
        }
        guard scores.count >= 2 else { return nil }

        let averages = scores.map { (genre, values) -> (String, Double, Int) in
            (genre, Double(values.reduce(0, +)) / Double(values.count), values.count)
        }
        .sorted { $0.1 > $1.1 }

        let bars = averages.prefix(6).map { entry in
            InsightBar(label: entry.0,
                       fraction: (entry.1 - 1) / 4,
                       caption: "\(entry.2) reaction\(entry.2 == 1 ? "" : "s")",
                       highlighted: entry.0 == averages.first?.0)
        }

        return Insight(
            id: "genres",
            title: "Genres That Land",
            headline: "\(averages[0].0) lands best with your viewers.",
            detail: "Ordered by the impressions you recorded afterwards, not by what anyone says is popular.",
            bars: Array(bars),
            eveningIds: ids.values.flatMap { $0 },
            action: nil
        )
    }

    // MARK: - Stopped early and why

    private static func stoppedEarly(_ evenings: [Evening]) -> Insight? {
        let stopped = evenings.filter { $0.outcome == .stoppedEarly }
        guard !stopped.isEmpty else { return nil }

        var counts: [StopReason: Int] = [:]
        for evening in stopped {
            guard let reason = evening.watch.stopReason else { continue }
            counts[reason, default: 0] += 1
        }
        let maximum = max(1, counts.values.max() ?? 1)
        let bars = StopReason.allCases.compactMap { reason -> InsightBar? in
            guard let count = counts[reason], count > 0 else { return nil }
            return InsightBar(label: reason.title,
                              fraction: Double(count) / Double(maximum),
                              caption: "\(count)",
                              highlighted: count == maximum)
        }
        let leading = counts.max { $0.value < $1.value }?.key

        return Insight(
            id: "stopped",
            title: "Stopped Early and Why",
            headline: leading.map { "Most often it stops because of: \($0.title.lowercased())." }
                ?? "\(stopped.count) evening\(stopped.count == 1 ? "" : "s") stopped early.",
            detail: "\(stopped.count) of \(evenings.count) evenings ended before the film did.",
            bars: bars,
            eveningIds: stopped.map(\.id),
            action: nil
        )
    }

    // MARK: - Certifications you really follow

    private static func certificationsFollowed(_ evenings: [Evening], document: AppDocument) -> Insight? {
        let withCert = evenings.filter { $0.titleSnapshot?.certificationCode != nil }
        guard withCert.count >= 2 else { return nil }

        var counts: [String: Int] = [:]
        for evening in withCert {
            guard let code = evening.titleSnapshot?.certificationCode else { continue }
            counts[code, default: 0] += 1
        }
        let exceptions = evenings.filter { !$0.exceptions.isEmpty }.count
        let maximum = max(1, counts.values.max() ?? 1)
        let bars = counts.sorted { $0.value > $1.value }.map { entry in
            InsightBar(label: entry.key,
                       fraction: Double(entry.value) / Double(maximum),
                       caption: "\(entry.value) evening\(entry.value == 1 ? "" : "s")",
                       highlighted: entry.value == maximum)
        }

        let headline = exceptions > 0
            ? "You allowed a deliberate exception on \(exceptions) of \(evenings.count) evenings."
            : "Every evening so far stayed inside your own rules."

        return Insight(
            id: "certifications",
            title: "Certifications You Really Follow",
            headline: headline,
            detail: "What was actually watched, by certificate, in \(document.profile.ratingCountry.countryName).",
            bars: bars,
            eveningIds: withCert.map(\.id),
            action: nil
        )
    }

    // MARK: - Sensitivities that faded

    private static func sensitivitiesThatFaded(_ evenings: [Evening], document: AppDocument) -> Insight? {
        var candidates: [(viewer: Viewer, record: SensitivityRecord, clear: Int, ids: [UUID])] = []

        for viewer in document.viewers {
            for record in viewer.activeSensitivities {
                var clear = 0
                var ids: [UUID] = []
                for evening in evenings {
                    guard evening.viewerIds.contains(viewer.id),
                          let titleId = evening.titleId,
                          let title = document.titles.first(where: { $0.id == titleId }),
                          title.contentAspects.contains(record.aspect)
                    else { continue }
                    let reaction = evening.reactions.first { $0.viewerId == viewer.id }
                    let untroubled = (reaction?.gotScared == false) && (reaction?.watchedToEnd == true)
                    if untroubled {
                        clear += 1
                        ids.append(evening.id)
                    }
                }
                if clear >= 2 {
                    candidates.append((viewer, record, clear, ids))
                }
            }
        }
        guard let best = candidates.max(by: { $0.clear < $1.clear }) else { return nil }

        let bars = candidates.sorted { $0.clear > $1.clear }.prefix(5).map { entry in
            InsightBar(label: "\(entry.viewer.name) · \(entry.record.aspect.title)",
                       fraction: min(1, Double(entry.clear) / 4.0),
                       caption: "\(entry.clear) evenings, no trouble",
                       highlighted: entry.record.id == best.record.id)
        }

        return Insight(
            id: "faded",
            title: "Sensitivities That Faded",
            headline: "\(best.viewer.name) has sat through \(best.record.aspect.phrase) \(best.clear) times without trouble.",
            detail: "Children change. When a sensitivity stops firing, take it off the list — the app keeps it in the history either way.",
            bars: Array(bars),
            eveningIds: best.ids,
            action: .markGrownOut(viewerId: best.viewer.id,
                                  sensitivityId: best.record.id,
                                  viewerName: best.viewer.name,
                                  aspect: best.record.aspect)
        )
    }

    // MARK: - Most rewatched

    private static func mostRewatched(_ evenings: [Evening], document: AppDocument) -> Insight? {
        var counts: [UUID: Int] = [:]
        var names: [UUID: String] = [:]
        var ids: [UUID: [UUID]] = [:]

        for evening in evenings {
            guard let titleId = evening.titleId else { continue }
            counts[titleId, default: 0] += 1
            names[titleId] = evening.titleSnapshot?.name ?? "Untitled"
            ids[titleId, default: []].append(evening.id)
        }
        let repeats = counts.filter { $0.value > 1 }
        guard let top = repeats.max(by: { $0.value < $1.value }) else { return nil }

        let maximum = max(1, repeats.values.max() ?? 1)
        let bars = repeats.sorted { $0.value > $1.value }.prefix(5).map { entry in
            InsightBar(label: names[entry.key] ?? "Untitled",
                       fraction: Double(entry.value) / Double(maximum),
                       caption: "\(entry.value) evenings",
                       highlighted: entry.key == top.key)
        }

        return Insight(
            id: "rewatched",
            title: "Most Rewatched",
            headline: "\(names[top.key] ?? "One title") has come round \(top.value) times.",
            detail: "Repeats are not a failure of choice — they are the safest evening you have.",
            bars: Array(bars),
            eveningIds: ids[top.key] ?? [],
            action: document.titles.contains(where: { $0.id == top.key })
                ? .openTitle(titleId: top.key, name: names[top.key] ?? "Title")
                : nil
        )
    }

    // MARK: - Time to choose a film

    private static func timeToChoose(_ evenings: [Evening]) -> Insight? {
        let measured = evenings.compactMap { evening -> (UUID, Int)? in
            guard let started = evening.planningStartedAt else { return nil }
            let seconds = Int(evening.createdAt.timeIntervalSince(started))
            guard seconds > 0, seconds < 60 * 60 * 6 else { return nil }
            return (evening.id, seconds / 60)
        }
        guard measured.count >= 2 else { return nil }

        let average = measured.reduce(0) { $0 + $1.1 } / measured.count
        let maximum = max(1, measured.map(\.1).max() ?? 1)
        let bars = measured.suffix(6).map { entry in
            InsightBar(label: "\(entry.1) min",
                       fraction: Double(entry.1) / Double(maximum),
                       caption: "",
                       highlighted: entry.1 == measured.map(\.1).min())
        }

        return Insight(
            id: "choosing",
            title: "Time to Choose a Film",
            headline: average <= 1
                ? "Choosing takes about a minute here."
                : "Choosing takes about \(average) minutes here.",
            detail: "Measured from opening the evening to creating it. The shorter it gets, the better the app knows your house.",
            bars: Array(bars),
            eveningIds: measured.map(\.0),
            action: nil
        )
    }

    // MARK: - Split evenings

    private static func splitEvenings(_ evenings: [Evening]) -> Insight? {
        let split = evenings.filter { $0.outcome == .splitAcrossEvenings || $0.continuedFromEveningId != nil }
        guard !split.isEmpty else { return nil }

        let finished = split.filter { $0.outcome == .finished || $0.continuedFromEveningId != nil }.count
        return Insight(
            id: "split",
            title: "Split Evenings",
            headline: "\(split.count) film\(split.count == 1 ? " was" : "s were") split over two sittings.",
            detail: finished > 0
                ? "\(finished) of them were picked up and finished on another day."
                : "Splitting is ordinary practice, not a failed evening.",
            bars: [],
            eveningIds: split.map(\.id),
            action: nil
        )
    }
}
