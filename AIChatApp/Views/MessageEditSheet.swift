import SwiftUI

struct MessageEditSheet: View {
    let originalContent: String
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(originalContent: String, onSave: @escaping (String) -> Void) {
        self.originalContent = originalContent
        self.onSave = onSave
        _text = State(initialValue: originalContent)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ChatChrome.field)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(ChatChrome.line, lineWidth: 1)
                )
                .padding(16)
                .focused($isFocused)
                .navigationTitle("编辑消息")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                onSave(trimmed)
                            }
                            dismiss()
                        }
                        .disabled(
                            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || text == originalContent
                        )
                    }
                }
                .onAppear {
                    isFocused = true
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
