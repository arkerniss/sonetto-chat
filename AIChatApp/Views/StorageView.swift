import SwiftUI

/// 聊天记录存储管理页,布局对应 kelivo 的 StorageSpacePage:
/// 总用量卡 + 分类占比条 + 分类明细行 + 清理操作
struct StorageView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var report = StorageUsageService.computeReport()
    @State private var showClearAllConfirm = false
    @State private var statusMessage: String?

    var body: some View {
        ZStack {
            ChatChrome.canvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        totalCard
                        categorySection
                        cleanupSection

                        if let statusMessage {
                            feedbackCard(message: statusMessage)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .liquidGlassContainer(spacing: 18)
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("清空聊天记录", isPresented: $showClearAllConfirm) {
            Button("清空并删除附件", role: .destructive) {
                StorageUsageService.clearAllConversations()
                refresh(status: "聊天记录已清空")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所有对话和附件文件,且无法恢复。建议先在「数据备份」里导出一份。")
        }
        .animation(.easeInOut(duration: 0.2), value: statusMessage)
    }

    private var header: some View {
        SettingsHeaderBar(
            title: "聊天记录存储",
            subtitle: "查看占用空间并清理",
            backSymbol: "chevron.left",
            backLabel: "返回设置"
        ) {
            dismiss()
        }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(AttachmentStore.formattedSize(report.totalBytes))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ChatChrome.ink)

                    Text("聊天数据总占用")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            usageBar
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 12, shadowRadius: 16, shadowY: 8)
    }

    /// kelivo 风格的分类占比条
    private var usageBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(report.categories.filter { $0.bytes > 0 }) { category in
                    Capsule()
                        .fill(color(for: category.key))
                        .frame(width: max(
                            6,
                            proxy.size.width * CGFloat(category.bytes) / CGFloat(max(report.totalBytes, 1))
                        ))
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(report.categories.enumerated()), id: \.element.id) { index, category in
                categoryRow(category)

                if index < report.categories.count - 1 {
                    Divider()
                        .padding(.leading, 50)
                }
            }
        }
        .padding(.vertical, 4)
        .liquidGlass(cornerRadius: 12, shadowRadius: 16, shadowY: 8)
    }

    private func categoryRow(_ category: StorageUsageService.CategoryUsage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(for: category.key))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color(for: category.key))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(color(for: category.key).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: category.key))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)

                Text(subtitle(for: category))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(AttachmentStore.formattedSize(category.bytes))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            cleanupButton(
                title: "清理临时文件",
                detail: "分享导出产生的缓存,可放心清理",
                systemImage: "trash",
                tint: Color.accentColor
            ) {
                StorageUsageService.clearTemporaryFiles()
                refresh(status: "临时文件已清理")
            }

            cleanupButton(
                title: "清理未引用的附件",
                detail: "删除对话后遗留的孤儿文件",
                systemImage: "doc.badge.gearshape",
                tint: Color.accentColor
            ) {
                StorageUsageService.clearOrphanAttachments()
                refresh(status: "未引用的附件已清理")
            }

            cleanupButton(
                title: "清空聊天记录",
                detail: "删除所有对话与附件,不可恢复",
                systemImage: "exclamationmark.triangle",
                tint: .red
            ) {
                showClearAllConfirm = true
            }
        }
    }

    private func cleanupButton(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(tint.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint == .red ? .red : ChatChrome.ink)

                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 12, interactive: true, shadowRadius: 10, shadowY: 5)
        }
        .buttonStyle(.plain)
    }

    private func feedbackCard(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(ChatChrome.ink)

            Spacer(minLength: 0)
        }
        .padding(14)
        .liquidGlass(cornerRadius: 12, shadowRadius: 10, shadowY: 5)
    }

    private func refresh(status: String) {
        report = StorageUsageService.computeReport()
        statusMessage = status
    }

    private func title(for key: StorageUsageService.CategoryUsage.Key) -> String {
        switch key {
        case .images:
            return "图片附件"
        case .files:
            return "文件附件"
        case .chatData:
            return "对话记录"
        case .temporary:
            return "临时文件"
        case .orphans:
            return "未引用的附件"
        }
    }

    private func subtitle(for category: StorageUsageService.CategoryUsage) -> String {
        switch category.key {
        case .chatData:
            return "\(category.fileCount) 个对话"
        default:
            return "\(category.fileCount) 个文件"
        }
    }

    private func symbol(for key: StorageUsageService.CategoryUsage.Key) -> String {
        switch key {
        case .images:
            return "photo"
        case .files:
            return "paperclip"
        case .chatData:
            return "bubble.left.and.bubble.right"
        case .temporary:
            return "clock.arrow.circlepath"
        case .orphans:
            return "questionmark.folder"
        }
    }

    private func color(for key: StorageUsageService.CategoryUsage.Key) -> Color {
        switch key {
        case .images:
            return Color(red: 0.39, green: 0.40, blue: 0.95)
        case .files:
            return Color(red: 0.66, green: 0.33, blue: 0.97)
        case .chatData:
            return Color(red: 0.13, green: 0.77, blue: 0.37)
        case .temporary:
            return Color(red: 0.92, green: 0.70, blue: 0.03)
        case .orphans:
            return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }
}
