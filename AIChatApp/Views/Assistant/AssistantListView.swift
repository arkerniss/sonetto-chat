import SwiftUI

/// 助手管理列表:增删改、复制、设为当前。
struct AssistantListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var assistants: AssistantStore

    @State private var showingAddSheet = false
    @State private var newName = ""
    @State private var editingAssistantID: UUID?

    var body: some View {
        ZStack {
            ChatChrome.canvas
                .ignoresSafeArea()
                .onTapGesture { dismissKeyboard() }

            VStack(spacing: 0) {
                header

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(assistants.assistants) { assistant in
                            card(assistant)
                        }
                        addButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .liquidGlassContainer(spacing: 14)
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $editingAssistantID) { id in
            AssistantEditView(assistantID: id)
                .environmentObject(assistants)
        }
        .sheet(isPresented: $showingAddSheet) {
            addSheet
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: assistants.assistants)
    }

    private var header: some View {
        SettingsHeaderBar(
            title: "助手",
            subtitle: "\(assistants.assistants.count) 个助手，点进去编辑",
            backSymbol: "chevron.left",
            backLabel: "返回设置"
        ) {
            dismiss()
        }
    }

    private func card(_ assistant: Assistant) -> some View {
        let isCurrent = assistant.id == assistants.currentAssistantID

        return Button {
            editingAssistantID = assistant.id
        } label: {
            HStack(spacing: 12) {
                AssistantAvatarView(avatar: assistant.avatar, name: assistant.name, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(assistant.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ChatChrome.ink)
                            .lineLimit(1)

                        if isCurrent {
                            Text("当前")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                    }

                    Text(promptPreview(assistant))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 14, interactive: true, shadowRadius: 10, shadowY: 5)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                assistants.setCurrent(assistant.id)
            } label: {
                Label("设为当前助手", systemImage: "checkmark.circle")
            }

            Button {
                if let copy = assistants.duplicateAssistant(assistant.id) {
                    editingAssistantID = copy.id
                }
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }

            if assistants.assistants.count > 1 {
                Divider()
                Button(role: .destructive) {
                    assistants.deleteAssistant(assistant.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private var addButton: some View {
        Button {
            newName = ""
            showingAddSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))

                Text("添加助手")
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 12, tint: .accent, interactive: true, shadowRadius: 10, shadowY: 5)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var addSheet: some View {
        VStack(spacing: 16) {
            Text("新建助手")
                .font(.headline.weight(.semibold))
                .foregroundStyle(ChatChrome.ink)
                .padding(.top, 8)

            TextField("助手名称", text: $newName)
                .settingsInputStyle()
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button("取消") {
                    showingAddSheet = false
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .liquidGlass(cornerRadius: 12, fallbackFill: ChatChrome.field, shadowRadius: 0, shadowY: 0)

                Button("保存") {
                    let created = assistants.addAssistant(name: newName)
                    showingAddSheet = false
                    editingAssistantID = created.id
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .liquidGlass(cornerRadius: 12, tint: .accent, fallbackFill: Color.accentColor, shadowRadius: 0, shadowY: 0)
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .background(ChatChrome.canvas.ignoresSafeArea())
    }

    private func promptPreview(_ assistant: Assistant) -> String {
        let trimmed = assistant.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "未设置提示词" }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }
}
