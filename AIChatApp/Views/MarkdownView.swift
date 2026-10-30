import SwiftUI
import UIKit

/// 按块渲染 AI 回复,块的样式对齐 rikkahub:标题分级字号、代码块带语言栏和
/// 复制按钮、引用块左侧竖条、列表多级缩进、表格横向滚动。
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    /// 分享卡片里渲染时关闭交互(复制按钮、文本选择)
    var isInteractive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .paragraph(text):
            selectableText(
                Text(text)
                    .font(.body)
            )
            .lineSpacing(3)

        case let .heading(level, text):
            selectableText(
                Text(text)
                    .font(headingFont(level))
            )
            .padding(.top, level <= 2 ? 6 : 3)

        case let .codeBlock(language, code):
            CodeBlockView(language: language, code: code, isInteractive: isInteractive)

        case let .quote(lines):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        selectableText(
                            Text(line)
                                .font(.body)
                                .italic()
                                .foregroundStyle(.secondary)
                        )
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

        case let .list(items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(item.marker)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)

                        selectableText(
                            Text(item.text)
                                .font(.body)
                        )
                        .lineSpacing(3)
                    }
                    .padding(.leading, CGFloat(item.level) * 16)
                }
            }

        case let .table(header, rows):
            tableView(header: header, rows: rows)

        case .divider:
            Divider()
                .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func selectableText(_ text: Text) -> some View {
        if isInteractive {
            text.textSelection(.enabled)
        } else {
            text
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 24, weight: .bold)
        case 2:
            return .system(size: 21, weight: .bold)
        case 3:
            return .system(size: 19, weight: .semibold)
        case 4:
            return .system(size: 17, weight: .semibold)
        default:
            return .system(size: 16, weight: .semibold)
        }
    }

    private func tableView(header: [AttributedString], rows: [[AttributedString]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .background(Color.primary.opacity(0.06))

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)

                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                    }
                    .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(ChatChrome.line, lineWidth: 1)
            )
        }
    }
}

/// 代码块:顶部语言栏 + 复制按钮,正文等宽字体可横向滚动(rikkahub 同款布局)
private struct CodeBlockView: View {
    let language: String
    let code: String
    let isInteractive: Bool

    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if isInteractive {
                    Button {
                        copyCode()
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(copied ? Color.accentColor : .secondary)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制代码")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isInteractive ? 4 : 8)
            .background(Color.primary.opacity(0.06))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(2)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ChatChrome.line, lineWidth: 1)
        )
        .onDisappear {
            copyResetTask?.cancel()
        }
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        copied = true

        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else {
                return
            }
            copied = false
        }
    }
}
