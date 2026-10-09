import SwiftUI

struct NoteEditor: View {
    @Environment(\.cookOutPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var saveFailed = false
    @State private var selectedTab: EditorTab = .recipe
    @State private var showsTemplates: Bool
    private let original: CookingNote
    private let folders: [RecipeFolder]
    private let availableTags: [String]
    private let engine: any CookingSuggestionEngine
    let onSave: (CookingNote) -> Bool

    init(note: CookingNote?, folders: [RecipeFolder] = [], initialFolderID: UUID? = nil, availableTags: [String] = [], engine: any CookingSuggestionEngine = CoreMLCookingSuggestionEngine(), onSave: @escaping (CookingNote) -> Bool) {
        var value = note ?? CookingNote()
        if note == nil { value.folderID = initialFolderID }
        value.tags = RecipeTags.normalized(value.tags)
        _draft = State(initialValue: value)
        _tagText = State(initialValue: "")
        _ingredientsText = State(initialValue: value.ingredients.joined(separator: "\n"))
        _stepsText = State(initialValue: value.steps.joined(separator: "\n"))
        _showsTemplates = State(initialValue: note == nil)
        original = value
        self.folders = folders
        self.availableTags = RecipeTags.normalized(availableTags)
        self.engine = engine
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("THE RECIPE JOURNAL").font(.caption2.weight(.semibold)).tracking(2.2).foregroundStyle(.secondary)
                            Text(original.title.isEmpty ? "Something delicious starts here." : "Make it your own.")
                                .font(CookOutTypography.display(30, relativeTo: .title))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "square.and.pencil").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                        ForEach(EditorTab.allCases) { tab in
                            Button { selectedTab = tab } label: {
                                Text(tab == .ai ? "Suggestions" : tab.rawValue).font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 20).padding(.vertical, 11)
                                    .foregroundStyle(selectedTab == tab ? Color.white : .primary)
                                    .background(selectedTab == tab ? palette.accent : Color.primary.opacity(0.04), in: Capsule())
                            }.buttonStyle(CookOutPressStyle())
                                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                        }
                        }
                    }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(CookOutTheme.surface(for: colorScheme))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        switch selectedTab {
                        case .recipe: recipeSections
                        case .details: detailSections
                        case .ai: aiSections
                        }
                    }
                    .frame(maxWidth: 820)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: selectedTab)
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
                        draft.ingredients = RecipeQuantity.ingredientLines(ingredientsText)
                        draft.steps = RecipeQuantity.directionLines(stepsText)
                        if onSave(draft) { dismiss() } else { saveFailed = true }
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
            .alert("Recipe could not be saved", isPresented: $saveFailed) {
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Your draft is still here. Check library storage access and try again.") }
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
        EditorPanel(title: "Name and notes", subtitle: "The name you’ll remember, and the little details that matter.", symbol: "text.alignleft") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recipe name").font(.subheadline.bold()).foregroundStyle(.secondary)
                TextField("Grandma’s tomato pasta", text: $draft.title)
                    .font(CookOutTypography.display(26, relativeTo: .title2)).cookOutField()
                Text("Chef’s notes").font(.subheadline.bold()).foregroundStyle(.secondary).padding(.top, 4)
                TextField("What makes this recipe special?", text: $draft.body, axis: .vertical)
                    .lineLimit(3...8).cookOutField()
            }
        }
        tagSection
        EditorPanel(title: "Ingredients", subtitle: "One ingredient per line · \(RecipeQuantity.ingredientLines(ingredientsText).count) total", symbol: "basket.fill") {
            MultilineRecipeField(text: $ingredientsText, placeholder: "2 cups flour\n1 tsp salt\n2 eggs", symbol: "carrot", minHeight: 150)
        }
        EditorPanel(title: "Directions", subtitle: "One instruction per line · \(RecipeQuantity.directionLines(stepsText).count) steps", symbol: "list.number") {
            MultilineRecipeField(text: $stepsText, placeholder: "Preheat the oven…\nMix the ingredients…\nCook until…", symbol: "list.number", minHeight: 180)
        }
    }

    @ViewBuilder private var detailSections: some View {
        EditorPanel(title: "Organization", subtitle: "Keep it in a collection and give it a place at the table.", symbol: "folder.fill") {
            Picker("Collection", selection: $draft.folderID) {
                Label("Unfiled", systemImage: "tray").tag(UUID?.none)
                ForEach(folders) { folder in
                    Label(RecipeFolders.path(for: folder.id, in: folders), systemImage: folder.symbol).tag(Optional(folder.id))
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
        EditorPanel(title: "Yield and timing", subtitle: "Plan your portions and your time in the kitchen.", symbol: "timer") {
            Stepper("Servings: \(draft.servings)", value: $draft.servings, in: 1...24)
            if let source = draft.sourceURL {
                Toggle("Source serving yield confirmed", isOn: Binding(get: { draft.sourceYieldIsServings == true }, set: { draft.sourceYieldIsServings = $0 }))
                Text("Confirm the number of servings at the original source before enabling quantity scaling.").font(.caption).foregroundStyle(.secondary)
                if let url = RecipeSourceURL.valid(source) { Link("Open original recipe", destination: url) }
            }
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
                    Image(systemName: value <= draft.rating ? "star.fill" : "star").font(.title2).foregroundStyle(CookOutTheme.mango)
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
                        Text(suggestion.insertion.trimmingCharacters(in: .whitespacesAndNewlines)).font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
                        Label("Add to chef’s notes", systemImage: "plus.circle.fill").font(.subheadline.bold())
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var normalizedTags: [String] {
        RecipeTags.normalized(draft.tags + RecipeTags.parse(tagText))
    }

    private var suggestedTags: [String] {
        let attached = Set(normalizedTags.map(RecipeTags.key))
        let search = RecipeTags.key(tagText.trimmingCharacters(in: .whitespacesAndNewlines))
        return availableTags.filter { !attached.contains(RecipeTags.key($0)) && (search.isEmpty || RecipeTags.key($0).contains(search)) }
    }

    private var tagSection: some View {
        EditorPanel(title: "Tags", subtitle: "A recipe can share tags with recipes in any folder.", symbol: "tag.fill") {
            VStack(alignment: .leading, spacing: 12) {
                if !draft.tags.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(RecipeTags.normalized(draft.tags), id: \.self) { tag in
                            Button {
                                draft.tags.removeAll { RecipeTags.key($0) == RecipeTags.key(tag) }
                            } label: {
                                HStack(spacing: 8) { Text(tag).lineLimit(1); Image(systemName: "xmark").font(.caption2) }
                                    .font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 9)
                                    .foregroundStyle(palette.accent).background(palette.accent.opacity(0.10), in: Capsule())
                            }.buttonStyle(CookOutPressStyle()).accessibilityLabel("Remove tag \(tag)")
                        }
                    }
                }
                HStack {
                    TextField("Add tags, separated by commas", text: $tagText).cookOutField()
                        .onSubmit(addPendingTags).accessibilityLabel("New recipe tags")
                    Button("Add", systemImage: "plus", action: addPendingTags)
                        .buttonStyle(.bordered).disabled(RecipeTags.parse(tagText).isEmpty)
                        .accessibilityLabel("Add recipe tags")
                }
                if !suggestedTags.isEmpty {
                    Text("From your cookbook").font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(Array(suggestedTags.prefix(12)), id: \.self) { tag in
                            Button {
                                draft.tags = RecipeTags.normalized(draft.tags + [tag])
                            } label: {
                                Label(tag, systemImage: "plus").font(.caption).lineLimit(1)
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(Color.primary.opacity(0.04), in: Capsule())
                            }.buttonStyle(CookOutPressStyle()).accessibilityLabel("Add tag \(tag)")
                        }
                    }
                }
            }
        }
    }

    private func addPendingTags() {
        draft.tags = normalizedTags
        tagText = ""
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
        candidate.ingredients = RecipeQuantity.ingredientLines(ingredientsText)
        candidate.steps = RecipeQuantity.directionLines(stepsText)
        return candidate != original
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
        frame(minWidth: 760, minHeight: 760)
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
        CookOutPanel(title: title, subtitle: subtitle, symbol: symbol) { content }
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
        }.buttonStyle(CookOutPressStyle())
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
