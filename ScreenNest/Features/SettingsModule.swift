//  SettingsModule.swift
//  Screen Nest — Settings and data management.
//
//  Every control here has a real, immediate, visible effect. Destructive
//  actions confirm; deleting everything confirms twice.

import SwiftUI

final class SettingsPresenter: ObservableObject {
    @Published var showBedtimes = false

    @Published var confirmingClearHistory = false
    @Published var confirmingDeleteAll = false
    @Published var confirmingDeleteAllSecond = false
    @Published var showImporter = false
    @Published var shareItems: [Any] = []
    @Published var showShare = false
    @Published var toast: NestToast?

    private let store: DataStore
    init(store: DataStore) { self.store = store }

    var profile: HouseProfile { store.profile }
    var counts: (titles: Int, viewers: Int, evenings: Int, notes: Int) {
        (store.titles.count, store.viewers.count, store.evenings.count, store.contentNotes.count)
    }

    func exportCSV() {
        let urls = ExportService.writeCSVBundle(store.document)
        guard !urls.isEmpty else {
            show(NestToast(message: "Nothing could be written", isError: true))
            return
        }
        shareItems = urls
        showShare = true
    }

    func exportPDF() {
        guard let url = ExportService.writePDF(store.document) else {
            show(NestToast(message: "The PDF could not be made", isError: true))
            return
        }
        shareItems = [url]
        showShare = true
    }

    func exportBackup() {
        guard let url = ExportService.writeBackup(store.document) else {
            show(NestToast(message: "The backup could not be made", isError: true))
            return
        }
        shareItems = [url]
        showShare = true
    }

    func importBackup(url: URL) {
        guard let document = ExportService.readBackup(at: url) else {
            show(NestToast(message: "That file could not be read", isError: true))
            return
        }
        store.replaceDocument(document)
        NotificationService.shared.reschedule(for: store.document)
        NestHaptics.success()
        show(NestToast(message: "Backup imported"))
    }

    func clearHistory() {
        store.clearHistory()
        NotificationService.shared.reschedule(for: store.document)
        NestHaptics.warning()
        show(NestToast(message: "History cleared"))
    }

    func deleteEverything() {
        store.deleteAllData()
        TMDBService.shared.clearCache()
        NotificationService.shared.cancelAll()
        UserDefaults.standard.set(false, forKey: NestDefaults.hasOnboarded)
        NestHaptics.warning()
        show(NestToast(message: "All app data deleted"))
    }

    func show(_ toast: NestToast) {
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            if self?.toast == toast { self?.toast = nil }
        }
    }
}

struct SettingsView: View {
    let onClose: () -> Void

    @EnvironmentObject private var store: DataStore
    @StateObject private var presenter = SettingsPresenter(store: .shared)

    @AppStorage(NestDefaults.theme) private var themeRaw: String = NestTheme.system.rawValue
    @AppStorage(NestDefaults.density) private var densityRaw: String = NestDensity.cosy.rawValue
    @AppStorage(NestDefaults.showPosters) private var showPosters: Bool = true

    var body: some View {
        NavigationView {
            ZStack {
                SheetScaffold(title: "Settings",
                              subtitle: "Everything here changes the app immediately.",
                              closeTitle: "Done",
                              onClose: onClose) {

                    profileSection
                    householdSection
                    appearanceSection
                    notificationsSection
                    externalDataSection
                    dataSection
                    aboutSection
                }
                ToastOverlay(toast: presenter.toast)
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $presenter.showShare) {
            ShareSheet(items: presenter.shareItems)
        }
        .sheet(isPresented: $presenter.showImporter) {
            DocumentPicker { url in presenter.importBackup(url: url) }
        }
    }

    // MARK: Profile

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Profile")
            NestCard {
                VStack(alignment: .leading, spacing: NestSpace.l) {
                    FieldShell(label: "Your Display Name") {
                        NestTextField(placeholder: "e.g. Mum, Dad, Grandad",
                                      text: Binding(
                                        get: { store.profile.displayName },
                                        set: { name in store.updateProfile { $0.displayName = name } }
                                      ))
                    }

                    FieldShell(label: "Rating Country",
                               hint: "Certificates are read for this country only. Changing it does not recalculate evenings that are already finished.") {
                        NestOptionList(options: RatingCountry.allCases,
                                       selection: Binding(
                                        get: { store.profile.ratingCountry },
                                        set: { country in
                                            store.updateProfile { $0.ratingCountry = country }
                                            presenter.show(NestToast(message: "Now using \(country.bodyName)"))
                                        }
                                       ),
                                       titleFor: { $0.displayName },
                                       detailFor: { $0.certifications.map(\.code).joined(separator: " · ") })
                    }
                }
            }
        }
    }

    // MARK: Household

    private var householdSection: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Household")
            NestRowGroup {
                NavigationLink(destination: ViewersSettingsList()) {
                    SettingsRow(icon: .content, title: "Viewers",
                                subtitle: "\(presenter.counts.viewers) in this house")
                }
                .buttonStyle(.plain)
                RowDivider()
                NavigationLink(destination: HouseRulesView()) {
                    SettingsRow(icon: .rule, title: "House Rules",
                                subtitle: "\(store.activeRules.count) active")
                }
                .buttonStyle(.plain)
                RowDivider()
                NavigationLink(destination: ScreenTimeView()) {
                    SettingsRow(icon: .screenTime, title: "Screen Time Limits",
                                subtitle: "Weekly minutes per child")
                }
                .buttonStyle(.plain)
                RowDivider()
                NestRow(title: "Bedtimes",
                        subtitle: "Weeknights \(store.profile.weeknightBedtime.display) · weekends \(store.profile.weekendBedtime.display)",
                        trailing: { Chevron() },
                        action: { presenter.showBedtimes.toggle() })
            }

            if presenter.showBedtimes {
                NestCard {
                    VStack(alignment: .leading, spacing: NestSpace.l) {
                        FieldShell(label: "Weeknight Bedtime") {
                            NestTimeField(time: Binding(
                                get: { store.profile.weeknightBedtime },
                                set: { time in store.updateProfile { $0.weeknightBedtime = time } }
                            ))
                        }
                        FieldShell(label: "Weekend Bedtime") {
                            NestTimeField(time: Binding(
                                get: { store.profile.weekendBedtime },
                                set: { time in store.updateProfile { $0.weekendBedtime = time } }
                            ), presets: [TimeOfDay(hour: 20, minute: 30),
                                         TimeOfDay(hour: 21, minute: 0),
                                         TimeOfDay(hour: 21, minute: 30),
                                         TimeOfDay(hour: 22, minute: 0)])
                        }
                        FieldShell(label: "Settling Time",
                                   hint: "Subtracted from every evening window by default.") {
                            NestSlider(value: Binding(
                                get: { store.profile.defaultSettlingMinutes },
                                set: { value in store.updateProfile { $0.defaultSettlingMinutes = value } }
                            ), range: 0...90, step: 5, suffix: "min")
                        }
                        FieldShell(label: "Expected Pauses") {
                            HStack(spacing: NestSpace.m) {
                                VStack(alignment: .leading, spacing: 4) {
                                    SectionLabel("how many")
                                    NestStepper(value: Binding(
                                        get: { store.profile.defaultPauseCount },
                                        set: { value in store.updateProfile { $0.defaultPauseCount = value } }
                                    ), range: 0...6, step: 1, suffix: "×")
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    SectionLabel("each")
                                    NestStepper(value: Binding(
                                        get: { store.profile.defaultPauseLengthMinutes },
                                        set: { value in store.updateProfile { $0.defaultPauseLengthMinutes = value } }
                                    ), range: 0...30, step: 5, suffix: "min")
                                }
                            }
                        }
                        FieldShell(label: "Buffer") {
                            NestSlider(value: Binding(
                                get: { store.profile.defaultBufferMinutes },
                                set: { value in store.updateProfile { $0.defaultBufferMinutes = value } }
                            ), range: 0...30, step: 5, suffix: "min")
                        }
                    }
                }
            }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Appearance")
            NestCard {
                VStack(alignment: .leading, spacing: NestSpace.l) {
                    FieldShell(label: "Theme", hint: "Lamplight is a warm room with the big light off — never a black cinema.") {
                        NestSegmented(options: NestTheme.allCases,
                                      selection: Binding(
                                        get: { NestTheme(rawValue: themeRaw) ?? .system },
                                        set: { themeRaw = $0.rawValue }
                                      ),
                                      titleFor: { $0.title })
                    }
                    FieldShell(label: "Density", hint: "Compact tightens the vertical rhythm across every screen.") {
                        NestSegmented(options: NestDensity.allCases,
                                      selection: Binding(
                                        get: { NestDensity(rawValue: densityRaw) ?? .cosy },
                                        set: { densityRaw = $0.rawValue }
                                      ),
                                      titleFor: { $0.title })
                    }
                    NestToggleRow(title: "Show Poster Images",
                                  subtitle: "Off: every title uses the drawn cover made from its own genre and running time.",
                                  isOn: $showPosters)
                }
            }
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Notifications")
            NotificationSettingsCard()
        }
    }

    // MARK: External data

    private var externalDataSection: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("External Data")
            ExternalDataCard { message in presenter.show(NestToast(message: message)) }
        }
    }

    // MARK: Data management

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Data",
                        subtitle: "\(presenter.counts.titles) titles · \(presenter.counts.evenings) evenings · \(presenter.counts.notes) content notes")

            NestRowGroup {
                NestRow(title: "Export Data (CSV)",
                        subtitle: "Library, evenings, reactions and content notes",
                        trailing: { Chevron() },
                        action: { presenter.exportCSV() })
                RowDivider()
                NestRow(title: "Export Data (PDF)",
                        subtitle: "A printed record of the house",
                        trailing: { Chevron() },
                        action: { presenter.exportPDF() })
                RowDivider()
                NestRow(title: "Export Backup",
                        subtitle: "Everything, as one file you can import again",
                        trailing: { Chevron() },
                        action: { presenter.exportBackup() })
                RowDivider()
                NestRow(title: "Import Backup",
                        subtitle: "Replaces everything currently in the app",
                        trailing: { Chevron() },
                        action: { presenter.showImporter = true })
            }

            NestRowGroup {
                NestRow(title: "Clear History",
                        subtitle: "Removes completed evenings. Library, viewers and rules stay.",
                        tint: NestColor.stop,
                        trailing: { Chevron() },
                        action: { presenter.confirmingClearHistory = true })
                RowDivider()
                NestRow(title: "Delete All App Data",
                        subtitle: "Everything, permanently",
                        tint: NestColor.stop,
                        trailing: { Chevron() },
                        action: { presenter.confirmingDeleteAll = true })
            }
            .alert("Clear the evening history?", isPresented: $presenter.confirmingClearHistory) {
                Button("Cancel", role: .cancel) {}
                Button("Clear History", role: .destructive) { presenter.clearHistory() }
            } message: {
                Text("Completed evenings and their reactions are removed. Insights will start again from nothing.")
            }
            .alert("Delete all app data?", isPresented: $presenter.confirmingDeleteAll) {
                Button("Cancel", role: .cancel) {}
                Button("Continue", role: .destructive) {
                    presenter.confirmingDeleteAllSecond = true
                }
            } message: {
                Text("Viewers, rules, the library, every evening, every content note and every poster.")
            }
            .alert("This cannot be undone", isPresented: $presenter.confirmingDeleteAllSecond) {
                Button("Keep My Data", role: .cancel) {}
                Button("Delete Everything", role: .destructive) { presenter.deleteEverything() }
            } message: {
                Text("There is no copy on a server, because nothing was ever sent to one. Export a backup first if you want to keep any of it.")
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("About")
            NestCard {
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    HStack(spacing: NestSpace.m) {
                        NestMark(size: 34, tint: NestColor.amber, seat: 1, lineWidth: 1.6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Screen Nest")
                                .font(NestFont.titleTight)
                                .foregroundColor(NestColor.ink)
                            Text("Version 1.0 · everything stored on this device")
                                .font(NestFont.small)
                                .foregroundColor(NestColor.inkFaint)
                        }
                    }

                    TickRule()

                    Text("Age ratings come from official classification bodies through TMDB. They are a starting point, not a decision. You know your child.")
                        .font(NestFont.quote)
                        .foregroundColor(NestColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: NestSpace.s) {
                        TMDBMark()
                        Text(TMDBService.attribution)
                            .font(NestFont.micro)
                            .foregroundColor(NestColor.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Screen Nest never reproduces film content, never links to anywhere to watch, and is not a substitute for a viewing service.")
                        .font(NestFont.micro)
                        .foregroundColor(NestColor.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Viewers list inside Settings

struct ViewersSettingsList: View {
    @EnvironmentObject private var store: DataStore
    @State private var editing: Viewer?
    @State private var showForm = false

    var body: some View {
        NestScreen(bottomInset: NestSpace.huge) {
            PageTitle(title: "Viewers", subtitle: "Tap anyone to edit their details and sensitivities.")

            if store.viewers.isEmpty {
                NestCard {
                    EmptyStateView(title: "Nobody Here Yet",
                                   message: "Add the people who actually watch.",
                                   primaryTitle: "Add Viewer",
                                   primaryAction: { editing = nil; showForm = true })
                }
            } else {
                ForEach(store.viewers) { viewer in
                    Button {
                        NestHaptics.tap()
                        editing = viewer
                        showForm = true
                    } label: {
                        NestCard(padding: NestSpace.m) {
                            HStack(spacing: NestSpace.m) {
                                ViewerToken(viewer: viewer, size: 38)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(viewer.name)
                                        .font(NestFont.bodyMedium)
                                        .foregroundColor(NestColor.ink)
                                    Text("\(viewer.role.title)\(viewer.age.map { " · \($0)" } ?? "") · \(viewer.activeSensitivities.count) sensitivities")
                                        .font(NestFont.small)
                                        .foregroundColor(NestColor.inkSoft)
                                }
                                Spacer()
                                Chevron()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button("Add Viewer") {
                    editing = nil
                    showForm = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showForm, onDismiss: { editing = nil }) {
            ViewerFormView(viewer: editing,
                           existingCount: store.viewers.count,
                           allowDelete: editing != nil,
                           onSave: { viewer in
                store.upsertViewer(viewer)
                showForm = false
            }, onDelete: { id in
                store.deleteViewer(id: id)
                showForm = false
            }, onCancel: {
                showForm = false
            })
        }
    }
}

// MARK: - Notifications card

struct NotificationSettingsCard: View {
    @EnvironmentObject private var store: DataStore
    @ObservedObject private var service = NotificationService.shared
    @State private var enabled: [String: Bool] = [:]
    @State private var showDeniedNotice = false

    var body: some View {
        NestCard {
            VStack(alignment: .leading, spacing: NestSpace.l) {
                if !service.isAuthorised {
                    VStack(alignment: .leading, spacing: NestSpace.m) {
                        Text("Reminders are off")
                            .font(NestFont.titleTight)
                            .foregroundColor(NestColor.ink)
                        Text("Four reminders, and nothing else: an evening about to start, reactions still unrecorded, a film left part-watched, and the week resetting. Nothing is scheduled until you say yes.")
                            .font(NestFont.small)
                            .foregroundColor(NestColor.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        PrimaryButton(title: "Turn On Reminders") {
                            service.requestAuthorisation { granted in
                                if granted {
                                    service.reschedule(for: store.document)
                                } else {
                                    showDeniedNotice = true
                                }
                            }
                        }
                        if showDeniedNotice {
                            Button("Open iOS Settings") { SystemSettings.open() }
                                .buttonStyle(SecondaryButtonStyle())
                            Text("Notifications are switched off for Screen Nest in iOS Settings.")
                                .font(NestFont.small)
                                .foregroundColor(NestColor.stop)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ForEach(Array(NestReminder.allCases.enumerated()), id: \.element.id) { index, reminder in
                        NestToggleRow(title: reminder.title,
                                      subtitle: reminder.explanation,
                                      isOn: Binding(
                                        get: { enabled[reminder.rawValue] ?? service.isEnabled(reminder) },
                                        set: { value in
                                            enabled[reminder.rawValue] = value
                                            service.setEnabled(reminder, value, document: store.document)
                                        }
                                      ))
                        if index < NestReminder.allCases.count - 1 { RowDivider() }
                    }
                }
            }
        }
        .onAppear {
            service.refreshAuthorisation()
            for reminder in NestReminder.allCases {
                enabled[reminder.rawValue] = service.isEnabled(reminder)
            }
        }
    }
}

// MARK: - External data card

struct ExternalDataCard: View {
    let notify: (String) -> Void

    @EnvironmentObject private var store: DataStore
    @ObservedObject private var monitor = NetworkMonitor.shared
    @AppStorage(NestDefaults.tmdbEnabled) private var enabled: Bool = true
    @State private var cacheDescription: String = ""

    var body: some View {
        NestCard {
            VStack(alignment: .leading, spacing: NestSpace.l) {
                Text("Screen Nest works entirely by hand. The network is used only to save you typing — and only when you press Search.")
                    .font(NestFont.body)
                    .foregroundColor(NestColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: NestSpace.s) {
                    SectionLabel("what is requested")
                    ForEach(["A title search you typed",
                             "Running time, year, genres and a short description",
                             "The age certificate for your country only",
                             "Content keywords",
                             "A poster image",
                             "Seasons and episodes for a series"], id: \.self) { line in
                        HStack(alignment: .top, spacing: NestSpace.s) {
                            Circle().fill(NestColor.amber).frame(width: 4, height: 4).padding(.top, 7)
                            Text(line)
                                .font(NestFont.small)
                                .foregroundColor(NestColor.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                NestToggleRow(title: "Allow Online Search",
                              subtitle: "Off: the app never touches the network at all — not even the cache is consulted.",
                              isOn: $enabled)

                HStack(spacing: NestSpace.s) {
                    Circle()
                        .fill(searchAvailable ? NestColor.go : NestColor.inkFaint)
                        .frame(width: 7, height: 7)
                    Text(searchStatus)
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("local cache")
                        Text(cacheDescription.isEmpty ? "Empty" : cacheDescription)
                            .font(NestFont.small)
                            .foregroundColor(NestColor.inkSoft)
                    }
                    Spacer()
                    Button("Clear Cache") {
                        NestHaptics.tap()
                        TMDBService.shared.clearCache()
                        cacheDescription = TMDBService.shared.cacheSizeDescription
                        notify("Cache cleared")
                    }
                    .buttonStyle(QuietButtonStyle(tint: NestColor.stop))
                }

                HStack(spacing: NestSpace.s) {
                    Circle()
                        .fill(monitor.isOnline ? NestColor.go : NestColor.inkFaint)
                        .frame(width: 7, height: 7)
                    Text(monitor.isOnline
                         ? "Online. Cached results are still used first where they exist."
                         : "Offline. You can add titles by hand, plan the evening and watch — only online search is unavailable.")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TickRule()

                HStack(spacing: NestSpace.s) {
                    TMDBMark()
                    Text(TMDBService.attribution)
                        .font(NestFont.micro)
                        .foregroundColor(NestColor.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("If a title has no certificate for your country, the field stays empty and says so. The app never substitutes another country's rating.")
                    .font(NestFont.micro)
                    .foregroundColor(NestColor.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { cacheDescription = TMDBService.shared.cacheSizeDescription }
    }

    private var searchAvailable: Bool { enabled && TMDBService.shared.hasKey }

    private var searchStatus: String {
        if !TMDBService.shared.hasKey {
            return "Online search is not available in this build. Titles are added by hand, which is the way the app is designed to work anyway."
        }
        return enabled
            ? "Online search is available. Nothing is requested until you press Search."
            : "Online search is off. Titles are added by hand."
    }
}


/// A settings row with its icon in an amber tile.
struct SettingsRow: View {
    let icon: ReasonSymbol
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: NestSpace.m) {
            IconTile(symbol: icon)
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
            Chevron()
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}
