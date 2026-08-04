//  ExportService.swift
//  Screen Nest
//
//  Export the library, the evenings and the content notes as CSV and as a
//  printed PDF. Both are drawn here by hand — no dependency, no template.

import UIKit

enum ExportService {

    // MARK: - CSV

    private static func escape(_ field: String) -> String {
        let cleaned = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(cleaned)\""
    }

    private static func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",") + "\n"
    }

    static func libraryCSV(_ document: AppDocument) -> String {
        let country = document.profile.ratingCountry
        var out = row(["Title", "Original title", "Type", "Runtime (min)", "Year", "Genres",
                       "Certification (\(country.bodyName))", "Where to watch", "Content",
                       "Tags", "Favourite", "Archived", "Watched"])
        for title in document.titles.sorted(by: { $0.name < $1.name }) {
            let watched = document.evenings.filter { $0.titleId == title.id && $0.state == .completed }.count
            out += row([
                title.name,
                title.originalName,
                title.type.title,
                "\(title.runtimeMinutes)",
                title.releaseYear.map(String.init) ?? "",
                title.genres.joined(separator: "; "),
                title.certification(for: country) ?? "",
                title.whereToWatch,
                title.contentAspects.map(\.title).joined(separator: "; "),
                title.personalTags.joined(separator: "; "),
                title.isFavourite ? "yes" : "no",
                title.isArchived ? "yes" : "no",
                "\(watched)"
            ])
        }
        return out
    }

    static func eveningsCSV(_ document: AppDocument) -> String {
        var out = row(["Date", "Evening", "Occasion", "Title", "Runtime (min)", "Certification",
                       "Viewers", "State", "Outcome", "Watched (min)", "Stop reason",
                       "Marks", "Exceptions", "Parent note"])
        let formatter = TimeFormat.shortDayFormatter
        for evening in document.evenings.sorted(by: { $0.date > $1.date }) {
            let viewers = evening.viewerIds
                .compactMap { id in document.viewers.first { $0.id == id }?.name }
                .joined(separator: "; ")
            out += row([
                formatter.string(from: evening.date),
                evening.displayName,
                evening.occasion.title,
                evening.titleSnapshot?.name ?? "",
                "\(evening.plannedRuntimeMinutes)",
                evening.titleSnapshot?.certificationCode ?? "",
                viewers,
                evening.state.title,
                evening.outcome?.title ?? "",
                "\(ScreenTimeEngine.watchedMinutes(evening))",
                evening.watch.stopReason?.title ?? "",
                evening.watch.marks.map { "\($0.timecode) \($0.kind.title)" }.joined(separator: "; "),
                evening.exceptions.map { "\($0.ruleTitle): \($0.reason)" }.joined(separator: "; "),
                evening.parentNote
            ])
        }
        return out
    }

    static func reactionsCSV(_ document: AppDocument) -> String {
        var out = row(["Date", "Title", "Viewer", "Impression", "Watched to end", "Got scared",
                       "Asked questions", "Fell asleep", "Wants again", "Best moment", "Note"])
        let formatter = TimeFormat.shortDayFormatter
        for evening in document.evenings.sorted(by: { $0.date > $1.date }) {
            for reaction in evening.reactions {
                let name = document.viewers.first { $0.id == reaction.viewerId }?.name ?? "Removed viewer"
                out += row([
                    formatter.string(from: evening.date),
                    evening.titleSnapshot?.name ?? evening.displayName,
                    name,
                    reaction.impression?.title ?? "",
                    reaction.watchedToEnd ? "yes" : "no",
                    reaction.gotScared ? "yes" : "no",
                    reaction.askedQuestions ? "yes" : "no",
                    reaction.fellAsleep ? "yes" : "no",
                    reaction.wantsAgain ? "yes" : "no",
                    reaction.bestMoment,
                    reaction.privateNote
                ])
            }
        }
        return out
    }

    static func contentNotesCSV(_ document: AppDocument) -> String {
        var out = row(["Title", "Timestamp", "What happens", "Who reacted", "Severity",
                       "Advice next time", "Warn before watching"])
        for note in document.contentNotes.sorted(by: { $0.titleName < $1.titleName }) {
            let who = note.whoReacted
                .compactMap { id in document.viewers.first { $0.id == id }?.name }
                .joined(separator: "; ")
            out += row([
                note.titleName,
                note.timecode ?? "",
                note.whatHappens,
                who,
                note.severity.title,
                note.adviceNextTime,
                note.warnBeforeWatching ? "yes" : "no"
            ])
        }
        return out
    }

    // MARK: - Files

    private static var exportDirectory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenNestExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func writeCSVBundle(_ document: AppDocument) -> [URL] {
        let stamp = Self.stamp()
        let files: [(String, String)] = [
            ("screen-nest-library-\(stamp).csv", libraryCSV(document)),
            ("screen-nest-evenings-\(stamp).csv", eveningsCSV(document)),
            ("screen-nest-reactions-\(stamp).csv", reactionsCSV(document)),
            ("screen-nest-content-notes-\(stamp).csv", contentNotesCSV(document))
        ]
        return files.compactMap { name, body in
            let url = exportDirectory.appendingPathComponent(name)
            guard let data = body.data(using: .utf8) else { return nil }
            try? data.write(to: url, options: .atomic)
            return url
        }
    }

    static func writeBackup(_ document: AppDocument) -> URL? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(document) else { return nil }
        let url = exportDirectory.appendingPathComponent("screen-nest-backup-\(stamp()).json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    static func readBackup(at url: URL) -> AppDocument? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppDocument.self, from: data)
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - PDF

    static func writePDF(_ document: AppDocument) -> URL? {
        let pageSize = CGSize(width: 595, height: 842) // A4 at 72dpi
        let margin: CGFloat = 44
        let url = exportDirectory.appendingPathComponent("screen-nest-\(stamp()).pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let cream = UIColor(nestHex: 0xFBF4E6)
        let ink = UIColor(nestHex: 0x3A2C12)
        let soft = UIColor(nestHex: 0x6E5C38)
        let amber = UIColor(nestHex: 0xE0982A)

        let titleFont = UIFont(descriptor: UIFont.systemFont(ofSize: 24).fontDescriptor
            .withDesign(.serif) ?? UIFont.systemFont(ofSize: 24).fontDescriptor, size: 24)
        let headFont = UIFont(descriptor: UIFont.systemFont(ofSize: 15, weight: .semibold).fontDescriptor, size: 15)
        let bodyFont = UIFont.systemFont(ofSize: 10.5)
        let labelFont = UIFont.systemFont(ofSize: 8.5, weight: .semibold)

        do {
            try renderer.writePDF(to: url) { context in
                var y: CGFloat = margin
                var pageStarted = false

                func newPage() {
                    context.beginPage()
                    cream.setFill()
                    context.fill(CGRect(origin: .zero, size: pageSize))
                    y = margin
                    pageStarted = true
                }

                func ensure(_ needed: CGFloat) {
                    if !pageStarted || y + needed > pageSize.height - margin { newPage() }
                }

                func ticks(at yPos: CGFloat, width: CGFloat) {
                    let path = UIBezierPath()
                    var x = margin
                    var index = 0
                    while x < margin + width {
                        let h: CGFloat = index % 5 == 0 ? 5 : 3
                        path.move(to: CGPoint(x: x, y: yPos))
                        path.addLine(to: CGPoint(x: x, y: yPos + h))
                        x += 8
                        index += 1
                    }
                    amber.withAlphaComponent(0.55).setStroke()
                    path.lineWidth = 0.8
                    path.stroke()
                }

                func draw(_ text: String, font: UIFont, colour: UIColor, indent: CGFloat = 0, spacing: CGFloat = 4) {
                    let width = pageSize.width - margin * 2 - indent
                    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
                    let bounding = (text as NSString).boundingRect(
                        with: CGSize(width: width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attributes, context: nil)
                    ensure(bounding.height + spacing)
                    (text as NSString).draw(with: CGRect(x: margin + indent, y: y, width: width, height: bounding.height),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                                            attributes: attributes, context: nil)
                    y += bounding.height + spacing
                }

                func sectionHead(_ text: String) {
                    ensure(46)
                    y += 12
                    ticks(at: y, width: 80)
                    y += 10
                    draw(text, font: headFont, colour: ink, spacing: 6)
                }

                newPage()
                ticks(at: y, width: 120)
                y += 14
                draw("Screen Nest", font: titleFont, colour: ink, spacing: 2)
                let house = document.profile.displayName.isEmpty ? "This house" : document.profile.displayName
                draw("\(house) · \(document.profile.ratingCountry.displayName) · exported \(stamp())",
                     font: bodyFont, colour: soft, spacing: 10)

                // Viewers
                sectionHead("Viewers")
                if document.viewers.isEmpty {
                    draw("No viewers recorded.", font: bodyFont, colour: soft)
                }
                for viewer in document.viewers {
                    let age = viewer.age.map { ", \($0)" } ?? ""
                    draw("\(viewer.name) — \(viewer.role.title)\(age)", font: bodyFont, colour: ink, spacing: 2)
                    let sensitivities = viewer.activeSensitivities.map(\.aspect.title)
                    if !sensitivities.isEmpty {
                        draw("Sensitive to: \(sensitivities.joined(separator: ", "))",
                             font: bodyFont, colour: soft, indent: 12, spacing: 2)
                    }
                    let retired = viewer.retiredSensitivities.map(\.aspect.title)
                    if !retired.isEmpty {
                        draw("Grown out of: \(retired.joined(separator: ", "))",
                             font: bodyFont, colour: soft, indent: 12, spacing: 2)
                    }
                    y += 4
                }

                // House rules
                sectionHead("House Rules")
                let rules = document.rules.filter(\.isActive)
                if rules.isEmpty { draw("No rules set.", font: bodyFont, colour: soft) }
                for rule in rules {
                    draw("\(rule.type.title) — \(rule.valueSummary)", font: bodyFont, colour: ink, spacing: 3)
                }

                // Library
                sectionHead("Library (\(document.titles.count))")
                for title in document.titles.sorted(by: { $0.name < $1.name }) {
                    let cert = title.certification(for: document.profile.ratingCountry) ?? "no certificate"
                    draw("\(title.name) · \(title.runtimeMinutes) min · \(cert) · \(title.genres.joined(separator: ", "))",
                         font: bodyFont, colour: ink, spacing: 3)
                }

                // Evenings
                sectionHead("Evenings (\(document.evenings.filter { $0.state == .completed }.count) completed)")
                let formatter = TimeFormat.shortDayFormatter
                for evening in document.evenings.sorted(by: { $0.date > $1.date }) {
                    let viewers = evening.viewerIds
                        .compactMap { id in document.viewers.first { $0.id == id }?.name }
                        .joined(separator: ", ")
                    draw("\(formatter.string(from: evening.date)) — \(evening.titleSnapshot?.name ?? evening.displayName)",
                         font: bodyFont, colour: ink, spacing: 2)
                    draw("\(evening.state.title)\(evening.outcome.map { " · \($0.title)" } ?? "") · \(ScreenTimeEngine.watchedMinutes(evening)) min watched · \(viewers)",
                         font: bodyFont, colour: soft, indent: 12, spacing: 2)
                    for reaction in evening.reactions where reaction.impression != nil {
                        let name = document.viewers.first { $0.id == reaction.viewerId }?.name ?? "Viewer"
                        draw("\(name): \(reaction.impression?.title ?? "")\(reaction.gotScared ? " · got scared" : "")\(reaction.fellAsleep ? " · fell asleep" : "")",
                             font: bodyFont, colour: soft, indent: 24, spacing: 1)
                    }
                    if !evening.parentNote.isEmpty {
                        draw("Parent note: \(evening.parentNote)", font: bodyFont, colour: soft, indent: 24, spacing: 1)
                    }
                    y += 4
                }

                // Content notes
                sectionHead("Content Notes (\(document.contentNotes.count))")
                if document.contentNotes.isEmpty {
                    draw("No content notes recorded.", font: bodyFont, colour: soft)
                }
                for note in document.contentNotes {
                    let stamp = note.timecode.map { "\($0) " } ?? ""
                    draw("\(note.titleName) — \(stamp)\(note.whatHappens)", font: bodyFont, colour: ink, spacing: 2)
                    if !note.adviceNextTime.isEmpty {
                        draw("Next time: \(note.adviceNextTime)", font: bodyFont, colour: soft, indent: 12, spacing: 2)
                    }
                }

                y += 16
                ensure(30)
                draw("Age ratings come from official classification bodies through TMDB. They are a starting point, not a decision. You know your child.",
                     font: labelFont, colour: soft)
                draw(TMDBService.attribution, font: labelFont, colour: soft)
            }
            return url
        } catch {
            return nil
        }
    }
}
