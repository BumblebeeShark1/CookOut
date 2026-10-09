import SwiftUI

struct CookingChatView: View {
    var embedded = false
    private enum ChatTab: Hashable { case chat, history }

    @Environment(\.cookOutPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    let cookbook: [CookingNote]
    let folders: [RecipeFolder]
    var bank: [BankRecipe] = []
    let onSaveRecipe: (CookingNote) -> Bool
    @StateObject private var historyStore = ChatHistoryStore()
    @State private var messages: [ChatMessage] = []
    @State private var activeConversationID: UUID?
    @State private var selectedTab: ChatTab = .chat
    @State private var historyQuery = ""
    @State private var showingClearHistoryConfirmation = false
    @State private var pendingRecipeEdit: RecipeEditProposal?
    @State private var pendingRecipeCreate: RecipeCreateProposal?
    @State private var input = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var hasKey = GroqKeychain.load() != nil
    @State private var keyInput = ""
    @State private var showingKeySettings = false
    @State private var isTestingKey = false
    @State private var keyError: String?
    @FocusState private var inputFocused: Bool
    @AppStorage("cookout.assistantFocus") private var focusRaw = CookingAssistantFocus.enhance.rawValue
    @AppStorage("cookout.groqModel") private var selectedModelRaw = GroqModel.gptOSS120B.rawValue
    private let service = GroqChatService()

    var body: some View {
        NavigationStack {
            Group {
                if !hasKey { keySetup }
                else { chatTabs }
            }
            .navigationTitle(selectedTab == .history && hasKey ? "CookAssistant History" : "CookAssistant")
            .toolbar {
                if !embedded { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                if hasKey {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("AI Model", selection: $selectedModelRaw) {
                                ForEach(GroqModel.allCases) { model in
                                    Label(model.name, systemImage: model.symbol).tag(model.rawValue)
                                }
                            }
                            Divider()
                            Button("New conversation", systemImage: "square.and.pencil") { startNewConversation() }
                            if !messages.isEmpty {
                                Button("Clear conversation", systemImage: "trash") { startNewConversation() }
                            }
                            Button("Replace API key", systemImage: "key") { keyInput = ""; showingKeySettings = true }
                            Button("Remove API key", systemImage: "key.slash", role: .destructive) { GroqKeychain.delete(); hasKey = false }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .sheet(isPresented: $showingKeySettings) { keyEditor }
            .confirmationDialog("Delete all CookAssistant conversations?", isPresented: $showingClearHistoryConfirmation, titleVisibility: .visible) {
                Button("Delete All History", role: .destructive) {
                    historyStore.deleteAll()
                    activeConversationID = nil
                    messages.removeAll()
                }
            } message: {
                Text("This removes the locally saved history and cannot be undone.")
            }
            .alert("Is it OK if CookAssistant can edit \(pendingRecipeName)?",
                   isPresented: Binding(get: { pendingRecipeEdit != nil }, set: { if !$0 { pendingRecipeEdit = nil } }),
                   presenting: pendingRecipeEdit) { proposal in
                Button("Allow Edit") { apply(proposal) }
                Button("Not Now", role: .cancel) { decline(proposal) }
            } message: { proposal in
                Text(proposal.summary)
            }
            .alert("Add \(pendingNewRecipeName) to CookOut?",
                   isPresented: Binding(get: { pendingRecipeCreate != nil }, set: { if !$0 { pendingRecipeCreate = nil } }),
                   presenting: pendingRecipeCreate) { proposal in
                Button("Add Recipe") { apply(proposal) }
                Button("Not Now", role: .cancel) { decline(proposal) }
            } message: { proposal in
                Text("\(proposal.summary)\n\n\(proposal.ingredients.count) ingredients · \(proposal.steps.count) steps")
            }
        }
        .cookOutCanvas()
    }

    private var focus: CookingAssistantFocus { CookingAssistantFocus(rawValue: focusRaw) ?? .enhance }

    private var chatTabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        tabButton("Conversation", symbol: "bubble.left", value: .chat)
                        tabButton("History", symbol: "clock", value: .history)
                    }
                }
                Button { startNewConversation() } label: { Image(systemName: "plus").frame(width: 32, height: 40) }
                    .buttonStyle(.borderless).accessibilityLabel("New conversation")
            }.padding(.horizontal, 28).padding(.vertical, 18)
            Picker("Cooking focus", selection: $focusRaw) {
                ForEach(CookingAssistantFocus.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }.pickerStyle(.segmented).padding(.horizontal, 28).padding(.bottom, 14)
            Divider()
            if selectedTab == .chat { conversation } else { history }
        }.animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: selectedTab)
    }

    private func tabButton(_ title: String, symbol: String, value: ChatTab) -> some View {
        Button { selectedTab = value } label: {
            Label(title, systemImage: symbol).font(.subheadline.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 11)
                .foregroundStyle(selectedTab == value ? Color.white : .primary)
                .background(selectedTab == value ? palette.accent : Color.primary.opacity(0.04), in: Capsule())
        }.buttonStyle(CookOutPressStyle()).accessibilityAddTraits(selectedTab == value ? .isSelected : [])
    }

    private var keySetup: some View {
        CookOutScreen {
            CookOutPageHeader(eyebrow: "Meet your sous-chef", title: "A little help.\nA lot of possibilities.",
                              subtitle: "Find tonight’s dinner, breathe new life into a favorite, or get a second opinion at the stove.")
            CookOutPanel(title: "CookAssistant", subtitle: "Good ideas belong in your kitchen.", symbol: "sparkles") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 22)], alignment: .leading, spacing: 24) {
                    assistantBenefit("lightbulb", "Find your next favorite", "Meal ideas for your mood, ingredients, and time.")
                    assistantBenefit("arrow.triangle.swap", "Make it work", "Thoughtful substitutions and practical technique advice.")
                    assistantBenefit("book.closed", "Build your cookbook", "Create recipes and refine the ones you already love.")
                }
                Divider()
                HStack {
                    Label("Powered by \(selectedModel.name) via Groq", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Button { keyError = nil; showingKeySettings = true } label: {
                    Label("Connect CookAssistant", systemImage: "arrow.right").padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            Label(keyStorageDescription, systemImage: "lock").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func assistantBenefit(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(CookOutTypography.display(23, relativeTo: .title3))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if messages.isEmpty {
                            CookOutPageHeader(eyebrow: "Your sous-chef", title: "What sounds good today?", subtitle: "Bring a question, an ingredient, or a little curiosity. We’ll take it from there.")
                                .padding(.top, 24)
                            promptChips.padding(.vertical, 12)
                        }
                        ForEach(messages) { message in ChatBubble(message: message).id(message.id) }
                        if isSending {
                            HStack(spacing: 12) { ProgressView().controlSize(.small); Text("A little food for thought…").font(.subheadline) }
                                .foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                        if let errorMessage {
                            CookOutPanel(title: "Let’s try that again.", symbol: "exclamationmark.circle") {
                                Text(errorMessage).font(.subheadline).foregroundStyle(.secondary)
                                Button("Try again", systemImage: "arrow.clockwise") { retryLastRequest() }.buttonStyle(.bordered)
                            }
                        }
                    }.padding(28).frame(maxWidth: 920).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    if let id = messages.last?.id {
                        withAnimation(CookOutTheme.motion(reduceMotion: reduceMotion)) { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 16) {
                    TextField("An idea, an ingredient, a question…", text: $input, axis: .vertical)
                        .textFieldStyle(.plain).lineLimit(1...5).focused($inputFocused).submitLabel(.send).onSubmit { send() }
                    Button { send() } label: {
                        Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(palette.accent, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(CookOutPressStyle()).accessibilityLabel("Send message")
                        .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                }.padding(16)
                    .background(CookOutTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).stroke(CookOutTheme.border(for: colorScheme)) }
                Text("\(selectedModel.name) via Groq")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 28).padding(.bottom, 18).padding(.top, 12)
                .frame(maxWidth: 920).frame(maxWidth: .infinity)
        }.cookOutCanvas()
    }

    private var filteredHistory: [ChatConversation] {
        let search = historyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return historyStore.conversations }
        return historyStore.conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(search) ||
                conversation.messages.contains { $0.content.localizedCaseInsensitiveContains(search) }
        }
    }

    private var history: some View {
        CookOutScreen {
            CookOutPageHeader(eyebrow: "Ideas worth coming back to", title: "Your kitchen conversations.", subtitle: "Pick up an old idea or return to advice you found helpful.")
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a conversation", text: $historyQuery).textFieldStyle(.plain)
                if !historyQuery.isEmpty {
                    Button { historyQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                }
            }.cookOutField()
            if filteredHistory.isEmpty {
                CookOutEmptyState(symbol: "bubble.left.and.bubble.right", title: historyStore.conversations.isEmpty ? "Good ideas start with a question." : "No matching conversations.",
                                  message: historyStore.conversations.isEmpty ? "Your conversations will be collected here automatically." : "Try another word or phrase.")
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(filteredHistory) { conversation in
                        Button { open(conversation) } label: {
                            CookOutPanel(title: "") {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(conversation.title).font(CookOutTypography.display(25, relativeTo: .title2)).foregroundStyle(.primary).lineLimit(2)
                                        Text(conversation.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                        Text(conversation.updatedAt, format: .dateTime.month(.abbreviated).day())
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 10)
                                    Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                                }
                            }
                        }.buttonStyle(CookOutPressStyle())
                            .contextMenu {
                                Button("Open", systemImage: "bubble.left") { open(conversation) }
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(conversation) }
                            }
                    }
                }
                Button("Delete all history", systemImage: "trash", role: .destructive) { showingClearHistoryConfirmation = true }
                    .font(.caption).buttonStyle(.borderless)
            }
        }
    }

    private var promptChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                quickPrompt("lightbulb", "Brainstorm dinner", CookOutTheme.orange, "Brainstorm six varied, balanced dinners with vegetables, satisfying carbohydrates, and protein. No restrictive diet. Include flavor, effort, and one useful variation for each.")
                quickPrompt("wand.and.sparkles", "Improve a recipe", CookOutTheme.berry, "Help me improve one of my recipes")
                quickPrompt("calendar", "Plan my week", CookOutTheme.coral, "Help me brainstorm a varied week of nourishing everyday meals. Ask only for essential household, ingredient exclusion, and time details. Include pantry reuse and a prep outline; no keto or weight-loss targets.")
                quickPrompt("arrow.triangle.swap", "Substitution", CookOutTheme.mint, "Suggest a smart substitution")
            }
        }.contentMargins(.horizontal, 2)
    }

    private func quickPrompt(_ symbol: String, _ title: String, _ color: Color, _ prompt: String) -> some View {
        Button { input = prompt; send() } label: {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(color)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
            }.frame(width: 150, alignment: .leading).padding(20)
                .background(CookOutTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(CookOutTheme.border(for: colorScheme)) }
        }.buttonStyle(CookOutPressStyle())
    }

    private var keyEditor: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "A secure connection", title: "Invite your sous-chef in.", subtitle: "Connect your Groq account to bring CookAssistant into your kitchen.")
                CookOutPanel(title: "Your Groq API key", subtitle: keyStorageDescription, symbol: "key") {
                    SecureField("gsk_…", text: $keyInput).textContentType(.password).cookOutField()
                    if isTestingKey { HStack { ProgressView(); Text("Checking your connection…").font(.subheadline) } }
                    if let keyError { Label(keyError, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.subheadline) }
                    Text("Your questions and cookbook context are sent to Groq when you chat. Recipe changes are reviewed before they’re saved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Secure Connection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingKeySettings = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Test & Save") { testAndSaveKey() }
                        .disabled(!isValidKey || isTestingKey)
                }
            }
        }
        .cookOutSheetFrame(width: 640, height: 560)
    }

    private var normalizedKeyInput: String { GroqKeychain.normalized(keyInput) }
    private var isValidKey: Bool { normalizedKeyInput.hasPrefix("gsk_") && normalizedKeyInput.count >= 20 }

    private func testAndSaveKey() {
        let key = normalizedKeyInput
        guard isValidKey else { return }
        isTestingKey = true; keyError = nil
        Task {
            do {
                _ = try await service.reply(to: [ChatMessage(role: "user", content: "Reply with OK only.")], cookbook: [], folders: [], apiKey: key, model: selectedModel)
                try GroqKeychain.save(key)
                keyInput = ""; hasKey = true; showingKeySettings = false
            } catch { keyError = error.localizedDescription }
            isTestingKey = false
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        input = ""; errorMessage = nil
        messages.append(ChatMessage(role: "user", content: text))
        saveConversation()
        isSending = true
        Task {
            do {
                handle(try await service.reply(to: messages, cookbook: cookbook, folders: folders, model: selectedModel, focus: focus, bank: bank))
                saveConversation()
            }
            catch { errorMessage = error.localizedDescription }
            isSending = false
        }
    }

    private func retryLastRequest() {
        guard !isSending, messages.last?.role == "user" else { return }
        errorMessage = nil; isSending = true
        Task {
            do {
                handle(try await service.reply(to: messages, cookbook: cookbook, folders: folders, model: selectedModel, focus: focus, bank: bank))
                saveConversation()
            }
            catch { errorMessage = error.localizedDescription }
            isSending = false
        }
    }

    private func saveConversation() {
        activeConversationID = historyStore.save(id: activeConversationID,
                                                 messages: messages,
                                                 modelRawValue: selectedModelRaw)
    }

    private func startNewConversation() {
        messages.removeAll()
        activeConversationID = nil
        errorMessage = nil
        input = ""
        selectedTab = .chat
    }

    private func open(_ conversation: ChatConversation) {
        activeConversationID = conversation.id
        messages = conversation.messages
        selectedModelRaw = conversation.modelRawValue
        errorMessage = nil
        selectedTab = .chat
    }

    private func delete(_ conversation: ChatConversation) {
        historyStore.delete(conversation)
        if activeConversationID == conversation.id { startNewConversation() }
    }

    private var pendingRecipeName: String {
        guard let proposal = pendingRecipeEdit,
              let recipe = cookbook.first(where: { $0.id == proposal.recipeID }) else { return "this recipe" }
        return recipe.title.isEmpty ? "this recipe" : "“\(recipe.title)”"
    }

    private var pendingNewRecipeName: String {
        let title = pendingRecipeCreate?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "this recipe" : "“\(title)”"
    }

    private func handle(_ reply: GroqReply) {
        messages.append(ChatMessage(role: "assistant", content: reply.content))
        if let proposal = reply.editProposal {
            guard cookbook.contains(where: { $0.id == proposal.recipeID }) else {
                messages.append(ChatMessage(role: "assistant", content: "I couldn't match that edit to a saved recipe, so nothing was changed."))
                return
            }
            pendingRecipeEdit = proposal
        }
        if let proposal = reply.createProposal {
            pendingRecipeCreate = proposal
        }
    }

    private func apply(_ proposal: RecipeEditProposal) {
        guard let recipe = cookbook.first(where: { $0.id == proposal.recipeID }) else { return }
        let updated = proposal.applying(to: recipe)
        guard onSaveRecipe(updated) else { return }
        pendingRecipeEdit = nil
        messages.append(ChatMessage(role: "assistant", content: "Done — I updated **\(updated.title.isEmpty ? "the recipe" : updated.title)**."))
        saveConversation()
    }

    private func decline(_ proposal: RecipeEditProposal) {
        pendingRecipeEdit = nil
        let name = cookbook.first(where: { $0.id == proposal.recipeID })?.title ?? "the recipe"
        messages.append(ChatMessage(role: "assistant", content: "No problem — **\(name)** was left unchanged."))
        saveConversation()
    }

    private func apply(_ proposal: RecipeCreateProposal) {
        var recipe = proposal.recipe()
        if let folderID = recipe.folderID, !folders.contains(where: { $0.id == folderID }) {
            recipe.folderID = nil
        }
        guard onSaveRecipe(recipe) else { return }
        pendingRecipeCreate = nil
        messages.append(ChatMessage(role: "assistant", content: "Done — I added **\(recipe.title.isEmpty ? "the new recipe" : recipe.title)** to your cookbook."))
        saveConversation()
    }

    private func decline(_ proposal: RecipeCreateProposal) {
        pendingRecipeCreate = nil
        messages.append(ChatMessage(role: "assistant", content: "No problem — **\(proposal.title)** was not added."))
        saveConversation()
    }

    private var selectedModel: GroqModel { GroqModel(rawValue: selectedModelRaw) ?? .gptOSS120B }

    private var keyStorageDescription: String {
#if os(macOS) || targetEnvironment(macCatalyst)
        "Key stored in CookOut's private app storage"
#else
        "Key stored in this device's Keychain"
#endif
    }
}

private struct ChatBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: ChatMessage
    var body: some View {
        HStack(alignment: .top) {
            if message.role == "user" { Spacer(minLength: 35) }
            VStack(alignment: .leading, spacing: 12) {
                Label(message.role == "user" ? "You" : "CookAssistant", systemImage: message.role == "user" ? "person" : "sparkles")
                    .font(.caption.weight(.medium)).opacity(0.75)
                Text(markdown).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(22)
                .background(message.role == "user" ? CookOutTheme.olive : CookOutTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(CookOutTheme.border(for: colorScheme)) }
                .foregroundStyle(message.role == "user" ? .white : .primary)
            if message.role != "user" { Spacer(minLength: 35) }
        }
    }

    private var markdown: AttributedString {
        (try? AttributedString(markdown: message.content)) ?? AttributedString(message.content)
    }
}
