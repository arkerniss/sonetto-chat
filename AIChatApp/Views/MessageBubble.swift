import Foundation
import SwiftUI
import UIKit

struct MessageBubble: View {
    let message: ChatMessage
    var conversationTitle = ""
    var isStreaming = false
    /// 助手名称(开启「使用助手名称」时传入);nil 表示不显示头部名称
    var assistantName: String?
    /// 助手头像(emoji 或本地文件名,开启「使用助手头像」时传入)
    var assistantAvatar: String?
    var onDelete: (() -> Void)?
    var onRegenerate: (() -> Void)?
    var onEdit: ((String) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    @State private var pendingDelete = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var deleteResetTask: Task<Void, Never>?
    @State private var showEditSheet = false
    @State private var showMessageInfo = false
    @State private var shareFile: ShareFile?
    @State private var shareError: String?

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            content
                .contextMenu {
                    contextMenuItems
                } preview: {
                    contextMenuPreview
                }

            if showsActions {
                actionBar
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.horizontal, 18)
        .animation(.easeInOut(duration: 0.2), value: showsActions)
        .onDisappear {
            copyResetTask?.cancel()
            deleteResetTask?.cancel()
        }
        .sheet(isPresented: $showEditSheet) {
            MessageEditSheet(originalContent: message.content) { newContent in
                onEdit?(newContent)
            }
        }
        .sheet(item: $shareFile) { file in
            MessageShareSheet(activityItems: [file.url])
        }
        .alert("分享失败", isPresented: shareErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isAssistantDraft {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text("正在生成…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        } else if isUser {
            VStack(alignment: .trailing, spacing: 10) {
                if !message.attachments.isEmpty {
                    attachmentGrid
                }

                if !message.content.isEmpty {
                    MarkdownView(blocks: markdownBlocks)
                }
            }
            .foregroundStyle(ChatChrome.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
            )
            .padding(.leading, 44)
        } else {
            // rikkahub 风格：AI 回复不带气泡，正文直接平铺
            VStack(alignment: .leading, spacing: 10) {
                if showsAssistantHeader {
                    assistantHeader
                }

                if !message.attachments.isEmpty {
                    attachmentGrid
                }

                if !message.content.isEmpty {
                    MarkdownView(blocks: markdownBlocks)
                }
            }
            .foregroundStyle(ChatChrome.ink)
        }
    }

    /// 助手头部:头像 + 名称。仅 assistant 消息且传入了名称或头像时显示。
    private var showsAssistantHeader: Bool {
        !isUser && (assistantName != nil || assistantAvatar != nil)
    }

    @ViewBuilder
    private var assistantHeader: some View {
        HStack(spacing: 8) {
            if let assistantAvatar {
                AssistantAvatarView(avatar: assistantAvatar, name: assistantName ?? "", size: 24)
            }
            if let assistantName, !assistantName.isEmpty {
                Text(assistantName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 长按预览:正文是平铺的(无气泡背景),系统默认会把透明视图直接抠出来当预览,
    /// 底下的聊天内容会透到液态玻璃菜单后面;给预览套一层不透明底色解决
    private var contextMenuPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.attachments.isEmpty {
                attachmentGrid
            }

            if !message.content.isEmpty {
                MarkdownView(blocks: markdownBlocks, isInteractive: false)
            }
        }
        .foregroundStyle(ChatChrome.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 340, alignment: .leading)
        .background(ChatChrome.surface)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            copyMessage()
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }

        if canEdit {
            Button {
                showEditSheet = true
            } label: {
                Label("编辑", systemImage: "pencil")
            }
        }

        if onRegenerate != nil {
            Button {
                onRegenerate?()
            } label: {
                Label("重新生成", systemImage: "arrow.clockwise")
            }
        }

        if !message.content.isEmpty {
            Button {
                shareAsMarkdown()
            } label: {
                Label("分享 Markdown", systemImage: "square.and.arrow.up")
            }

            Button {
                shareAsImage()
            } label: {
                Label("分享图片", systemImage: "photo.on.rectangle")
            }
        }

        if onDelete != nil {
            Divider()
            Button(role: .destructive) {
                onDelete?()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 4) {
            actionButton(
                systemImage: copied ? "checkmark" : "doc.on.doc",
                accessibilityLabel: "复制",
                tint: copied ? Color.accentColor : .secondary
            ) {
                copyMessage()
            }

            if onRegenerate != nil {
                actionButton(
                    systemImage: "arrow.clockwise",
                    accessibilityLabel: "重新生成",
                    tint: .secondary
                ) {
                    onRegenerate?()
                }
            }

            actionButton(
                systemImage: "trash",
                accessibilityLabel: pendingDelete ? "确认删除" : "删除",
                tint: pendingDelete ? .red : .secondary
            ) {
                handleDeleteTap()
            }

            Button {
                showMessageInfo = true
            } label: {
                Text(message.createdAt, format: .dateTime.hour().minute())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("消息详情")
            .popover(isPresented: $showMessageInfo) {
                messageInfoPopover
            }
        }
    }

    private var messageInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            infoRow(
                label: "时间",
                value: message.createdAt.formatted(
                    .dateTime.year().month().day().hour().minute().second()
                )
            )

            if isUser {
                infoRow(label: "来源", value: "用户消息")
            } else {
                infoRow(label: "模型", value: message.model ?? "未知")
            }
        }
        .padding(16)
        .frame(minWidth: 220, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(ChatChrome.ink)
                .textSelection(.enabled)
        }
    }

    private func actionButton(
        systemImage: String,
        accessibilityLabel: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func copyMessage() {
        UIPasteboard.general.string = message.content
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

    /// 把单条消息打包成 .md 文件再调系统分享面板,和对话级导出保持同一种格式
    private func shareAsMarkdown() {
        do {
            let url = try MessageMarkdownExporter.renderMarkdownFile(
                for: message,
                title: conversationTitle.isEmpty ? "Sonetto Chat" : conversationTitle
            )
            shareFile = ShareFile(url: url)
        } catch {
            shareError = error.localizedDescription
        }
    }

    /// 仿 rikkahub 的图片导出:把消息渲染成分享卡片长图再调系统分享面板
    private func shareAsImage() {
        do {
            let url = try MessageImageExporter.renderImageFile(
                for: message,
                title: conversationTitle.isEmpty ? "Sonetto Chat" : conversationTitle,
                colorScheme: colorScheme
            )
            shareFile = ShareFile(url: url)
        } catch {
            shareError = error.localizedDescription
        }
    }

    private var shareErrorBinding: Binding<Bool> {
        Binding(
            get: { shareError != nil },
            set: { isPresented in
                if !isPresented {
                    shareError = nil
                }
            }
        )
    }

    /// 与 rikkahub 一致的二次确认：第一次点变红，3 秒内再点才删除。
    private func handleDeleteTap() {
        if pendingDelete {
            deleteResetTask?.cancel()
            pendingDelete = false
            onDelete?()
            return
        }

        pendingDelete = true
        deleteResetTask?.cancel()
        deleteResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else {
                return
            }
            pendingDelete = false
        }
    }

    private var showsActions: Bool {
        !isStreaming && !isAssistantDraft && (!message.content.isEmpty || !message.attachments.isEmpty)
    }

    private var canEdit: Bool {
        onEdit != nil && !message.content.isEmpty
    }

    private var isUser: Bool {
        message.role == .user
    }

    private var isAssistantDraft: Bool {
        message.role == .assistant && message.content.isEmpty
    }

    private var markdownBlocks: [MarkdownBlock] {
        MarkdownCache.blocks(for: message)
    }

    private var attachmentGrid: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 7) {
            ForEach(message.attachments) { attachment in
                AttachmentPreview(attachment: attachment, variant: .bubble)
            }
        }
    }
}

private struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct MessageShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
