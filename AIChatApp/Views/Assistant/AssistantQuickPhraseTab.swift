import SwiftUI

/// 快捷短语标签:助手作用域的快捷短语,聊天时点一下插入到输入框。
struct AssistantQuickPhraseTab: View {
    @Binding var assistant: Assistant

    @State private var editingPhrase: QuickPhrase?
    @State private var showingEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerRow

                if assistant.quickPhrases.isEmpty {
                    Text("还没有快捷短语。添加后会在聊天输入栏出现快捷入口。")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .liquidGlass(cornerRadius: 16, shadowRadius: 14, shadowY: 8)
                } else {
                    ForEach(assistant.quickPhrases) { phrase in
                        phraseCard(phrase)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .liquidGlassContainer(spacing: 14)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showingEditor) {
            QuickPhraseEditor(phrase: editingPhrase ?? QuickPhrase()) { saved in
                save(saved)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var headerRow: some View {
        HStack {
            Text("快捷短语")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChatChrome.ink)
            Spacer()
            Button {
                editingPhrase = nil
                showingEditor = true
            } label: {
                Label("添加短语", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private func phraseCard(_ phrase: QuickPhrase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(phrase.title.isEmpty ? "未命名" : phrase.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
                Spacer()
                Button {
                    editingPhrase = phrase
                    showingEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    assistant.quickPhrases.removeAll { $0.id == phrase.id }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            Text(phrase.content)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 14, shadowRadius: 10, shadowY: 5)
    }

    private func save(_ phrase: QuickPhrase) {
        let trimmedContent = phrase.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }
        if let index = assistant.quickPhrases.firstIndex(where: { $0.id == phrase.id }) {
            assistant.quickPhrases[index] = phrase
        } else {
            assistant.quickPhrases.append(phrase)
        }
        editingPhrase = nil
    }
}

/// 快捷短语编辑器。
private struct QuickPhraseEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State var phrase: QuickPhrase
    let onSave: (QuickPhrase) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                ChatChrome.canvas.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    SettingsField(title: "标题", symbol: "tag") {
                        TextField("短语标题", text: $phrase.title)
                            .settingsInputStyle()
                    }

                    SettingsField(title: "内容", symbol: "text.alignleft") {
                        TextField("插入到输入框的内容", text: $phrase.content, axis: .vertical)
                            .lineLimit(4...10)
                            .settingsInputStyle()
                    }

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("快捷短语")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(phrase)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .disabled(phrase.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
