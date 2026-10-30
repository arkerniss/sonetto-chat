import SwiftUI

/// 正则标签:对消息显示/发送内容做正则替换。
struct AssistantRegexTab: View {
    @Binding var assistant: Assistant

    @State private var editingRule: AssistantRegex?
    @State private var showingEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerRow

                if assistant.regexRules.isEmpty {
                    Text("还没有正则规则。可用于在显示或发送时替换消息内容。")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .liquidGlass(cornerRadius: 16, shadowRadius: 14, shadowY: 8)
                } else {
                    ForEach(assistant.regexRules) { rule in
                        ruleCard(rule)
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
            RegexRuleEditor(rule: editingRule ?? AssistantRegex()) { saved in
                save(saved)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var headerRow: some View {
        HStack {
            Text("正则规则")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChatChrome.ink)
            Spacer()
            Button {
                editingRule = nil
                showingEditor = true
            } label: {
                Label("添加规则", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private func ruleCard(_ rule: AssistantRegex) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(rule.name.isEmpty ? "未命名规则" : rule.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { rule.enabled },
                    set: { on in toggle(rule, enabled: on) }
                ))
                .labelsHidden()
                .tint(Color.accentColor)
            }

            Text("匹配: \(rule.pattern.isEmpty ? "—" : rule.pattern)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("替换为: \(rule.replacement.isEmpty ? "(空)" : rule.replacement)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                if rule.applyToUser { tag("用户") }
                if rule.applyToAssistant { tag("助手") }
                if rule.visualOnly { tag("仅显示") }
                if rule.replaceOnly { tag("仅发送") }
            }

            HStack {
                Spacer()
                Button {
                    editingRule = rule
                    showingEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    assistant.regexRules.removeAll { $0.id == rule.id }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 14, shadowRadius: 10, shadowY: 5)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(ChatChrome.surfaceMuted))
    }

    private func toggle(_ rule: AssistantRegex, enabled: Bool) {
        guard let index = assistant.regexRules.firstIndex(where: { $0.id == rule.id }) else { return }
        assistant.regexRules[index].enabled = enabled
    }

    private func save(_ rule: AssistantRegex) {
        if let index = assistant.regexRules.firstIndex(where: { $0.id == rule.id }) {
            assistant.regexRules[index] = rule
        } else {
            assistant.regexRules.append(rule)
        }
        editingRule = nil
    }
}

/// 正则规则编辑器。
private struct RegexRuleEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State var rule: AssistantRegex
    let onSave: (AssistantRegex) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                ChatChrome.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsField(title: "名称", symbol: "tag") {
                            TextField("规则名称", text: $rule.name)
                                .settingsInputStyle()
                        }

                        SettingsField(title: "匹配模式 (正则)", symbol: "textformat.abc") {
                            TextField("例如 \\*\\*(.+?)\\*\\*", text: $rule.pattern)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .settingsInputStyle()
                        }

                        SettingsField(title: "替换为", symbol: "arrow.right") {
                            TextField("支持 $1 $2 捕获组", text: $rule.replacement)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .settingsInputStyle()
                        }

                        VStack(spacing: 12) {
                            toggleRow("作用于用户消息", $rule.applyToUser)
                            toggleRow("作用于助手消息", $rule.applyToAssistant)
                            toggleRow("仅影响显示 (不改发送内容)", Binding(
                                get: { rule.visualOnly },
                                set: { on in
                                    rule.visualOnly = on
                                    if on { rule.replaceOnly = false }
                                }
                            ))
                            toggleRow("仅影响发送 (不改显示)", Binding(
                                get: { rule.replaceOnly },
                                set: { on in
                                    rule.replaceOnly = on
                                    if on { rule.visualOnly = false }
                                }
                            ))
                        }
                        .padding(16)
                        .liquidGlass(cornerRadius: 12, shadowRadius: 10, shadowY: 5)
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("正则规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(rule)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .disabled(rule.pattern.isEmpty)
                }
            }
        }
    }

    private func toggleRow(_ title: String, _ isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ChatChrome.ink)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.accentColor)
        }
    }
}
