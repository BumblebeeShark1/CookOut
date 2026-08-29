import SwiftUI

struct CookingChatView: View {
    @Environment(\.cookOutPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let cookbook: [CookingNote]
    @State private var messages: [ChatMessage] = []
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
                else { conversation }
            }
            .navigationTitle("CookOut Sous Chef")
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
                            Button("Clear conversation", systemImage: "trash") { messages.removeAll(); errorMessage = nil }
                            Button("Replace API key", systemImage: "key") { keyInput = ""; showingKeySettings = true }
                            Button("Remove API key", systemImage: "key.slash", role: .destructive) { GroqKeychain.delete(); hasKey = false }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .sheet(isPresented: $showingKeySettings) { keyEditor }
        }
    }

    private var keySetup: some View {
        ZStack {
            ZStack { palette.background(for: colorScheme); palette.softGradient }.ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(palette.gradient).frame(width: 96, height: 96)
                    Image(systemName: "chef.hat.fill").font(.system(size: 42)).foregroundStyle(.white)
                }
                VStack(spacing: 8) {
                    Text("Meet your Sous Chef").font(.largeTitle.bold())
                    Text("Recipe ideas, substitutions, troubleshooting, and meal inspiration—right in your cookbook.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    setupBenefit("sparkles", "Creative cooking help")
                    setupBenefit("book.closed.fill", "Understands your saved recipes")
                    setupBenefit("lock.shield.fill", "Key stored in this device's Keychain")
                }
                Button { keyError = nil; showingKeySettings = true } label: {
                    Label("Connect to Groq", systemImage: "bolt.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
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
                Text("• Groq Cloud").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal).padding(.vertical, 8).background(CookOutTheme.mint.opacity(0.10))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if messages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "chef.hat.fill").font(.system(size: 46)).foregroundStyle(CookOutTheme.orange)
                                Text("What are we cooking?").font(.title2.bold())
                                Text("Ask about a recipe, substitution, technique, or what to cook.").multilineTextAlignment(.center).foregroundStyle(.secondary)
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
        .background { ZStack { palette.background(for: colorScheme); palette.softGradient } }
    }

    private var promptChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                quickPrompt("clock.fill", "30-minute meal", CookOutTheme.orange, "What can I cook in 30 minutes?")
                quickPrompt("wand.and.sparkles", "Improve a recipe", CookOutTheme.berry, "Help me improve one of my recipes")
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
                Section("Groq API key") {
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
                _ = try await service.reply(to: [ChatMessage(role: "user", content: "Reply with OK only.")], cookbook: [], apiKey: key, model: selectedModel)
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
        isSending = true
        Task {
            do { messages.append(ChatMessage(role: "assistant", content: try await service.reply(to: messages, cookbook: cookbook, model: selectedModel))) }
            catch { errorMessage = error.localizedDescription }
            isSending = false
        }
    }

    private func retryLastRequest() {
        guard !isSending, messages.last?.role == "user" else { return }
        errorMessage = nil; isSending = true
        Task {
            do { messages.append(ChatMessage(role: "assistant", content: try await service.reply(to: messages, cookbook: cookbook, model: selectedModel))) }
            catch { errorMessage = error.localizedDescription }
            isSending = false
        }
    }

    private var selectedModel: GroqModel { GroqModel(rawValue: selectedModelRaw) ?? .gptOSS120B }
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
