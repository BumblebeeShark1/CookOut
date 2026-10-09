import SwiftUI

struct AppleNotesImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cookOutPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    let folders: [RecipeFolder]
    let onImport: (CookingNote) -> Bool

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
        CookOutScreen {
            CookOutPageHeader(eyebrow: "From notes to the table", title: "Keep the recipe.\nLeave the clutter.", subtitle: "Bring a favorite from Apple Notes. CookAssistant will turn it into ingredients, directions, and all the little details.")
            CookOutPanel(title: "Connect CookAssistant", subtitle: "Use your Groq API key to organize an imported note.", symbol: "sparkles") {
                SecureField("Groq API key (gsk_…)", text: $keyInput).cookOutField()
                Button("Save key & continue", systemImage: "arrow.right") { saveKey() }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!isValidKey)
                Text("Your key stays in CookOut’s private local storage. Only the selected recipe text is sent to Groq to organize.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var sourcePicker: some View {
        CookOutScreen {
            CookOutPageHeader(eyebrow: "01 · Choose a note", title: "A favorite, ready for a new home.", subtitle: "Choose one recipe to organize. You’ll review the result before it joins your cookbook.")
            CookOutPanel(title: "Bring it along", symbol: "note.text") {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { sourceActions }
                    VStack(alignment: .leading, spacing: 12) { sourceActions }
                }.controlSize(.large)
                if isLoadingNotes { HStack { ProgressView(); Text("Gathering your notes…").font(.subheadline) } }
                Text("Only the note you select is sent to Groq for organizing.").font(.caption).foregroundStyle(.secondary)
            }
#if os(macOS)
            if sources.isEmpty {
                CookOutEmptyState(symbol: "doc.on.clipboard", title: "There’s a recipe in there somewhere.", message: "Load your Apple Notes or paste the recipe you’ve copied.")
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a note", text: $search).textFieldStyle(.plain)
                }.cookOutField()
                LazyVStack(spacing: 14) {
                    ForEach(filteredSources) { source in
                        Button { selectedSource = source } label: {
                            CookOutPanel(title: "") {
                                HStack(alignment: .top, spacing: 18) {
                                    Image(systemName: selectedSource?.id == source.id ? "checkmark.circle.fill" : "circle")
                                        .font(.title2).foregroundStyle(selectedSource?.id == source.id ? palette.accent : .secondary)
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(source.title).font(CookOutTypography.display(25, relativeTo: .title2)).foregroundStyle(.primary).lineLimit(2)
                                        Text(source.text.replacingOccurrences(of: "\n", with: " ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                        Label(source.folderName, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }.buttonStyle(CookOutPressStyle()).accessibilityAddTraits(selectedSource?.id == source.id ? .isSelected : [])
                    }
                }
                if filteredSources.isEmpty { Text("No notes match your search.").foregroundStyle(.secondary) }
                importBar
            }
#else
            if let selectedSource {
                CookOutPanel(title: selectedSource.title, subtitle: "Copied from Apple Notes", symbol: "note.text") {
                    Text(selectedSource.text).font(.body).foregroundStyle(.secondary).lineLimit(12)
                    importButton
                }
            } else {
                CookOutEmptyState(symbol: "doc.on.clipboard", title: "Copy a little inspiration.", message: "In Apple Notes, copy the recipe text. Return here and paste it to begin.")
            }
#endif
        }
    }

    @ViewBuilder private var sourceActions: some View {
#if os(macOS)
        Button("Load Apple Notes", systemImage: "square.and.arrow.down") { loadAppleNotes() }
            .buttonStyle(.borderedProminent).disabled(isLoadingNotes)
#endif
        Button("Paste a copied recipe", systemImage: "doc.on.clipboard") { pasteAppleNote() }
            .buttonStyle(.bordered)
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
        CookOutPanel(title: "") {
            VStack(alignment: .leading, spacing: 14) {
                Text(selectedSource.map { "Ready to organize: \($0.title)" } ?? "Choose a note above to continue.")
                    .font(.subheadline.weight(.medium)).lineLimit(2)
                importButton
            }
        }
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
        CookOutScreen {
            CookOutPageHeader(eyebrow: "02 · Make it yours", title: proposal.title, subtitle: proposal.summary)
            HStack(spacing: 18) {
                Label("\(proposal.ingredients.count) ingredients", systemImage: "basket")
                Label("\(proposal.steps.count) steps", systemImage: "list.number")
            }.font(.subheadline).foregroundStyle(.secondary)
            CookOutPanel(title: "Ingredients", symbol: "basket") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(proposal.ingredients, id: \.self) { ingredient in
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 5, height: 5).padding(.top, 8)
                            Text(ingredient)
                        }
                    }
                }
            }
            CookOutPanel(title: "Directions", symbol: "list.number") {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(proposal.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)").font(.caption.weight(.medium)).frame(width: 28, height: 28)
                                .background(Color.primary.opacity(0.05), in: Circle())
                            Text(step).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            CookOutPanel(title: "Give it a home", subtitle: "Pick a collection, or keep it in your library.", symbol: "folder") {
                Picker("Collection", selection: $destinationFolderID) {
                    Label("Unfiled", systemImage: "tray").tag(UUID?.none)
                    ForEach(folders) { folder in Label(RecipeFolders.path(for: folder.id, in: folders), systemImage: folder.symbol).tag(Optional(folder.id)) }
                }
                Button("Add to my cookbook", systemImage: "plus") {
                    var recipe = proposal.recipe()
                    recipe.folderID = destinationFolderID
                    if onImport(recipe) { dismiss() }
                    else { errorMessage = "The recipe could not be saved. Your import is still here. Check library storage access and try again." }
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
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
#endif

    private func pasteAppleNote() {
        do {
            let source = try notesService.pastedNote()
            sources = [source]
            selectedSource = source
        } catch {
            errorMessage = error.localizedDescription
        }
    }

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
