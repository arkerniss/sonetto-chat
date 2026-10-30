import SwiftUI

/// 记忆标签:开关 + 手动记忆条目管理。发送时注入到系统提示词。
struct AssistantMemoryTab: View {
    @Binding var assistant: Assistant

    @State private var editingIndex: Int?
    @State private var draftContent = ""
    @State private var showingEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switchCard
                memoriesCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .liquidGlassContainer(spacing: 18)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showingEditor) {
            memoryEditor
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var switchCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("启用记忆", systemImage: "brain")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
                Spacer()
                Toggle("", isOn: $assistant.enableMemory)
                    .labelsHidden()
                    .tint(Color.accentColor)
            }

            Text("开启后,下面的记忆条目会在每次对话时注入到系统提示词,帮助助手记住关键信息。")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16, shadowRadius: 14, shadowY: 8)
    }

    private var memoriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("记忆条目")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
                Spacer()
                Button {
                    editingIndex = nil
                    draftContent = ""
                    showingEditor = true
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            if assistant.memories.isEmpty {
                Text("还没有记忆条目。")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(assistant.memories.enumerated()), id: \.offset) { index, memory in
                    memoryRow(index: index, content: memory)
                }
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16, shadowRadius: 14, shadowY: 8)
    }

    private func memoryRow(index: Int, content: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(content)
                .font(.caption.weight(.medium))
                .foregroundStyle(ChatChrome.ink)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                editingIndex = index
                draftContent = content
                showingEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                guard index < assistant.memories.count else { return }
                assistant.memories.remove(at: index)
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

    private var memoryEditor: some View {
        NavigationStack {
            ZStack {
                ChatChrome.canvas.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    TextField("输入要记住的信息", text: $draftContent, axis: .vertical)
                        .lineLimit(3...10)
                        .settingsInputStyle()
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle(editingIndex == nil ? "添加记忆" : "编辑记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showingEditor = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saveMemory()
                        showingEditor = false
                    }
                    .font(.body.weight(.semibold))
                    .disabled(draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveMemory() {
        let trimmed = draftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = editingIndex, index < assistant.memories.count {
            assistant.memories[index] = trimmed
        } else {
            assistant.memories.append(trimmed)
        }
        editingIndex = nil
    }
}
