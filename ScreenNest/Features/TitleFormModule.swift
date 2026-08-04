//  TitleFormModule.swift
//  Screen Nest — add / edit a title.
//
//  Title, type, runtime and at least one genre are required, and the error is
//  attached to the field that failed. The save button blocks itself while the
//  write happens, so a fast double tap cannot create two of anything.
//
//  Anything that arrived from the network and was then edited here is marked
//  "Edited by You" and is never overwritten by a later refresh.

import SwiftUI

/// What an online search hands to the form.
struct TitlePrefill {
    var name: String
    var originalName: String
    var type: ContentType
    var runtimeMinutes: Int?
    var genres: [String]
    var releaseYear: Int?
    var certificationCode: String?
    var certificationMissing: Bool
    var shortDescription: String
    var aspects: [ContentAspect]
    var poster: UIImage?
    var tmdbId: Int?
    var seasons: [SeriesSeason]
}

final class TitleFormPresenter: ObservableObject {

    @Published var name: String
    @Published var originalName: String
    @Published var type: ContentType
    @Published var runtime: Int?
    @Published var genres: Set<String>
    @Published var customGenre: String = ""
    @Published var releaseYear: Int?
    @Published var certificationCode: String?
    @Published var shortDescription: String
    @Published var whereToWatch: String
    @Published var aspects: Set<ContentAspect>
    @Published var contentNotesText: String
    @Published var personalTags: [String]
    @Published var tagDraft: String = ""
    @Published var privateNote: String
    @Published var poster: UIImage?
    @Published var posterFileName: String?
    @Published var seasons: [SeriesSeason]

    @Published var attemptedSave = false
    @Published var isSaving = false
    @Published var showPhotoPicker = false
    @Published var confirmingDelete = false
    @Published var savedFlash = false

    let country: RatingCountry
    let certificationMissingFromSource: Bool
    private let original: Title?
    private var fromNetwork: Set<String> = []
    private var editedFields: Set<String>

    init(title: Title?, prefill: TitlePrefill?, country: RatingCountry) {
        self.original = title
        self.country = country
        self.certificationMissingFromSource = prefill?.certificationMissing ?? false

        name = title?.name ?? prefill?.name ?? ""
        originalName = title?.originalName ?? prefill?.originalName ?? ""
        type = title?.type ?? prefill?.type ?? .film
        runtime = title.map { $0.runtimeMinutes > 0 ? $0.runtimeMinutes : nil } ?? prefill?.runtimeMinutes
        genres = Set(title?.genres ?? prefill?.genres ?? [])
        releaseYear = title?.releaseYear ?? prefill?.releaseYear
        certificationCode = title?.certification(for: country) ?? prefill?.certificationCode
        shortDescription = title?.shortDescription ?? prefill?.shortDescription ?? ""
        whereToWatch = title?.whereToWatch ?? ""
        aspects = Set(title?.contentAspects ?? prefill?.aspects ?? [])
        contentNotesText = title?.contentNotesText ?? ""
        personalTags = title?.personalTags ?? []
        privateNote = title?.privateNote ?? ""
        posterFileName = title?.posterFileName
        poster = prefill?.poster
        seasons = title?.seasons ?? prefill?.seasons ?? []
        editedFields = Set(title?.editedFields ?? [])

        if let prefill = prefill {
            var arrived: Set<String> = ["name", "originalName", "type"]
            if prefill.runtimeMinutes != nil { arrived.insert("runtime") }
            if !prefill.genres.isEmpty { arrived.insert("genres") }
            if prefill.releaseYear != nil { arrived.insert("releaseYear") }
            if prefill.certificationCode != nil { arrived.insert("certification") }
            if !prefill.shortDescription.isEmpty { arrived.insert("shortDescription") }
            if !prefill.aspects.isEmpty { arrived.insert("aspects") }
            fromNetwork = arrived
            self.tmdbId = prefill.tmdbId
        } else {
            self.tmdbId = title?.tmdbId
        }
    }

    private var tmdbId: Int?

    var isEditing: Bool { original != nil }
    var title: String { isEditing ? "Edit Title" : "Add by Hand" }

    /// A field that came from the network and has since been changed by hand.
    func isEditedByYou(_ field: String) -> Bool {
        editedFields.contains(field)
    }

    func markEdited(_ field: String) {
        guard fromNetwork.contains(field) || (original?.tmdbId != nil) else { return }
        editedFields.insert(field)
    }

    func cameFromNetwork(_ field: String) -> Bool {
        fromNetwork.contains(field) || (original?.tmdbId != nil && !editedFields.contains(field))
    }

    // MARK: Validation

    var nameError: String? {
        guard attemptedSave else { return nil }
        return name.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter a title to continue." : nil
    }

    var runtimeError: String? {
        guard attemptedSave else { return nil }
        guard let runtime = runtime, runtime > 0 else { return "Runtime must be greater than zero." }
        return runtime > 900 ? "That is longer than fifteen hours — check the number." : nil
    }

    var genreError: String? {
        guard attemptedSave else { return nil }
        return genres.isEmpty ? "Select at least one genre." : nil
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (runtime ?? 0) > 0 && (runtime ?? 0) <= 900
            && !genres.isEmpty
    }

    // MARK: Intents

    func toggleGenre(_ genre: String) {
        if genres.contains(genre) { genres.remove(genre) } else { genres.insert(genre) }
        markEdited("genres")
        NestHaptics.tap()
    }

    func toggleAspect(_ aspect: ContentAspect) {
        if aspects.contains(aspect) { aspects.remove(aspect) } else { aspects.insert(aspect) }
        markEdited("aspects")
        NestHaptics.tap()
    }

    func addCustomGenre() {
        let trimmed = customGenre.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        genres.insert(trimmed)
        customGenre = ""
        markEdited("genres")
    }

    func addTag() {
        let trimmed = tagDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !personalTags.contains(trimmed) else { return }
        personalTags.append(trimmed)
        tagDraft = ""
        NestHaptics.tap()
    }

    var genreOptions: [String] {
        Array(Set(GenreCatalogue.all).union(genres)).sorted()
    }

    /// A throwaway title used to draw the live cover preview. Writes nothing.
    var previewTitle: Title {
        var result = Title()
        result.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : name
        result.runtimeMinutes = runtime ?? 0
        result.genres = genres.sorted()
        return result
    }

    func build() -> Title {
        var result = original ?? Title()
        result.name = name.trimmingCharacters(in: .whitespaces)
        result.originalName = originalName.trimmingCharacters(in: .whitespaces)
        result.type = type
        result.runtimeMinutes = runtime ?? 0
        result.genres = genres.sorted()
        result.releaseYear = releaseYear
        if let code = certificationCode, !code.isEmpty {
            result.certifications[country.rawValue] = code
        } else {
            result.certifications.removeValue(forKey: country.rawValue)
        }
        result.shortDescription = shortDescription
        result.whereToWatch = whereToWatch.trimmingCharacters(in: .whitespaces)
        result.contentAspects = aspects.sorted { $0.rawValue < $1.rawValue }
        result.contentNotesText = contentNotesText
        result.personalTags = personalTags
        result.privateNote = privateNote
        result.tmdbId = tmdbId
        result.editedFields = Array(editedFields)
        result.seasons = seasons
        if type.isEpisodic && result.seriesPosition == nil {
            result.seriesPosition = SeriesPosition()
        }

        if let image = poster {
            result.posterFileName = PosterStore.shared.save(image, replacing: original?.posterFileName)
        } else {
            result.posterFileName = posterFileName
        }
        return result
    }
}

// MARK: - View

struct TitleFormView: View {
    @EnvironmentObject private var store: DataStore
    @StateObject private var presenter: TitleFormPresenter

    let onSave: (Title) -> Void
    let onCancel: () -> Void
    let onDelete: (UUID) -> Void

    private let titleId: UUID?
    private let allowDelete: Bool

    init(title: Title?,
         prefill: TitlePrefill?,
         country: RatingCountry = DataStore.shared.profile.ratingCountry,
         onSave: @escaping (Title) -> Void,
         onCancel: @escaping () -> Void,
         onDelete: @escaping (UUID) -> Void) {
        _presenter = StateObject(wrappedValue: TitleFormPresenter(title: title, prefill: prefill, country: country))
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.titleId = title?.id
        self.allowDelete = title != nil
    }

    var body: some View {
        SheetScaffold(title: presenter.title,
                      subtitle: "Title, type, running time and one genre are needed.",
                      closeTitle: "Cancel",
                      onClose: onCancel) {

            FieldShell(label: "Title", error: presenter.nameError, required: true) {
                VStack(alignment: .leading, spacing: 4) {
                    NestTextField(placeholder: "Title", text: Binding(
                        get: { presenter.name },
                        set: { presenter.name = $0; presenter.markEdited("name") }
                    ), invalid: presenter.nameError != nil)
                    editedBadge("name")
                }
            }

            FieldShell(label: "Original Title", hint: "If it differs from the name you use at home.") {
                NestTextField(placeholder: "Original title", text: Binding(
                    get: { presenter.originalName },
                    set: { presenter.originalName = $0; presenter.markEdited("originalName") }
                ))
            }

            FieldShell(label: "Content Type", required: true) {
                NestSegmented(options: ContentType.allCases,
                              selection: Binding(
                                get: { presenter.type },
                                set: { presenter.type = $0; presenter.markEdited("type") }
                              ),
                              titleFor: { $0.title })
            }

            FieldShell(label: presenter.type.isEpisodic ? "Episode Runtime" : "Runtime",
                       hint: presenter.type.isEpisodic ? "One episode, in minutes." : nil,
                       error: presenter.runtimeError,
                       required: true) {
                VStack(alignment: .leading, spacing: 4) {
                    NestNumberField(placeholder: "Minutes",
                                    value: Binding(
                                        get: { presenter.runtime },
                                        set: { presenter.runtime = $0; presenter.markEdited("runtime") }
                                    ),
                                    suffix: "minutes",
                                    invalid: presenter.runtimeError != nil)
                    editedBadge("runtime")
                }
            }

            FieldShell(label: "Genres", error: presenter.genreError, required: true) {
                VStack(alignment: .leading, spacing: NestSpace.s) {
                    ChipFlow(items: presenter.genreOptions) { genre in
                        NestChip(title: genre, selected: presenter.genres.contains(genre)) {
                            presenter.toggleGenre(genre)
                        }
                    }
                    HStack(spacing: NestSpace.s) {
                        NestTextField(placeholder: "Add your own genre", text: $presenter.customGenre)
                        Button("Add") { presenter.addCustomGenre() }
                            .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
                    }
                    editedBadge("genres")
                }
            }

            FieldShell(label: "Release Year") {
                NestNumberField(placeholder: "Year",
                                value: Binding(
                                    get: { presenter.releaseYear },
                                    set: { presenter.releaseYear = $0; presenter.markEdited("releaseYear") }
                                ),
                                suffix: "")
            }

            certificationField

            FieldShell(label: "Short Description") {
                VStack(alignment: .leading, spacing: 4) {
                    NestTextArea(placeholder: "What it is about, in a line or two.",
                                 text: Binding(
                                    get: { presenter.shortDescription },
                                    set: { presenter.shortDescription = $0; presenter.markEdited("shortDescription") }
                                 ),
                                 minHeight: 76)
                    editedBadge("shortDescription")
                }
            }

            FieldShell(label: "Where to Watch", hint: "A shelf, a disc, a service — whatever is true for you.") {
                NestTextField(placeholder: "e.g. DVD shelf, streaming service", text: $presenter.whereToWatch)
            }

            posterField

            FieldShell(label: "Content Notes",
                       hint: "What is actually in it. This is what the check compares against each viewer's sensitivities.") {
                VStack(alignment: .leading, spacing: NestSpace.s) {
                    ChipFlow(items: ContentAspect.contentOptions) { aspect in
                        NestChip(title: aspect.title,
                                 selected: presenter.aspects.contains(aspect),
                                 tint: NestColor.amber,
                                 glyph: aspect) {
                            presenter.toggleAspect(aspect)
                        }
                    }
                    NestTextArea(placeholder: "Anything else worth knowing before it starts.",
                                 text: $presenter.contentNotesText, minHeight: 66)
                    editedBadge("aspects")
                }
            }

            FieldShell(label: "Personal Tags") {
                VStack(alignment: .leading, spacing: NestSpace.s) {
                    HStack(spacing: NestSpace.s) {
                        NestTextField(placeholder: "e.g. dinosaurs, rainy Sunday", text: $presenter.tagDraft)
                        Button("Add") { presenter.addTag() }
                            .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
                    }
                    if !presenter.personalTags.isEmpty {
                        ChipFlow(items: presenter.personalTags) { tag in
                            NestChip(title: tag, selected: true, tint: NestColor.plum) {
                                presenter.personalTags.removeAll { $0 == tag }
                            }
                        }
                    }
                }
            }

            FieldShell(label: "Private Note", hint: "Only you see this.") {
                NestTextArea(placeholder: "Private note", text: $presenter.privateNote, minHeight: 66)
            }

            VStack(spacing: NestSpace.m) {
                PrimaryButton(title: presenter.isEditing ? "Save Changes" : "Save Title",
                              busyTitle: "Saving…",
                              busy: presenter.isSaving) {
                    save()
                }

                if allowDelete, let id = titleId {
                    Button("Delete Title") {
                        NestHaptics.tap()
                        presenter.confirmingDelete = true
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: NestColor.stop))
                    .alert("Delete this title?", isPresented: $presenter.confirmingDelete) {
                        Button("Cancel", role: .cancel) {}
                        Button("Delete", role: .destructive) { onDelete(id) }
                    } message: {
                        Text("Finished evenings keep a snapshot of the name, running time and certificate, so your history stays intact. Content notes for this title are removed.")
                    }
                }
            }
            .padding(.top, NestSpace.s)
        }
        .sheet(isPresented: $presenter.showPhotoPicker) {
            PhotoPicker { image in
                presenter.poster = image
            }
        }
    }

    private func save() {
        presenter.attemptedSave = true
        guard presenter.isValid else {
            NestHaptics.warning()
            return
        }
        guard !presenter.isSaving else { return }
        presenter.isSaving = true
        NestHaptics.success()
        onSave(presenter.build())
    }

    @ViewBuilder
    private func editedBadge(_ field: String) -> some View {
        if presenter.isEditedByYou(field) {
            nestTracked("edited by you", kern: 0.8)
                .font(NestFont.label)
                .foregroundColor(NestColor.plum)
        }
    }

    private var certificationField: some View {
        FieldShell(label: "Certification",
                   hint: "\(presenter.country.displayName). The app never substitutes another country's rating.") {
            VStack(alignment: .leading, spacing: NestSpace.s) {
                ChipFlow(items: presenter.country.certifications.map(\.code)) { code in
                    NestChip(title: code, selected: presenter.certificationCode == code) {
                        presenter.certificationCode = presenter.certificationCode == code ? nil : code
                        presenter.markEdited("certification")
                    }
                }
                if let code = presenter.certificationCode,
                   let cert = presenter.country.certification(code: code) {
                    Text(cert.note)
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else if presenter.certificationMissingFromSource {
                    Text("No certification for your country. Decide for yourself, or add a content note.")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.amberSunk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                editedBadge("certification")
            }
        }
    }

    private var posterField: some View {
        FieldShell(label: "Poster",
                   hint: "From the search result, from your photos, or the drawn cover the app makes from the title's own genre and running time.") {
            HStack(alignment: .top, spacing: NestSpace.m) {
                Group {
                    if let image = presenter.poster {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if let existing = PosterStore.shared.image(named: presenter.posterFileName) {
                        Image(uiImage: existing)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        PosterArtwork(title: presenter.previewTitle)
                    }
                }
                .frame(width: 82, height: 123)
                .clipShape(PosterShape())
                .overlay(PosterShape().stroke(NestColor.hairline, lineWidth: NestStroke.hair))

                VStack(alignment: .leading, spacing: NestSpace.s) {
                    Button("Choose from Photos") {
                        NestHaptics.tap()
                        presenter.showPhotoPicker = true
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    if presenter.poster != nil || presenter.posterFileName != nil {
                        Button("Use the Drawn Cover") {
                            NestHaptics.tap()
                            PosterStore.shared.remove(named: presenter.posterFileName)
                            presenter.poster = nil
                            presenter.posterFileName = nil
                        }
                        .buttonStyle(QuietButtonStyle(tint: NestColor.stop))
                    }
                }
            }
        }
    }
}
