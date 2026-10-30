import SwiftUI

/// 提示词标签:系统提示词(含变量)、消息模板(含变量)、预设对话消息。
struct AssistantPromptTab: View {
    @Binding var assistant: Assistant

    @State private var editingPreset: PresetMessage?
    @State private var newPresetRole: ChatMessage.Role = .user
    @State private var showingPresetEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                systemPromptCard
                messageTemplateCard
                presetCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .liquidGlassContainer(spacing: 18)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showingPresetEditor) {
            PresetMessageEditor(
                role: editingPreset?.role ?? newPresetRole,
                content: editingPreset?.content ?? ""
            ) { role, content in
                savePreset(role: role, content: content)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 系统提示词

    private var systemPromptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("系统提示词")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChatChrome.ink)

            TextField("例如:你是一个乐于助人的助手…", text: $assistant.systemPrompt, axis: .vertical)
                .lineLimit(6...14)
                .settingsInputStyle()

            Text("可用变量(点击插入)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowWrap(spacing: 8) {
                ForEach(PromptVariable.allCases, id: \.rawValue) { variable in
                    variableChip(label: variable.label, token: variable.rawValue) {
                        assistant.systemPrompt += variable.rawValue
                    }
                }
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16, shadowRadius: 14, shadowY: 8)
    }

    // MARK: - 消息模板

    private var messageTemplateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("消息模板")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChatChrome.ink)

            TextField("{{ message }}", text: $assistant.messageTemplate, axis: .vertical)
                .lineLimit(2...6)
                .settingsInputStyle()

            Text("每条用户消息发送前会套用此模板。可用变量(点击插入):")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            FlowWrap(spacing: 8) {
                ForEach(MessageTemplateVariable.allCases, id: \.rawValue) { variable in
                    variableChip(label: variable.label, token: variable.rawValue) {
                        assistant.messageTemplate += variable.rawValue
                    }
                }
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16, shadowRadius: 14, shadowY: 8)
    }

    // MARK: - 预设消息

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("预设对话")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
                Spacer()
                Button {
                    editingPreset = nil
                    newPresetRole = .user
                    showingPresetEditor = true
                } label: {
                    Label("用户", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                Button {
                    editingPreset = nil
                    newPresetRole = .assistant
                    showingPresetEditor = true
                } label: {
                    Label("助手", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if assistant.presetMessages.isEmpty {
                Text("添加预设对话,会在每次会话最前面注入。")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assistant.presetMessages) { preset in
                    presetRow(preset)
                }
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16, shadowRadius: 14, shadowY: 8)
    }

    private func presetRow(_ preset: PresetMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: preset.role == .user ? "person.fill" : "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(preset.role == .user ? Color.accentColor : .secondary)
                .frame(width: 22)

            Text(preset.content)
                .font(.caption.weight(.medium))
                .foregroundStyle(ChatChrome.ink)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                editingPreset = preset
                showingPresetEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                assistant.presetMessages.removeAll { $0.id == preset.id }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ChatChrome.field)
        )
    }

    private func variableChip(label: String, token: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.accentColor.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private func savePreset(role: ChatMessage.Role, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let editing = editingPreset,
           let index = assistant.presetMessages.firstIndex(where: { $0.id == editing.id }) {
            assistant.presetMessages[index].content = trimmed
            assistant.presetMessages[index].role = role
        } else {
            assistant.presetMessages.append(PresetMessage(role: role, content: trimmed))
        }
        editingPreset = nil
    }
}

/// 预设消息编辑器。
private struct PresetMessageEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State var role: ChatMessage.Role
    @State var content: String
    let onSave: (ChatMessage.Role, String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                ChatChrome.canvas.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    Picker("角色", selection: $role) {
                        Text("用户").tag(ChatMessage.Role.user)
                        Text("助手").tag(ChatMessage.Role.assistant)
                    }
                    .pickerStyle(.segmented)

                    TextField("输入内容", text: $content, axis: .vertical)
                        .lineLimit(4...12)
                        .settingsInputStyle()

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("预设消息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(role, content)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
