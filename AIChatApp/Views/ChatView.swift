import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private enum ConversationArchiveHintPhase {
    case hidden
    case source
    case sidebar
}

enum ChatChrome {
    static let canvas = adaptive(
        light: UIColor(red: 0.948, green: 0.950, blue: 0.925, alpha: 1),
        dark: UIColor(red: 0.070, green: 0.078, blue: 0.075, alpha: 1)
    )
    static let surface = adaptive(
        light: UIColor(red: 0.992, green: 0.992, blue: 0.974, alpha: 1),
        dark: UIColor(red: 0.118, green: 0.126, blue: 0.121, alpha: 1)
    )
    static let surfaceMuted = adaptive(
        light: UIColor(red: 0.925, green: 0.931, blue: 0.900, alpha: 1),
        dark: UIColor(red: 0.155, green: 0.165, blue: 0.158, alpha: 1)
    )
    static let field = adaptive(
        light: UIColor(red: 1, green: 1, blue: 0.992, alpha: 1),
        dark: UIColor(red: 0.095, green: 0.102, blue: 0.100, alpha: 1)
    )
    static let ink = adaptive(
        light: UIColor(red: 0.090, green: 0.105, blue: 0.105, alpha: 1),
        dark: UIColor(red: 0.930, green: 0.935, blue: 0.915, alpha: 1)
    )
    static let line = Color.primary.opacity(0.10)
    static let softLine = Color.primary.opacity(0.06)
    static let shadow = Color.black.opacity(0.09)
    static let glassShadow = Color.black.opacity(0.12)
    static let warmAccent = Color(red: 0.70, green: 0.43, blue: 0.24)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

struct ChatView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var assistants: AssistantStore
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = ChatViewModel()
    @State private var showingSettings = false
    @State private var showingModelPicker = false
    @State private var showingSidebar = false
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var showingAssistantPicker = false
    @State private var showingQuickPhrases = false
    @State private var exportFile: ConversationExportFile?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var archiveHintPhase: ConversationArchiveHintPhase = .hidden
    @State private var highlightedConversationID: UUID?
    @State private var archiveHintTask: Task<Void, Never>?
    @Namespace private var archiveHintNamespace
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let safeTop = geometry.safeAreaInsets.top
                let safeBottom = min(max(geometry.safeAreaInsets.bottom, 6), 20)
                let sidebarWidth = min(340, geometry.size.width * 0.86)

                ZStack(alignment: .leading) {
                    backgroundLayer

                    VStack(spacing: 0) {
                        messageList
                            .safeAreaInset(edge: .top) {
                                header(safeTop: safeTop)
                            }
                            .safeAreaInset(edge: .bottom) {
                                inputBar(bottomInset: safeBottom)
                            }
                    }
                    .allowsHitTesting(!showingSidebar)

                    statusBarScrim(safeTop: safeTop)

                    if showingSidebar {
                        Color.black
                            .opacity(0.24)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture {
                                dismissKeyboard()
                                hideSidebar()
                            }
                    }

                    sidebar(
                        width: sidebarWidth,
                        safeTop: safeTop,
                        safeBottom: safeBottom
                    )
                    .offset(x: showingSidebar ? 0 : -sidebarWidth - 24)
                    .allowsHitTesting(showingSidebar)
                    .accessibilityHidden(!showingSidebar)
                    .zIndex(showingSidebar ? 2 : -1)
                }
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                        .environmentObject(settings)
                        .environmentObject(assistants)
                        .presentationDragIndicator(.visible)
                        .preferredColorScheme(preferredColorScheme)
                }
                .sheet(isPresented: $showingAssistantPicker) {
                    AssistantPickerSheet()
                        .environmentObject(assistants)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .preferredColorScheme(preferredColorScheme)
                }
                .sheet(isPresented: $showingQuickPhrases) {
                    QuickPhrasePickerSheet(phrases: assistants.currentAssistant.quickPhrases) { phrase in
                        insertQuickPhrase(phrase)
                    }
                    .environmentObject(assistants)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .preferredColorScheme(preferredColorScheme)
                }
                .sheet(isPresented: $showingModelPicker) {
                    ChatModelPickerSheet(
                        models: inputModelOptions,
                        currentModel: activeModel
                    ) { model in
                        activateModel(model)
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .preferredColorScheme(preferredColorScheme)
                }
                .sheet(item: $exportFile) { file in
                    ActivityShareSheet(activityItems: [file.url])
                }
                .photosPicker(
                    isPresented: $showingPhotoPicker,
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 8,
                    matching: .images
                )
                .fileImporter(
                    isPresented: $showingFileImporter,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: true,
                    onCompletion: handleFileImport
                )
                .onChange(of: selectedPhotoItems) { _, items in
                    guard !items.isEmpty else {
                        return
                    }

                    Task {
                        await importPhotoItems(items)
                    }
                }
                .onDisappear {
                    archiveHintTask?.cancel()
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showingSidebar)
                .animation(.spring(response: 0.36, dampingFraction: 0.88), value: archiveHintPhase)
                .animation(.spring(response: 0.38, dampingFraction: 0.9), value: highlightedConversationID)
            }
        }
    }

    private var backgroundLayer: some View {
        ChatChrome.canvas
            .ignoresSafeArea()
            .onTapGesture {
                dismissKeyboard()
            }
    }

    /// Preferred scheme for presented sheets. `.preferredColorScheme` set on the
    /// root view does not propagate into `.sheet` content (sheets present in their
    /// own context), so the chosen mode must be reapplied per sheet.
    private var preferredColorScheme: ColorScheme? {
        switch settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Top safe-area extension that keeps system indicators legible while
    /// messages scroll underneath. iOS 26 uses the system background extension
    /// effect; earlier versions keep the existing material fallback.
    @ViewBuilder
    private func statusBarScrim(safeTop: CGFloat) -> some View {
        let gradientMask = LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.85), location: 0.55),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        if #available(iOS 26.0, *) {
            Rectangle()
                .fill(ChatChrome.canvas.opacity(colorScheme == .dark ? 0.78 : 0.34))
                .backgroundExtensionEffect()
                .mask(gradientMask)
                .frame(height: max(safeTop, 20) + 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    ChatChrome.canvas
                        .opacity(colorScheme == .dark ? 0.92 : 0.28)
                )
                .mask(gradientMask)
                .frame(height: max(safeTop, 20) + 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }

    private func header(safeTop: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                toolbarButton(
                    systemImage: showingSidebar ? "xmark" : "sidebar.left",
                    accessibilityLabel: showingSidebar ? "关闭侧栏" : "打开侧栏"
                ) {
                    dismissKeyboard()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        showingSidebar.toggle()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 对话")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ChatChrome.ink)
                        .lineLimit(1)

                    providerSwitcher
                }

                Spacer(minLength: 8)

                toolbarButton(
                    systemImage: "person.crop.circle",
                    accessibilityLabel: "切换助手"
                ) {
                    dismissKeyboard()
                    showingAssistantPicker = true
                }

                toolbarButton(
                    systemImage: "square.and.pencil",
                    accessibilityLabel: "新建对话",
                    emphasized: true,
                    isDisabled: viewModel.isSending
                ) {
                    createConversation()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .liquidGlass(cornerRadius: 26, shadowRadius: 18, shadowY: 8)
            .padding(.horizontal, 12)

            if archiveHintPhase == .source {
                archiveHintLabel
                    .matchedGeometryEffect(id: "archiveHint", in: archiveHintNamespace)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .padding(.horizontal, 18)
            }
        }
        .padding(.top, max(4, safeTop - 44))
        .padding(.bottom, 8)
        .liquidGlassContainer(spacing: 14)
    }

    /// Status line under the title. With multiple providers it becomes a menu
    /// that switches the active provider; with one it's a plain label.
    @ViewBuilder
    private var providerSwitcher: some View {
        let hasChoices = settings.providers.count > 1

        if hasChoices {
            Menu {
                Picker("供应商", selection: providerSelection) {
                    ForEach(settings.providers) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }
            } label: {
                providerSwitcherLabel(showsChevron: true)
            }
        } else {
            providerSwitcherLabel(showsChevron: false)
        }
    }

    private func providerSwitcherLabel(showsChevron: Bool) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(viewModel.isSending ? ChatChrome.warmAccent : Color.accentColor)
                .frame(width: 7, height: 7)

            Text(providerStatusText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var providerStatusText: String {
        let provider = settings.activeProvider
        let model = provider.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.providers.count > 1 {
            return model.isEmpty ? provider.name : "\(provider.name) · \(model)"
        }
        return model.isEmpty ? provider.name : model
    }

    private var providerSelection: Binding<UUID> {
        Binding(
            get: { settings.activeProviderID },
            set: { settings.setActiveProvider($0) }
        )
    }

    private var archiveHintLabel: some View {
        Label("之前对话已归档", systemImage: "tray.full")
            .font(.caption.weight(.semibold))
            .foregroundStyle(ChatChrome.ink)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .liquidGlass(shape: Capsule(style: .continuous), shadowRadius: 12, shadowY: 6)
    }

    private func toolbarButton(
        systemImage: String,
        accessibilityLabel: String,
        emphasized: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(emphasized ? Color.accentColor : ChatChrome.ink)
                .frame(width: 44, height: 44)
                .liquidGlass(
                    cornerRadius: 22,
                    tint: emphasized ? .accent : .none,
                    interactive: true,
                    shadowRadius: 14,
                    shadowY: 7
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubble(
                            message: message,
                            conversationTitle: viewModel.selectedConversationTitle,
                            isStreaming: viewModel.isSending && message.id == viewModel.messages.last?.id,
                            assistantName: assistants.currentAssistant.useAssistantName ? assistants.currentAssistant.name : nil,
                            assistantAvatar: assistants.currentAssistant.useAssistantAvatar ? assistants.currentAssistant.avatar : nil,
                            onDelete: {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    viewModel.deleteMessage(message.id)
                                }
                            },
                            onRegenerate: message.role == .system ? nil : {
                                viewModel.regenerate(messageID: message.id, using: settings, assistant: assistants.currentAssistant)
                            },
                            onEdit: { newContent in
                                viewModel.editMessage(message.id, newContent: newContent)
                            }
                        )
                        .id(message.id)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.red.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.red.opacity(0.18), lineWidth: 1)
                            )
                            .padding(.horizontal, 18)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .simultaneousGesture(
                TapGesture().onEnded {
                    dismissKeyboard()
                }
            )
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(using: proxy)
            }
            .onChange(of: lastMessageLengthBucket) { _, _ in
                guard viewModel.isSending else {
                    return
                }

                scrollToBottom(using: proxy)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("今天从哪一件事开始？")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ChatChrome.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("当前模型")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                Spacer(minLength: 12)

                Image(systemName: "text.bubble")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10))
                    )
            }

            Text(settings.model)
                .font(.callout.weight(.medium))
                .foregroundStyle(ChatChrome.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ChatChrome.surfaceMuted)
                )

            HStack(spacing: 10) {
                statCell(title: "会话", value: "\(viewModel.conversations.count)")
                statCell(title: "温度", value: temperatureText)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 258, alignment: .topLeading)
        .liquidGlass(cornerRadius: 12, shadowRadius: 18, shadowY: 10)
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    private func statCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChatChrome.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ChatChrome.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(ChatChrome.softLine, lineWidth: 1)
        )
    }

    private var temperatureText: String {
        settings.temperature.formatted(.number.precision(.fractionLength(1)))
    }

    private func inputBar(bottomInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.selectedAttachments.isEmpty {
                selectedAttachmentStrip
            }

            // The text field always lives in the same HStack slot so its
            // first-responder identity is preserved. When the keyboard is up
            // the + and send buttons fold into the capsule, left and right.
            HStack(alignment: .center, spacing: 8) {
                if isInputFocused {
                    attachmentButton
                        .transition(.scale.combined(with: .opacity))
                }

                composerField
                    .padding(.horizontal, isInputFocused ? 6 : 18)
                    .padding(.vertical, isInputFocused ? 11 : 12)

                if isInputFocused {
                    sendButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(isInputFocused ? 6 : 0)
            .liquidGlass(
                shape: Capsule(style: .continuous),
                shadowRadius: 18,
                shadowY: 8
            )

            if !isInputFocused {
                HStack(spacing: 10) {
                    attachmentButton

                    modelSelectorChip

                    if !assistants.currentAssistant.quickPhrases.isEmpty {
                        quickPhraseButton
                    }

                    Spacer(minLength: 8)

                    sendButton
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.24), value: isInputFocused)
        .animation(.easeInOut(duration: 0.22), value: viewModel.selectedAttachments)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, max(bottomInset - 14, 2))
        .liquidGlassContainer(spacing: 12)
    }

    private var composerField: some View {
        TextField("输入消息", text: $viewModel.draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(1...5)
            .submitLabel(.send)
            .focused($isInputFocused)
            .disabled(viewModel.isSending)
            .onSubmit {
                viewModel.send(using: settings, assistant: assistants.currentAssistant)
            }
    }

    private var sendButton: some View {
        Button {
            if viewModel.isSending {
                viewModel.cancel()
            } else {
                viewModel.send(using: settings, assistant: assistants.currentAssistant)
            }
        } label: {
            Image(systemName: viewModel.isSending ? "stop.fill" : "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(viewModel.isSending ? ChatChrome.ink : .white)
                .frame(width: 42, height: 42)
                .liquidGlass(
                    shape: Circle(),
                    tint: viewModel.isSending ? .custom(ChatChrome.surfaceMuted.opacity(0.42)) : .accent,
                    interactive: true,
                    shadowRadius: 12,
                    shadowY: 5
                )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isSending && !viewModel.canSend)
        .opacity(!viewModel.isSending && !viewModel.canSend ? 0.45 : 1)
        .accessibilityLabel(viewModel.isSending ? "停止" : "发送")
    }

    private var selectedAttachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.selectedAttachments) { attachment in
                    AttachmentPreview(attachment: attachment, variant: .composer) {
                        viewModel.removeSelectedAttachment(attachment)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var attachmentButton: some View {
        Menu {
            Button {
                dismissKeyboard()
                showingPhotoPicker = true
            } label: {
                Label("选择图片", systemImage: "photo.on.rectangle")
            }

            Button {
                dismissKeyboard()
                showingFileImporter = true
            } label: {
                Label("选择文件", systemImage: "doc")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(ChatChrome.ink)
                .frame(width: 42, height: 42)
                .liquidGlass(
                    shape: Circle(),
                    tint: .custom(ChatChrome.surfaceMuted.opacity(0.32)),
                    interactive: true,
                    shadowRadius: 12,
                    shadowY: 5
                )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(viewModel.isSending)
        .opacity(viewModel.isSending ? 0.45 : 1)
        .accessibilityLabel("添加附件")
    }

    private var quickPhraseButton: some View {
        Button {
            dismissKeyboard()
            showingQuickPhrases = true
        } label: {
            Image(systemName: "bolt.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ChatChrome.ink)
                .frame(width: 42, height: 42)
                .liquidGlass(
                    shape: Circle(),
                    tint: .custom(ChatChrome.surfaceMuted.opacity(0.32)),
                    interactive: true,
                    shadowRadius: 12,
                    shadowY: 5
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSending)
        .opacity(viewModel.isSending ? 0.45 : 1)
        .accessibilityLabel("快捷短语")
    }

    private func insertQuickPhrase(_ phrase: QuickPhrase) {
        if viewModel.draft.isEmpty {
            viewModel.draft = phrase.content
        } else {
            viewModel.draft += phrase.content
        }
    }

    private func brandIconName(for model: String) -> String? {
        let lowered = model.lowercased()
        if lowered.contains("claude") || lowered.contains("anthropic") {
            return "brand-claude"
        } else if lowered.contains("gemini") {
            return "brand-gemini"
        } else if lowered.contains("gpt") || lowered.contains("openai") || lowered.contains("o1") || lowered.contains("o3") || lowered.contains("o4") {
            return "brand-openai"
        } else if lowered.contains("deepseek") {
            return "brand-deepseek"
        } else if lowered.contains("grok") {
            return "brand-grok"
        } else if lowered.contains("llama") {
            return "brand-llama"
        } else if lowered.contains("mistral") {
            return "brand-mistral"
        } else if lowered.contains("qwen") {
            return "brand-qwen"
        } else if lowered.contains("perplexity") || lowered.contains("pplx") {
            return "brand-perplexity"
        } else if lowered.contains("huggingface") || lowered.contains("hf") {
            return "brand-huggingface"
        } else if lowered.contains("ollama") {
            return "brand-ollama"
        } else if lowered.contains("alibaba") || lowered.contains("ali") {
            return "brand-alibaba"
        }
        return nil
    }

    @ViewBuilder
    private func modelIcon(for model: String, size: CGFloat = 16) -> some View {
        if let assetName = brandIconName(for: model) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "cpu")
                .font(.system(size: size - 2, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var modelSelectorChip: some View {
        Button {
            openModelPicker()
        } label: {
            HStack(spacing: 8) {
                modelIcon(for: activeModel, size: 18)

                Text(activeModel.isEmpty ? "未设置模型" : activeModel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if inputModelOptions.count > 1 {
                    Text("\(inputModelOptions.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ChatChrome.surfaceMuted))
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .liquidGlass(
                shape: Capsule(style: .continuous),
                interactive: true,
                shadowRadius: 14,
                shadowY: 6
            )
        }
        .buttonStyle(.plain)
        .disabled(inputModelOptions.isEmpty)
        .opacity(inputModelOptions.isEmpty ? 0.5 : 1)
        .accessibilityLabel("选择模型")
    }

    private var activeModel: String {
        settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var inputModelOptions: [String] {
        SettingsStore.normalizedModelList(settings.selectedModels, ensuring: settings.model)
    }

    private func activateModel(_ item: String) {
        let normalizedModel = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty, normalizedModel != activeModel else {
            return
        }

        settings.model = normalizedModel
        settings.save()
        dismissKeyboard()
    }

    private func openModelPicker() {
        guard !inputModelOptions.isEmpty else {
            return
        }

        dismissKeyboard()
        showingModelPicker = true
    }

    private func sidebar(width: CGFloat, safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        VStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("对话记录")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ChatChrome.ink)

                    Text("\(viewModel.conversations.count) 个会话")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 14)

                if archiveHintPhase == .sidebar {
                    archiveHintLabel
                        .matchedGeometryEffect(id: "archiveHint", in: archiveHintNamespace)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.conversations) { conversation in
                            SwipeActionConversationRow(
                                conversation: conversation,
                                isSelected: conversation.id == viewModel.selectedConversationID,
                                isHighlighted: conversation.id == highlightedConversationID,
                                isDisabled: viewModel.isSending
                            ) {
                                viewModel.selectConversation(conversation.id)
                                hideSidebar()
                            } onExport: {
                                exportConversation(conversation)
                            } onDelete: {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    highlightedConversationID = nil
                                    archiveHintPhase = .hidden
                                    viewModel.deleteConversation(conversation.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.hidden)

                Rectangle()
                    .fill(ChatChrome.line)
                    .frame(height: 1)
                    .padding(.horizontal, 14)

                Button {
                    dismissKeyboard()
                    hideSidebar()
                    showingSettings = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 24)

                        Text("设置")
                            .font(.body.weight(.semibold))

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(ChatChrome.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .liquidGlass(
                        cornerRadius: 10,
                        tint: .custom(ChatChrome.surfaceMuted.opacity(0.32)),
                        interactive: true,
                        fallbackFill: ChatChrome.surfaceMuted,
                        fallbackStroke: ChatChrome.softLine,
                        shadowRadius: 8,
                        shadowY: 4
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            .frame(width: width, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .liquidGlass(cornerRadius: 16, shadowRadius: 22, shadowY: 12)
            .padding(.top, safeTop + 8)
            .padding(.bottom, safeBottom)
            .padding(.leading, 12)
            .padding(.trailing, 14)
        }
        .liquidGlassContainer(spacing: 18)
    }

    private func createConversation() {
        dismissKeyboard()

        let previousConversationID = viewModel.selectedConversationID
        let hadMessages = !viewModel.messages.isEmpty

        archiveHintTask?.cancel()

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            viewModel.startNewConversation()
            showingSidebar = true
        }

        guard hadMessages else {
            archiveHintPhase = .hidden
            highlightedConversationID = nil
            return
        }

        highlightedConversationID = previousConversationID
        archiveHintPhase = .source

        archiveHintTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                archiveHintPhase = .sidebar
            }

            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeOut(duration: 0.24)) {
                archiveHintPhase = .hidden
                highlightedConversationID = nil
            }
        }
    }

    private func hideSidebar() {
        dismissKeyboard()

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            showingSidebar = false
        }
    }

    private var lastMessageLengthBucket: Int {
        let contentCount = viewModel.messages.last?.content.count ?? 0
        return contentCount / 48
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        guard let lastID = viewModel.messages.last?.id else {
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    @MainActor
    private func importPhotoItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                continue
            }

            let type = item.supportedContentTypes.first { $0.conforms(to: .image) }
            let fileExtension = type?.preferredFilenameExtension ?? "jpg"
            let mimeType = type?.preferredMIMEType
            viewModel.attachImage(
                data: data,
                suggestedFilename: "image-\(UUID().uuidString).\(fileExtension)",
                mimeType: mimeType
            )
        }

        selectedPhotoItems = []
    }

    private func exportConversation(_ conversation: Conversation) {
        do {
            exportFile = ConversationExportFile(url: try viewModel.markdownExportFile(for: conversation))
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            urls.forEach { url in
                viewModel.attachImportedFile(from: url)
            }
        case let .failure(error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

private struct ConversationExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct SwipeActionConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let isHighlighted: Bool
    let isDisabled: Bool
    let onSelect: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    @State private var rowOffset: CGFloat = 0
    @GestureState private var dragTranslation: CGFloat = 0

    private let actionWidth: CGFloat = 74
    private let actionSpacing: CGFloat = 6

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: actionSpacing) {
                Button {
                    closeRow()
                    onExport()
                } label: {
                    actionLabel(title: "导出", systemImage: "square.and.arrow.up")
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .frame(width: actionWidth)
                .opacity(revealedWidth > actionWidth * 0.55 ? 1 : 0)

                Button(role: .destructive) {
                    closeRow()
                    onDelete()
                } label: {
                    actionLabel(title: "删除", systemImage: "trash")
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.red)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .frame(width: actionWidth)
                .opacity(revealedWidth > revealWidth - actionWidth * 0.45 ? 1 : 0)
            }
            .frame(width: revealWidth, alignment: .trailing)
            .frame(width: revealedWidth, alignment: .trailing)
            .clipped()
            .allowsHitTesting(rowOffset <= -revealWidth * 0.95 && !isDisabled)

            ConversationRow(
                conversation: conversation,
                isSelected: isSelected,
                isHighlighted: isHighlighted
            )
            .contentShape(Rectangle())
            .offset(x: effectiveOffset)
            .highPriorityGesture(
                TapGesture().onEnded {
                    selectOrClose()
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .updating($dragTranslation) { value, state, _ in
                        guard abs(value.translation.width) > abs(value.translation.height) else {
                            return
                        }

                        state = value.translation.width
                    }
                    .onEnded { value in
                        guard !isDisabled,
                              abs(value.translation.width) > abs(value.translation.height) else {
                            return
                        }

                        let proposedOffset = clampedOffset(rowOffset + value.translation.width)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            rowOffset = proposedOffset < -(revealWidth * 0.34) ? -revealWidth : 0
                        }
                    }
            )
        }
        .clipped()
        .opacity(isDisabled ? 0.58 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: effectiveOffset)
    }

    private var effectiveOffset: CGFloat {
        clampedOffset(rowOffset + dragTranslation)
    }

    private var revealedWidth: CGFloat {
        min(revealWidth, max(0, -effectiveOffset))
    }

    private var revealWidth: CGFloat {
        actionWidth * 2 + actionSpacing
    }

    private func actionLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))

            Text(title)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.white)
        .frame(width: actionWidth)
        .frame(maxHeight: .infinity)
    }

    private func clampedOffset(_ value: CGFloat) -> CGFloat {
        min(0, max(-revealWidth, value))
    }

    private func closeRow() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            rowOffset = 0
        }
    }

    private func selectOrClose() {
        guard !isDisabled else {
            return
        }

        if rowOffset < 0 {
            closeRow()
        } else {
            onSelect()
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(conversation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(conversation.updatedAt, format: .dateTime.month().day())

                    Circle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 3, height: 3)

                    Text("\(messageCount) 条")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            } else if isHighlighted {
                Image(systemName: "tray.full")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ChatChrome.warmAccent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected || isHighlighted ? 1 : 0)
        )
        .scaleEffect(isHighlighted ? 1.015 : 1)
    }

    private var messageCount: Int {
        conversation.messages.filter { $0.role != .system }.count
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }

        if isHighlighted {
            return ChatChrome.warmAccent.opacity(0.12)
        }

        return ChatChrome.field
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.34)
        }

        if isHighlighted {
            return ChatChrome.warmAccent.opacity(0.36)
        }

        return .clear
    }
}

private struct ChatModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let models: [String]
    let currentModel: String
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                ChatChrome.canvas
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("选择模型")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ChatChrome.ink)

                        Text("上下滑动列表，点一下立即切换")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(models, id: \.self) { item in
                                modelRow(item)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func pickerBrandIcon(for model: String, size: CGFloat = 20) -> some View {
        let lowered = model.lowercased()
        let assetName: String? = {
            if lowered.contains("claude") || lowered.contains("anthropic") { return "brand-claude" }
            if lowered.contains("gemini") { return "brand-gemini" }
            if lowered.contains("gpt") || lowered.contains("openai") || lowered.contains("o1") || lowered.contains("o3") || lowered.contains("o4") { return "brand-openai" }
            if lowered.contains("deepseek") { return "brand-deepseek" }
            if lowered.contains("grok") { return "brand-grok" }
            if lowered.contains("llama") { return "brand-llama" }
            if lowered.contains("mistral") { return "brand-mistral" }
            if lowered.contains("qwen") { return "brand-qwen" }
            if lowered.contains("perplexity") || lowered.contains("pplx") { return "brand-perplexity" }
            if lowered.contains("huggingface") || lowered.contains("hf") { return "brand-huggingface" }
            if lowered.contains("ollama") { return "brand-ollama" }
            if lowered.contains("alibaba") || lowered.contains("ali") { return "brand-alibaba" }
            return nil
        }()

        return Group {
            if let name = assetName {
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: size - 2, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modelRow(_ item: String) -> some View {
        let isActive = item == currentModel

        return Button {
            onSelect(item)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                pickerBrandIcon(for: item, size: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChatChrome.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(isActive ? "当前使用中" : "点按切换到这个模型")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isActive {
                    Text("当前")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(
                cornerRadius: 12,
                tint: isActive ? .accent : .none,
                interactive: true,
                shadowRadius: 10,
                shadowY: 5
            )
        }
        .buttonStyle(.plain)
    }
}
