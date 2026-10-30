import SwiftUI

/// 聊天顶部快速切换当前助手的面板。
struct AssistantPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var assistants: AssistantStore

    var body: some View {
        NavigationStack {
            ZStack {
                ChatChrome.canvas
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("选择助手")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ChatChrome.ink)

                        Text("点一下立即切换当前助手")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(assistants.assistants) { assistant in
                                row(assistant)
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
                    Button("完成") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func row(_ assistant: Assistant) -> some View {
        let isActive = assistant.id == assistants.currentAssistantID

        return Button {
            assistants.setCurrent(assistant.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                AssistantAvatarView(avatar: assistant.avatar, name: assistant.name, size: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(assistant.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChatChrome.ink)
                        .lineLimit(1)

                    Text(promptPreview(assistant))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isActive {
                    Text("当前")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
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

    private func promptPreview(_ assistant: Assistant) -> String {
        let trimmed = assistant.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "未设置提示词" }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }
}

/// 输入框上方的快捷短语选择面板。
struct QuickPhrasePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let phrases: [QuickPhrase]
    let onSelect: (QuickPhrase) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                ChatChrome.canvas
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("快捷短语")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ChatChrome.ink)

                        Text("点一下插入到输入框")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                    if phrases.isEmpty {
                        Spacer()
                        Text("当前助手还没有快捷短语")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(phrases) { phrase in
                                    row(phrase)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func row(_ phrase: QuickPhrase) -> some View {
        Button {
            onSelect(phrase)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(phrase.title.isEmpty ? "未命名" : phrase.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChatChrome.ink)
                        .lineLimit(1)

                    Text(phrase.content)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 12, interactive: true, shadowRadius: 10, shadowY: 5)
        }
        .buttonStyle(.plain)
    }
}
