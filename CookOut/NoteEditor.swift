import SwiftUI

struct NoteEditor: View {
    @Environment(\.cookOutPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    private enum EditorTab: String, CaseIterable, Identifiable {
        case recipe = "Recipe", details = "Details", ai = "AI"
        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CookingNote
    @State private var tagText: String
    @State private var ingredientsText: String
    @State private var stepsText: String
    @State private var suggestions: [CookingSuggestion] = []
    @State private var isThinking = false
    @State private var showingDiscardConfirmation = false
    @State private var selectedTab: EditorTab = .recipe
    @State private var showsTemplates: Bool
    private let original: CookingNote
    private let folders: [RecipeFolder]
    private let engine: any CookingSuggestionEngine
    let onSave: (CookingNote) -> Void

    init(note: CookingNote?, folders: [RecipeFolder] = [], initialFolderID: UUID? = nil, engine: any CookingSuggestionEngine = CoreMLCookingSuggestionEngine(), onSave: @escaping (CookingNote) -> Void) {
        var value = note ?? CookingNote()
        if note == nil { value.folderID = initialFolderID }
        _draft = State(initialValue: value)
        _tagText = State(initialValue: value.tags.joined(separator: ", "))
        _ingredientsText = State(initialValue: value.ingredients.joined(separator: "\n"))
        _stepsText = State(initialValue: value.steps.joined(separator: "\n"))
        _showsTemplates = State(initialValue: note == nil)
        original = value
        self.folders = folders
        self.engine = engine
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Editor section", selection: $selectedTab) {
                    ForEach(EditorTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.vertical, 10)
                .background(palette.softGradient)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(palette.gradient).frame(height: 2).opacity(0.75)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case .recipe: recipeSections
                        case .details: detailSections
                        case .ai: aiSections
                        }
                    }
                    .frame(maxWidth: 820)
                    .padding()
                    .frame(maxWidth: .infinity)
                }
                .background(palette.background(for: colorScheme))
            }
            .navigationTitle(original.title.isEmpty ? "New Recipe" : "Edit Recipe")
            .interactiveDismissDisabled(hasUnsavedChanges)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges { showingDiscardConfirmation = true }
                        else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.tags = normalizedTags
                        draft.ingredients = parsedLines(ingredientsText)
                        draft.steps = parsedLines(stepsText)
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasRecipeContent)
                }
            }
            .confirmationDialog("Discard this draft?", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
        .tint(palette.accent)
        .cookOutEditorFrame()
    }

    @ViewBuilder private var recipeSections: some View {
        if showsTemplates && !hasRecipeContent {
            EditorPanel(title: "Quick start", subtitle: "Pick a structure or begin from scratch.", symbol: "bolt.fill") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    TemplateButton(title: "Everyday recipe", symbol: "fork.knife", color: CookOutTheme.orange) { applyTemplate(.everyday) }
                    TemplateButton(title: "Baking recipe", symbol: "oven", color: CookOutTheme.berry) { applyTemplate(.baking) }
                    TemplateButton(title: "Kitchen experiment", symbol: "testtube.2", color: CookOutTheme.mint) { applyTemplate(.experiment) }
                }
            }
        }
        EditorPanel(title: "Name and notes", subtitle: "Give this recipe a clear identity and a useful briefing.", symbol: "text.alignleft") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recipe name").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("Grandma’s tomato pasta", text: $draft.title)
                    .textFieldStyle(.roundedBorder).font(.title3.weight(.semibold))
                Text("Chef’s notes").font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 4)
                TextField("What makes this recipe special?", text: $draft.body, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(3...8)
            }
        }
        EditorPanel(title: "Ingredients", subtitle: "One ingredient per line · \(parsedLines(ingredientsText).count) total", symbol: "basket.fill") {
            MultilineRecipeField(text: $ingredientsText, placeholder: "2 cups flour\n1 tsp salt\n2 eggs", symbol: "carrot", minHeight: 150)
        }
        EditorPanel(title: "Directions", subtitle: "One instruction per line · \(parsedLines(stepsText).count) steps", symbol: "list.number") {
            MultilineRecipeField(text: $stepsText, placeholder: "Preheat the oven…\nMix the ingredients…\nCook until…", symbol: "list.number", minHeight: 180)
        }
        EditorPanel(title: "Tags", subtitle: "Separate tags with commas for fast filtering.", symbol: "tag.fill") {
            TextField("family favorite, pasta, dinner", text: $tagText).textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder private var detailSections: some View {
        EditorPanel(title: "Organization", subtitle: "Route the recipe to the right kitchen station.", symbol: "folder.fill") {
            Picker("Folder", selection: $draft.folderID) {
                Label("Unfiled", systemImage: "tray").tag(UUID?.none)
                ForEach(folders) { folder in
                    Label(folder.name, systemImage: folder.symbol).tag(Optional(folder.id))
                }
            }
            Divider()
            Picker("Meal", selection: $draft.mealType) { ForEach(MealType.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
            Divider()
            Picker("Status", selection: $draft.status) { ForEach(RecipeStatus.allCases) { Text($0.rawValue).tag($0) } }
            Divider()
            Picker("Difficulty", selection: $draft.difficulty) { ForEach(RecipeDifficulty.allCases) { Text($0.rawValue).tag($0) } }
            Divider()
            Toggle("Favorite", isOn: $draft.isFavorite)
        }
        EditorPanel(title: "Yield and timing", subtitle: "Operational numbers for planning and cook mode.", symbol: "timer") {
            Stepper("Servings: \(draft.servings)", value: $draft.servings, in: 1...24)
            Divider()
            Stepper("Prep time: \(draft.prepMinutes) min", value: $draft.prepMinutes, in: 0...480, step: 5)
            Divider()
            Stepper("Cook time: \(draft.cookMinutes) min", value: $draft.cookMinutes, in: 0...720, step: 5)
            Divider()
            LabeledContent("Total time", value: "\(draft.totalMinutes) min")
        }
        EditorPanel(title: "Your rating", subtitle: "Record how this version performed.", symbol: "star.fill") {
            HStack { Spacer(); ForEach(1...5, id: \.self) { value in
                Button { draft.rating = draft.rating == value ? 0 : value } label: {
                    Image(systemName: value <= draft.rating ? "star.fill" : "star").font(.title2).foregroundStyle(.orange)
                }.buttonStyle(.plain)
            }; Spacer() }
        }
    }

    @ViewBuilder private var aiSections: some View {
        EditorPanel(title: "On-device sous-chef", subtitle: "Uses your Cooking Assistant Core ML model. Nothing leaves the device.", symbol: "cpu") {
            Button { Task { await refreshSuggestions() } } label: {
                HStack { Label("Analyze this recipe", systemImage: "sparkles").fontWeight(.semibold); Spacer(); if isThinking { ProgressView() } }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }.buttonStyle(.borderedProminent).disabled(isThinking || (draft.title.isEmpty && draft.body.isEmpty && ingredientsText.isEmpty))
        }
        if suggestions.isEmpty && !isThinking {
            EditorPanel(title: "Ready for analysis", subtitle: "Add recipe content, then run the model for technique, timing, seasoning, and note-quality suggestions.", symbol: "wand.and.sparkles") {
                Text("Suggestions appear here and can be added to the chef’s notes with one click.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        ForEach(suggestions) { suggestion in
            EditorPanel(title: suggestion.title, subtitle: "AI suggestion", symbol: suggestion.symbol) {
                Button {
                    if !draft.body.isEmpty && !suggestion.insertion.hasPrefix("\n") { draft.body += "\n" }
                    draft.body += suggestion.insertion
                    suggestions.removeAll { $0.id == suggestion.id }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(suggestion.insertion.trimmingCharacters(in: .whitespacesAndNewlines)).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                        Label("Add to chef’s notes", systemImage: "plus.circle.fill").font(.subheadline.bold())
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var normalizedTags: [String] {
        var seen = Set<String>()
        return tagText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private var hasRecipeContent: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !stepsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasUnsavedChanges: Bool {
        var candidate = draft
        candidate.tags = normalizedTags
        candidate.ingredients = parsedLines(ingredientsText)
        candidate.steps = parsedLines(stepsText)
        return candidate != original
    }

    private func parsedLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^[-•\d.\s]+"#, with: "", options: .regularExpression)
        }.filter { !$0.isEmpty }
    }

    @MainActor private func refreshSuggestions() async {
        let requestedTitle = draft.title
        let requestedBody = [draft.body, "Ingredients:", ingredientsText, "Directions:", stepsText].joined(separator: "\n")
        isThinking = true
        defer { isThinking = false }
        let result = await engine.suggestions(title: requestedTitle, body: requestedBody)
        let currentBody = [draft.body, "Ingredients:", ingredientsText, "Directions:", stepsText].joined(separator: "\n")
        guard requestedTitle == draft.title, requestedBody == currentBody else { return }
        suggestions = result
    }

    private enum RecipeTemplate { case everyday, baking, experiment }

    private func applyTemplate(_ template: RecipeTemplate) {
        showsTemplates = false
        switch template {
        case .everyday:
            draft.mealType = .dinner; draft.difficulty = .easy; draft.servings = 4
            ingredientsText = ""; stepsText = "Prep the ingredients.\nCook until done.\nTaste, adjust seasoning, and serve."
        case .baking:
            draft.mealType = .dessert; draft.difficulty = .medium; draft.servings = 8
            draft.prepMinutes = 20; draft.cookMinutes = 30
            stepsText = "Preheat the oven.\nPrepare the pan.\nMix dry and wet ingredients separately.\nCombine without overmixing.\nBake until the visual and texture cues are met.\nCool before serving."
        case .experiment:
            draft.status = .testing; draft.body = "Goal:\n\nWhat I changed:\n\nResult:\n\nNext time:"
        }
    }
}

private extension View {
    @ViewBuilder func cookOutEditorFrame() -> some View {
#if os(macOS)
        frame(minWidth: 680, minHeight: 720)
#else
        self
#endif
    }
}

private struct EditorPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    let symbol: String
    let content: Content

    init(title: String, subtitle: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: symbol).font(.headline).foregroundStyle(CookOutTheme.orange)
                    .frame(width: 34, height: 34).background(CookOutTheme.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .dark ? CookOutTheme.grapheneRaised.opacity(0.88) : Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.08)) }
    }
}

private struct TemplateButton: View {
    let title: String
    let symbol: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(12).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(.plain)
    }
}

private struct MultilineRecipeField: View {
    @Binding var text: String
    let placeholder: String
    let symbol: String
    let minHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol)
                    Text(placeholder)
                }
                .foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.vertical, 8)
                .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .padding(6)
                .scrollContentBackground(.hidden)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.10)) }
        }
    }
}
