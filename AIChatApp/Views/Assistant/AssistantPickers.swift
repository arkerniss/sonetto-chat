import SwiftUI

/// 简单的 emoji 选择器:常用 emoji 网格 + 手动输入。
struct EmojiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    @State private var customInput = ""

    private let emojis: [String] = [
        "🤖", "😀", "😎", "🧠", "💡", "🎯", "🚀", "⭐️", "🔥", "✨",
        "📚", "✏️", "💻", "🛠️", "🔧", "🧩", "🎨", "🎵", "📷", "🎬",
        "🐱", "🐶", "🦊", "🐼", "🦉", "🐳", "🦄", "🐉", "🌸", "🌈",
        "❤️", "💙", "💚", "💛", "💜", "🧡", "🤍", "🖤", "☀️", "🌙",
        "🍀", "🌟", "⚡️", "🎓", "🔮", "🧪", "📈", "🗂️", "📝", "💬"
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        NavigationStack {
            ZStack {
                ChatChrome.canvas.ignoresSafeArea()

                VStack(spacing: 16) {
                    if !customInput.isEmpty {
                        Text(customInput)
                            .font(.system(size: 56))
                            .frame(width: 88, height: 88)
                            .background(Circle().fill(Color.accentColor.opacity(0.12)))
                            .padding(.top, 8)
                    }

                    TextField("或直接输入 emoji", text: $customInput)
                        .multilineTextAlignment(.center)
                        .settingsInputStyle()
                        .padding(.horizontal, 16)

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(emojis, id: \.self) { emoji in
                                Button {
                                    onPick(emoji)
                                    dismiss()
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 30))
                                        .frame(width: 46, height: 46)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("选择 Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("使用") {
                        let trimmed = customInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onPick(String(trimmed.prefix(2)))
                        }
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .disabled(customInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

/// 助手模型选择(供 Basic 标签覆盖模型用)。第一项是「使用默认」。
struct AssistantModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let models: [String]
    let current: String?
    let onSelect: (String?) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                ChatChrome.canvas.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 10) {
                        row(title: "使用供应商默认模型", value: nil, isActive: current == nil)
                        ForEach(models, id: \.self) { model in
                            row(title: model, value: model, isActive: current == model)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .liquidGlassContainer(spacing: 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("聊天模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func row(title: String, value: String?, isActive: Bool) -> some View {
        Button {
            onSelect(value)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(value == nil ? .secondary : ChatChrome.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(
                cornerRadius: 12,
                tint: isActive ? .accent : .none,
                interactive: true,
                shadowRadius: 8,
                shadowY: 4
            )
        }
        .buttonStyle(.plain)
    }
}
