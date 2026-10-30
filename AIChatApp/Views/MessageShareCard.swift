import SwiftUI
import UIKit

/// 仿 rikkahub 的 ExportedChatImage:把消息渲染成固定宽度的分享长图。
/// rikkahub 用 BitmapComposer 把 Compose 视图离屏 draw 成 Bitmap;
/// iOS 这边 SwiftUI 自带 ImageRenderer,直接渲染同一套 MarkdownView,
/// 保证导出的图和聊天界面格式一致(加粗、代码块、表格都保留)。
enum MessageImageExporter {
    /// rikkahub 固定 540dp 宽,这里取同样的逻辑宽度,3x 输出约 1620px
    private static let cardWidth: CGFloat = 540

    @MainActor
    static func renderImage(
        for message: ChatMessage,
        title: String,
        colorScheme: ColorScheme
    ) -> UIImage? {
        let card = MessageShareCard(message: message, conversationTitle: title)
            .frame(width: cardWidth)
            .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: cardWidth, height: nil)
        return renderer.uiImage
    }

    /// 渲染成 PNG 临时文件,交给系统分享面板(和导出 .md 走同一条 FileProvider 思路)
    @MainActor
    static func renderImageFile(
        for message: ChatMessage,
        title: String,
        colorScheme: ColorScheme
    ) throws -> URL {
        guard let image = renderImage(for: message, title: title, colorScheme: colorScheme),
              let data = image.pngData() else {
            throw ExportError.renderFailed
        }

        let filename = "Sonetto-Chat-\(message.id.uuidString.prefix(8)).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    enum ExportError: LocalizedError {
        case renderFailed

        var errorDescription: String? {
            "图片生成失败"
        }
    }
}

/// 把单条消息打包成 .md 临时文件,和图片导出一样交给系统分享面板
enum MessageMarkdownExporter {
    static func renderMarkdownFile(for message: ChatMessage, title: String) throws -> URL {
        var lines: [String] = [
            "# \(title)",
            "",
            "- 角色：\(roleName(for: message.role))",
            "- 时间：\(message.createdAt.formatted(date: .numeric, time: .shortened))",
            ""
        ]

        if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(message.content)
            lines.append("")
        }

        if !message.attachments.isEmpty {
            lines.append("**附件**")
            for attachment in message.attachments {
                let size = ByteCountFormatter.string(fromByteCount: Int64(attachment.fileSize), countStyle: .file)
                lines.append("- \(attachment.filename)（\(attachment.mimeType)，\(size)）")
            }
            lines.append("")
        }

        let filename = "Sonetto-Chat-\(message.id.uuidString.prefix(8)).md"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func roleName(for role: ChatMessage.Role) -> String {
        switch role {
        case .system:
            return "系统"
        case .user:
            return "用户"
        case .assistant:
            return "AI"
        }
    }
}

/// 分享卡片:头部应用名+对话标题+时间,正文复用 MarkdownView,底部水印
struct MessageShareCard: View {
    let message: ChatMessage
    let conversationTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 18)

            Divider()
                .padding(.horizontal, 24)

            MarkdownView(blocks: MarkdownParser.parse(message.content), isInteractive: false)
                .foregroundStyle(ChatChrome.ink)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)

            Divider()
                .padding(.horizontal, 24)

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChatChrome.surface)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(conversationTitle)
                    .font(.headline)
                    .foregroundStyle(ChatChrome.ink)
                    .lineLimit(2)

                Text(message.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            Text("Sonetto Chat")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text("AI 生成内容,仅供参考")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
