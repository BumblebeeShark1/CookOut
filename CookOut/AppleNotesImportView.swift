import SwiftUI

struct AppleNotesImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cookOutPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    let folders: [RecipeFolder]
    let onImport: (CookingNote) -> Void

    @State private var sources: [AppleNoteSource] = []
    @State private var selectedSource: AppleNoteSource?
    @State private var search = ""
    @State private var isLoadingNotes = false
    @State private var isOrganizing = false
    @State private var proposal: RecipeCreateProposal?
    @State private var destinationFolderID: UUID?
    @State private var errorMessage: String?
    @State private var hasKey = GroqKeychain.load() != nil
    @State private var keyInput = ""
    @AppStorage("cookout.groqModel") private var selectedModelRaw = GroqModel.gptOSS120B.rawValue

    private let notesService = AppleNotesService()
    private let groqService = GroqChatService()

    var body: some View {
        NavigationStack {
            Group {
                if !hasKey {
                    keySetup
                } else if let proposal {
                    recipePreview(proposal)
                } else {
                    sourcePicker
                }
            }
            .background {
                ZStack { palette.background(for: colorScheme); palette.ambientGradient(for: colorScheme) }
                    .ignoresSafeArea()
            }
            .navigationTitle(proposal == nil ? "Import from Apple Notes" : "Review Imported Recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(proposal == nil ? "Cancel" : "Back") {
                        if proposal == nil { dismiss() }
                        else { self.proposal = nil }
                    }
                }
            }
            .alert("Import failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
        .tint(palette.accent)
        .cookOutImportFrame()
    }

    private var keySetup: some View {
        VStack(spacing: 20) {
            Image(systemName: "note.text.badge.plus")
                .font(.system(size: 54))
                .foregroundStyle(palette.gradient)
            Text("Connect CookAssistant to organize your note")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("CookAssistant turns the note into a recipe with ingredients, directions, timing, tags, and the best matching folder.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
            SecureField("Groq API key (gsk_…)", text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 440)
            Button("Save Key and Continue", systemImage: "key.fill") {
                saveKey()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isValidKey)
            Text("Your key stays in CookOut’s private local storage.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }

    @ViewBuilder private var sourcePicker: some View {
#if os(macOS)
        VStack(spacing: 0) {
            if sources.isEmpty {
                ContentUnavailableView {
                    Label("Choose a recipe note", systemImage: "note.text")
                } description: {
                    Text("CookOut will ask macOS for permission to read Apple Notes, then CookAssistant will organize the note you select.")
                } actions: {
                    Button("Load Apple Notes", systemImage: "square.and.arrow.down") { loadAppleNotes() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    if isLoadingNotes { ProgressView("Reading notes…") }
                }
            } else {
                List(filteredSources, selection: Binding(get: { selectedSource?.id }, set: { id in selectedSource = sources.first { $0.id == id } })) { source in
                    Button { selectedSource = source } label: {
                        HStack(spacing: 14) {
                            Image(systemName: selectedSource?.id == source.id ? "checkmark.circle.fill" : "note.text")
                                .font(.title2)
                                .foregroundStyle(selectedSource?.id == source.id ? palette.accent : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                                Text(source.text.replacingOccurrences(of: "\n", with: " "))
                                    .font(.body).foregroundStyle(.secondary).lineLimit(2)
                                Label(source.folderName, systemImage: "folder")
                                    .font(.footnote).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }
                .searchable(text: $search, prompt: "Search Apple Notes")
                importBar
            }
        }
#else
        VStack(spacing: 22) {
            ContentUnavailableView {
                Label(selectedSource == nil ? "Copy a recipe from Notes" : "Recipe note ready", systemImage: selectedSource == nil ? "doc.on.clipboard" : "checkmark.circle.fill")
            } description: {
                Text(selectedSource == nil ? "In Apple Notes, select and copy the recipe text. Then return here and paste it for CookAssistant to organize." : (selectedSource?.title ?? "Apple Notes Recipe"))
            } actions: {
                Button("Paste from Apple Notes", systemImage: "doc.on.clipboard.fill") { pasteAppleNote() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            if let selectedSource {
                Text(selectedSource.text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(10)
                    .padding()
                    .frame(maxWidth: 620, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                importButton
            }
        }
        .padding(28)
#endif
    }

#if os(macOS)
    private var filteredSources: [AppleNoteSource] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return sources }
        return sources.filter {
            $0.title.localizedCaseInsensitiveContains(term) ||
            $0.text.localizedCaseInsensitiveContains(term) ||
            $0.folderName.localizedCaseInsensitiveContains(term)
        }
    }

    private var importBar: some View {
        HStack {
            Text(selectedSource.map { "Selected: \($0.title)" } ?? "Select one note")
                .font(.body.weight(.medium))
                .foregroundStyle(selectedSource == nil ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            Button("Reload", systemImage: "arrow.clockwise") { loadAppleNotes() }
                .buttonStyle(.bordered)
            importButton
        }
        .padding()
        .background(.regularMaterial)
    }
#endif

    private var importButton: some View {
        Button {
            organizeSelectedNote()
        } label: {
            HStack(spacing: 9) {
                if isOrganizing { ProgressView().controlSize(.small) }
                Label(isOrganizing ? "Organizing…" : "Organize with CookAssistant", systemImage: "sparkles")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(selectedSource == nil || isOrganizing)
    }

    private func recipePreview(_ proposal: RecipeCreateProposal) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("CookAssistant organized your note", systemImage: "checkmark.seal.fill")
                    .font(.title2.bold())
                    .foregroundStyle(CookOutTheme.mint)
                Text(proposal.summary).font(.body).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Text(proposal.title).font(.title.bold())
                    HStack(spacing: 14) {
                        Label("\(proposal.ingredients.count) ingredients", systemImage: "basket.fill")
                        Label("\(proposal.steps.count) steps", systemImage: "list.number")
                        Label(proposal.mealType ?? MealType.other.rawValue, systemImage: "fork.knife")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    Divider()
                    Text("Ingredients").font(.title3.bold())
                    ForEach(proposal.ingredients, id: \.self) { Text("• \($0)").font(.body) }
                    Text("Directions").font(.title3.bold()).padding(.top, 4)
                    ForEach(Array(proposal.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)").font(.body)
                    }
                }
                .padding(20)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))

                Picker("Save to Folder", selection: $destinationFolderID) {
                    Label("Unfiled", systemImage: "tray").tag(UUID?.none)
                    ForEach(folders) { folder in
                        Label(folder.name, systemImage: folder.symbol).tag(Optional(folder.id))
                    }
                }
                .font(.body)

                Button("Add Recipe to CookOut", systemImage: "plus.circle.fill") {
                    var recipe = proposal.recipe()
                    recipe.folderID = destinationFolderID
                    onImport(recipe)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private var isValidKey: Bool {
        let key = GroqKeychain.normalized(keyInput)
        return key.hasPrefix("gsk_") && key.count >= 20
    }

    private func saveKey() {
        do {
            try GroqKeychain.save(keyInput)
            keyInput = ""
            hasKey = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

#if os(macOS)
    private func loadAppleNotes() {
        guard !isLoadingNotes else { return }
        isLoadingNotes = true
        errorMessage = nil
        Task { @MainActor in
            await Task.yield()
            do {
                sources = try notesService.loadNotes()
                selectedSource = sources.first
                if sources.isEmpty { errorMessage = "No readable text notes were found in Apple Notes." }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoadingNotes = false
        }
    }
#else
    private func pasteAppleNote() {
        do {
            selectedSource = try notesService.pastedNote()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
#endif

    private func organizeSelectedNote() {
        guard let selectedSource, !isOrganizing else { return }
        isOrganizing = true
        errorMessage = nil
        Task {
            do {
                let result = try await groqService.organizeRecipe(
                    noteTitle: selectedSource.title,
                    noteText: String(selectedSource.text.prefix(60_000)),
                    folders: folders,
                    model: GroqModel(rawValue: selectedModelRaw) ?? .gptOSS120B
                )
                proposal = result
                destinationFolderID = result.folderID.flatMap { suggested in
                    folders.contains(where: { $0.id == suggested }) ? suggested : nil
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isOrganizing = false
        }
    }
}

private extension View {
    @ViewBuilder func cookOutImportFrame() -> some View {
#if os(macOS)
        frame(minWidth: 560, minHeight: 620)
#else
        self
#endif
    }
}
