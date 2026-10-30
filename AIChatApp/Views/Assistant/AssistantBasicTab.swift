import SwiftUI
import PhotosUI

/// 基础设置标签:头像、名称、采样参数、上下文、模型、背景等。
struct AssistantBasicTab: View {
    @Binding var assistant: Assistant
    @EnvironmentObject private var settings: SettingsStore

    @State private var showingEmojiSheet = false
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var backgroundPickerItem: PhotosPickerItem?
    @State private var showingModelPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                identityCard
                parameterCard
                modelCard
                backgroundCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .liquidGlassContainer(spacing: 18)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showingEmojiSheet) {
            EmojiPickerSheet { emoji in
                AssistantImageStore.removeIfLocal(assistant.avatar)
                assistant.avatar = emoji
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: avatarPickerItem) { _, item in
            guard let item else { return }
            Task { await loadAvatar(item) }
        }
        .onChange(of: backgroundPickerItem) { _, item in
            guard let item else { return }
            Task { await loadBackground(item) }
        }
    }

    // MARK: - 身份卡片(头像 + 名称)

    private var identityCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                AssistantAvatarView(avatar: assistant.avatar, name: assistant.name, size: 72)

                HStack(spacing: 10) {
                    Menu {
                        Button {
                            showingEmojiSheet = true
                        } label: {
                            Label("使用 Emoji", systemImage: "face.smiling")
                        }
                        if assistant.avatar != nil {
                            Button(role: .destructive) {
                                AssistantImageStore.removeIfLocal(assistant.avatar)
                                assistant.avatar = nil
                            } label: {
                                Label("移除头像", systemImage: "trash")
                            }
                        }
                    } label: {
                        Text("Emoji")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .liquidGlass(shape: Capsule(), fallbackFill: ChatChrome.field, shadowRadius: 0, shadowY: 0)
                    }

                    PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                        Text("从相册")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .liquidGlass(shape: Capsule(), fallbackFill: ChatChrome.field, shadowRadius: 0, shadowY: 0)
                    }
                }
            }

            SettingsField(title: "助手名称", symbol: "tag") {
                TextField("给助手起个名字", text: $assistant.name)
                    .settingsInputStyle()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 16, shadowRadius: 14, shadowY: 8)
    }

    // MARK: - 参数卡片

    private var parameterCard: some View {
        VStack(spacing: 14) {
            OptionalDoubleParameterRow(
                title: "温度",
                symbol: "thermometer.medium",
                value: $assistant.temperature,
                range: 0...2,
                defaultOnEnable: 0.6,
                description: "控制随机性,越高越发散。关闭则不下发该参数。"
            )
            divider
            OptionalDoubleParameterRow(
                title: "Top P",
                symbol: "wand.and.stars",
                value: $assistant.topP,
                range: 0...1,
                defaultOnEnable: 1.0,
                description: "核采样阈值。关闭则不下发该参数。"
            )
            divider
            contextRow
            divider
            maxTokensRow
            divider
            toggleRow(title: "使用助手头像", symbol: "person.crop.circle", isOn: $assistant.useAssistantAvatar)
            divider
            toggleRow(title: "使用助手名称", symbol: "textformat", isOn: $assistant.useAssistantName)
            divider
            toggleRow(title: "流式输出", symbol: "bolt.horizontal", isOn: $assistant.streamOutput)
        }
        .padding(16)
        .liquidGlass(cornerRadius: 12, shadowRadius: 14, shadowY: 8)
    }

    private var contextRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("上下文消息数", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
                Spacer()
                Toggle("", isOn: $assistant.limitContextMessages)
                    .labelsHidden()
                    .tint(Color.accentColor)
            }

            if assistant.limitContextMessages {
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(assistant.contextMessageSize) },
                            set: { assistant.contextMessageSize = Int($0) }
                        ),
                        in: Double(Assistant.minContextMessageSize)...Double(Assistant.maxContextMessageSize),
                        step: 1
                    )
                    .tint(Color.accentColor)

                    Text("\(assistant.contextMessageSize)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, alignment: .trailing)
                }

                Text("携带最近 \(assistant.contextMessageSize) 条消息作为上下文。")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("不限制,发送全部历史消息。")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var maxTokensRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("最大 Token 数", systemImage: "number")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { assistant.maxTokens != nil },
                    set: { on in assistant.maxTokens = on ? 2048 : nil }
                ))
                .labelsHidden()
                .tint(Color.accentColor)
            }

            if let tokens = assistant.maxTokens {
                TextField("不限制", text: Binding(
                    get: { String(tokens) },
                    set: { assistant.maxTokens = Int($0.filter(\.isNumber)) }
                ))
                .keyboardType(.numberPad)
                .settingsInputStyle()

                Text("限制单次回复的最大 token 数。")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("不限制回复长度。")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleRow(title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChatChrome.ink)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.accentColor)
        }
    }

    // MARK: - 模型卡片

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("聊天模型", systemImage: "cpu")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
                Spacer()
                if assistant.chatModelId != nil {
                    Button {
                        assistant.chatModelId = nil
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("恢复默认模型")
                }
            }

            Button {
                showingModelPicker = true
            } label: {
                HStack(spacing: 10) {
                    Text(assistant.chatModelId ?? "使用供应商默认模型")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(assistant.chatModelId == nil ? .secondary : ChatChrome.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 10, interactive: true, fallbackFill: ChatChrome.field, shadowRadius: 0, shadowY: 0)
            }
            .buttonStyle(.plain)

            Text("不设置时跟随聊天界面当前选择的模型。")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16, shadowRadius: 14, shadowY: 8)
        .sheet(isPresented: $showingModelPicker) {
            AssistantModelPickerSheet(
                models: modelOptions,
                current: assistant.chatModelId
            ) { picked in
                assistant.chatModelId = picked
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var modelOptions: [String] {
        SettingsStore.normalizedModelList(settings.selectedModels, ensuring: settings.model)
    }

    // MARK: - 背景卡片

    private var backgroundCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("聊天背景", systemImage: "photo")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChatChrome.ink)

            HStack(spacing: 10) {
                PhotosPicker(selection: $backgroundPickerItem, matching: .images) {
                    Text(assistant.background == nil ? "选择图片" : "更换图片")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .liquidGlass(cornerRadius: 10, fallbackFill: ChatChrome.field, shadowRadius: 0, shadowY: 0)
                }

                if assistant.background != nil {
                    Button {
                        AssistantImageStore.removeIfLocal(assistant.background)
                        assistant.background = nil
                    } label: {
                        Text("清除")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .liquidGlass(cornerRadius: 10, fallbackFill: ChatChrome.field, shadowRadius: 0, shadowY: 0)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let background = assistant.background,
               AssistantImageStore.isLocalFile(background),
               let image = loadImage(background) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 12, shadowRadius: 14, shadowY: 8)
    }

    private var divider: some View {
        Rectangle().fill(ChatChrome.softLine).frame(height: 1)
    }

    // MARK: - 图片加载

    private func loadAvatar(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let filename = AssistantImageStore.save(imageData: data) else { return }
        await MainActor.run {
            AssistantImageStore.removeIfLocal(assistant.avatar)
            assistant.avatar = filename
            avatarPickerItem = nil
        }
    }

    private func loadBackground(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let filename = AssistantImageStore.save(imageData: data) else { return }
        await MainActor.run {
            AssistantImageStore.removeIfLocal(assistant.background)
            assistant.background = filename
            backgroundPickerItem = nil
        }
    }

    private func loadImage(_ filename: String) -> UIImage? {
        let url = AssistantImageStore.url(forFilename: filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

/// 可开关的浮点参数行(温度 / Top P)。关闭时值为 nil。
struct OptionalDoubleParameterRow: View {
    let title: String
    let symbol: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let defaultOnEnable: Double
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { value != nil },
                    set: { on in value = on ? defaultOnEnable : nil }
                ))
                .labelsHidden()
                .tint(Color.accentColor)
            }

            if let current = value {
                HStack {
                    Slider(
                        value: Binding(
                            get: { current },
                            set: { value = $0 }
                        ),
                        in: range,
                        step: 0.05
                    )
                    .tint(Color.accentColor)

                    Text(current, format: .number.precision(.fractionLength(2)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
            }

            Text(description)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
