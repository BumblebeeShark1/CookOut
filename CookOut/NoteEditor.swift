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
    private let engine: any CookingSuggestionEngine
    let onSave: (CookingNote) -> Void

    init(note: CookingNote?, engine: any CookingSuggestionEngine = CoreMLCookingSuggestionEngine(), onSave: @escaping (CookingNote) -> Void) {
        let value = note ?? CookingNote()
        _draft = State(initialValue: value)
        _tagText = State(initialValue: value.tags.joined(separator: ", "))
        _ingredientsText = State(initialValue: value.ingredients.joined(separator: "\n"))
        _stepsText = State(initialValue: value.steps.joined(separator: "\n"))
        _showsTemplates = State(initialValue: note == nil)
        original = value
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

                Form {
                    switch selectedTab {
                    case .recipe: recipeSections
                    case .details: detailSections
                    case .ai: aiSections
                    }
                }
                .scrollContentBackground(.hidden)
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
    }

    @ViewBuilder private var recipeSections: some View {
        if showsTemplates && !hasRecipeContent {
            Section("Quick start") {
                Button { applyTemplate(.everyday) } label: { Label("Everyday recipe", systemImage: "fork.knife") }
                Button { applyTemplate(.baking) } label: { Label("Baking recipe", systemImage: "oven") }
                Button { applyTemplate(.experiment) } label: { Label("Kitchen experiment", systemImage: "testtube.2") }
            }
        }
        Section("Name and notes") {
            TextField("Recipe name", text: $draft.title).font(.title3.weight(.semibold))
            TextField("What makes this recipe special?", text: $draft.body, axis: .vertical).lineLimit(3...8)
        }
        Section {
            MultilineRecipeField(text: $ingredientsText, placeholder: "2 cups flour\n1 tsp salt\n2 eggs", symbol: "carrot", minHeight: 150)
        } header: { Text("Ingredients") }
          footer: { Text("\(parsedLines(ingredientsText).count) ingredients · one per line") }
        Section {
            MultilineRecipeField(text: $stepsText, placeholder: "Preheat the oven…\nMix the ingredients…\nCook until…", symbol: "list.number", minHeight: 180)
        } header: { Text("Directions") }
          footer: { Text("\(parsedLines(stepsText).count) steps · one instruction per line") }
        Section("Tags") { TextField("family favorite, pasta, dinner", text: $tagText) }
    }

    @ViewBuilder private var detailSections: some View {
        Section("Organization") {
            Picker("Meal", selection: $draft.mealType) { ForEach(MealType.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
            Picker("Status", selection: $draft.status) { ForEach(RecipeStatus.allCases) { Text($0.rawValue).tag($0) } }
            Picker("Difficulty", selection: $draft.difficulty) { ForEach(RecipeDifficulty.allCases) { Text($0.rawValue).tag($0) } }
            Toggle("Favorite", isOn: $draft.isFavorite)
        }
        Section("Yield and timing") {
            Stepper("Servings: \(draft.servings)", value: $draft.servings, in: 1...24)
            Stepper("Prep time: \(draft.prepMinutes) min", value: $draft.prepMinutes, in: 0...480, step: 5)
            Stepper("Cook time: \(draft.cookMinutes) min", value: $draft.cookMinutes, in: 0...720, step: 5)
            LabeledContent("Total time", value: "\(draft.totalMinutes) min")
        }
        Section("Your rating") {
            HStack { Spacer(); ForEach(1...5, id: \.self) { value in
                Button { draft.rating = draft.rating == value ? 0 : value } label: {
                    Image(systemName: value <= draft.rating ? "star.fill" : "star").font(.title2).foregroundStyle(.orange)
                }.buttonStyle(.plain)
            }; Spacer() }
        }
    }

    @ViewBuilder private var aiSections: some View {
        Section {
            Button { Task { await refreshSuggestions() } } label: {
                HStack { Label("Analyze this recipe", systemImage: "sparkles"); Spacer(); if isThinking { ProgressView() } }
            }.disabled(isThinking || (draft.title.isEmpty && draft.body.isEmpty && ingredientsText.isEmpty))
        } header: { Text("On-device sous-chef") }
          footer: { Text("Uses your Cooking Assistant Core ML model. Nothing leaves the phone.") }
        if suggestions.isEmpty && !isThinking {
            Section { Text("Run an analysis to get technique, timing, seasoning, and note-quality suggestions.").foregroundStyle(.secondary) }
        }
        ForEach(suggestions) { suggestion in
            Section {
                Button {
                    if !draft.body.isEmpty && !suggestion.insertion.hasPrefix("\n") { draft.body += "\n" }
                    draft.body += suggestion.insertion
                    suggestions.removeAll { $0.id == suggestion.id }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(suggestion.title, systemImage: suggestion.symbol).font(.headline)
                        Text(suggestion.insertion.trimmingCharacters(in: .whitespacesAndNewlines)).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                    }
                }
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
            TextEditor(text: $text).frame(minHeight: minHeight).scrollContentBackground(.hidden)
        }
    }
}
