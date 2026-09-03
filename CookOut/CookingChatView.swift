import SwiftUI

struct CookingChatView: View {
    private enum ChatTab: Hashable { case chat, history }

    @Environment(\.cookOutPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let cookbook: [CookingNote]
    let folders: [RecipeFolder]
    let onSaveRecipe: (CookingNote) -> Void
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
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
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
    }

    private var chatTabs: some View {
        TabView(selection: $selectedTab) {
            conversation
                .tabItem { Label("Chat", systemImage: "sparkles") }
                .tag(ChatTab.chat)

            history
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(ChatTab.history)
        }
    }

    private var keySetup: some View {
        ZStack {
            ZStack { palette.background(for: colorScheme); palette.ambientGradient(for: colorScheme) }.ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(palette.gradient).frame(width: 96, height: 96)
                    Image(systemName: "chef.hat.fill").font(.system(size: 42)).foregroundStyle(.white)
                }
                VStack(spacing: 8) {
                    Text("Meet CookAssistant").font(.largeTitle.bold())
                    Text("Recipe ideas, substitutions, troubleshooting, and meal inspiration—right in your cookbook.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    setupBenefit("sparkles", "Creative cooking help")
                    setupBenefit("book.closed.fill", "Understands your saved recipes")
                    setupBenefit("lock.shield.fill", keyStorageDescription)
                }
                Button { keyError = nil; showingKeySettings = true } label: {
                    Label("Connect CookAssistant", systemImage: "bolt.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }.buttonStyle(.borderedProminent).tint(palette.accent)
                Text("Powered by GPT-OSS 120B").font(.caption).foregroundStyle(.tertiary)
            }.padding(28)
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Image(systemName: selectedModel.symbol).foregroundStyle(palette.accent)
                Text(selectedModel.name).font(.caption.weight(.semibold))
                Text("• CookAssistant via Groq").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal).padding(.vertical, 8).background(CookOutTheme.mint.opacity(0.10))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if messages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "chef.hat.fill").font(.system(size: 46)).foregroundStyle(CookOutTheme.orange)
                                Text("What are we cooking?").font(.title2.bold())
                                Text("Ask about a recipe, substitution, technique, what to cook, or tell CookAssistant to add a new recipe.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                                promptChips
                            }.padding(.top, 48)
                        }
                        ForEach(messages) { message in ChatBubble(message: message).id(message.id) }
                        if isSending { HStack { ProgressView(); Text("\(selectedModel.name) is cooking up an answer…") }.foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                        if let errorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("That didn't cook properly", systemImage: "exclamationmark.triangle.fill").font(.subheadline.bold())
                                Text(errorMessage).font(.footnote)
                                Button("Try again", systemImage: "arrow.clockwise") { retryLastRequest() }.font(.footnote.bold())
                            }.foregroundStyle(.red).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }.padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask your cooking question…", text: $input, axis: .vertical)
                    .lineLimit(1...5).focused($inputFocused).submitLabel(.send).onSubmit { send() }
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title).foregroundStyle(CookOutTheme.hero) }
                    .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal).padding(.bottom, 8)
        }
        .background { ZStack { palette.background(for: colorScheme); palette.ambientGradient(for: colorScheme) } }
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
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search conversations", text: $historyQuery)
                    .textFieldStyle(.plain)
                if !historyQuery.isEmpty {
                    Button { historyQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()

            if filteredHistory.isEmpty {
                ContentUnavailableView(
                    historyStore.conversations.isEmpty ? "No conversations yet" : "No matching conversations",
                    systemImage: historyStore.conversations.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass",
                    description: Text(historyStore.conversations.isEmpty ? "Your CookAssistant chats will be saved here automatically." : "Try a different search.")
                )
            } else {
                List {
                    ForEach(filteredHistory) { conversation in
                        Button { open(conversation) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(conversation.title).font(.headline).lineLimit(1)
                                    Spacer()
                                    Text(conversation.updatedAt, format: .relative(presentation: .named))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(conversation.preview)
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                Label(GroqModel(rawValue: conversation.modelRawValue)?.name ?? "CookAssistant", systemImage: "brain.head.profile")
                                    .font(.caption2).foregroundStyle(palette.accent)
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(conversation)
                            }
                        }
                        .contextMenu {
                            Button("Open", systemImage: "bubble.left") { open(conversation) }
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(conversation) }
                        }
                    }
                }
                .listStyle(.plain)

                Button("Delete All History", systemImage: "trash", role: .destructive) {
                    showingClearHistoryConfirmation = true
                }
                .font(.footnote).padding(.bottom, 8)
            }
        }
        .background { ZStack { palette.background(for: colorScheme); palette.ambientGradient(for: colorScheme) } }
    }

    private var promptChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                quickPrompt("clock.fill", "30-minute meal", CookOutTheme.orange, "What can I cook in 30 minutes?")
                quickPrompt("wand.and.sparkles", "Improve a recipe", CookOutTheme.berry, "Help me improve one of my recipes")
                quickPrompt("plus.circle.fill", "Add a recipe", CookOutTheme.coral, "Create and add a new recipe to my cookbook")
                quickPrompt("arrow.triangle.swap", "Substitution", CookOutTheme.mint, "Suggest a smart substitution")
            }
        }.contentMargins(.horizontal, 2)
    }

    private func setupBenefit(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
    }

    private func quickPrompt(_ symbol: String, _ title: String, _ color: Color, _ prompt: String) -> some View {
        Button { input = prompt; send() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.title3).foregroundStyle(color)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }.frame(width: 130, alignment: .leading).padding(12)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }

    private var keyEditor: some View {
        NavigationStack {
            Form {
                Section("CookAssistant connection") {
                    SecureField("gsk_…", text: $keyInput).textContentType(.password)
                }
                if isTestingKey { Section { HStack { ProgressView(); Text("Testing secure connection…") } } }
                if let keyError { Section { Text(keyError).foregroundStyle(.red) } }
                Section { Text("For production, route requests through your own server so no distributable app contains a reusable provider credential.").font(.footnote) }
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
                handle(try await service.reply(to: messages, cookbook: cookbook, folders: folders, model: selectedModel))
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
                handle(try await service.reply(to: messages, cookbook: cookbook, folders: folders, model: selectedModel))
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
        pendingRecipeEdit = nil
        guard let recipe = cookbook.first(where: { $0.id == proposal.recipeID }) else { return }
        let updated = proposal.applying(to: recipe)
        onSaveRecipe(updated)
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
        pendingRecipeCreate = nil
        var recipe = proposal.recipe()
        if let folderID = recipe.folderID, !folders.contains(where: { $0.id == folderID }) {
            recipe.folderID = nil
        }
        onSaveRecipe(recipe)
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
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 50) }
            Text(markdown).textSelection(.enabled).padding(12)
                .background(message.role == "user" ? CookOutTheme.orange : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(message.role == "user" ? .white : .primary)
            if message.role != "user" { Spacer(minLength: 35) }
        }
    }

    private var markdown: AttributedString {
        (try? AttributedString(markdown: message.content)) ?? AttributedString(message.content)
    }
}
