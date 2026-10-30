import SwiftUI
import UniformTypeIdentifiers

/// 备份页状态。对应 rikkahub 的 BackupVM:WebDAV 测试/备份/列表/恢复/删除 +
/// 本地导出/导入。
@MainActor
final class BackupViewModel: ObservableObject {
    @Published var config: WebDAVConfig
    @Published var password: String
    @Published var remoteItems: [WebDAVBackupItem] = []
    @Published var isBusy = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var lastBackupTime: Date?

    init() {
        config = BackupService.loadWebDAVConfig()
        password = BackupService.loadWebDAVPassword()
        lastBackupTime = BackupService.lastBackupTime
    }

    func saveConfig() {
        BackupService.saveWebDAVConfig(config, password: password)
    }

    func testConnection() async {
        await run("连接成功,服务器可用") { client in
            try await client.testConnection()
        }
    }

    func backupNow(settings: SettingsStore) async {
        await run("备份完成") { [config] client in
            let archive = BackupService.makeArchive(
                settings: settings,
                includeConversations: config.includeConversations,
                includeAttachments: config.includeAttachments
            )
            let data = try BackupService.encode(archive)
            try await client.ensureDirectory()
            try await client.upload(data, filename: BackupService.makeFilename())
            BackupService.recordBackupTime()
            self.lastBackupTime = BackupService.lastBackupTime
            self.remoteItems = (try? await client.list()) ?? self.remoteItems
        }
    }

    func refreshList() async {
        await run(nil) { client in
            self.remoteItems = try await client.list()
        }
    }

    func restore(_ item: WebDAVBackupItem, settings: SettingsStore) async {
        await run("恢复完成,数据已生效") { client in
            let data = try await client.download(filename: item.displayName)
            try BackupService.restore(from: data, settings: settings)
        }
    }

    func delete(_ item: WebDAVBackupItem) async {
        await run("已删除 \(item.displayName)") { client in
            try await client.delete(filename: item.displayName)
            self.remoteItems.removeAll { $0.id == item.id }
        }
    }

    func restoreFromLocalFile(_ url: URL, settings: SettingsStore) {
        errorMessage = nil
        statusMessage = nil

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try BackupService.restore(from: data, settings: settings)
            statusMessage = "恢复完成,数据已生效"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportToLocalFile(settings: SettingsStore) -> URL? {
        errorMessage = nil
        statusMessage = nil

        do {
            let url = try BackupService.exportToFile(
                settings: settings,
                includeConversations: config.includeConversations,
                includeAttachments: config.includeAttachments
            )
            lastBackupTime = BackupService.lastBackupTime
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// 统一的 WebDAV 操作包装:存配置 -> 建 client -> 跑任务 -> 报状态
    private func run(
        _ successMessage: String?,
        _ task: @escaping (WebDAVClient) async throws -> Void
    ) async {
        guard !isBusy else {
            return
        }

        errorMessage = nil
        statusMessage = nil
        isBusy = true
        defer {
            isBusy = false
        }

        saveConfig()
        do {
            let client = try WebDAVClient(config: config, password: password)
            try await task(client)
            statusMessage = successMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 备份设置页,布局对应 rikkahub 的 BackupPage:
/// 状态卡 + WebDAV 配置 + 备份内容选择 + 操作按钮 + 远端文件列表 + 本地导入导出
struct BackupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var viewModel = BackupViewModel()

    @State private var showPassword = false
    @State private var showFileImporter = false
    @State private var exportURL: ExportURL?
    @State private var pendingRestoreItem: WebDAVBackupItem?

    var body: some View {
        ZStack {
            ChatChrome.canvas
                .ignoresSafeArea()
                .onTapGesture {
                    dismissKeyboard()
                }

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        statusCard
                        webDAVSection
                        backupItemsSection
                        webDAVActions
                        remoteListSection
                        localSection

                        if let statusMessage = viewModel.statusMessage {
                            feedbackCard(title: "完成", message: statusMessage, tint: .green)
                        }

                        if let errorMessage = viewModel.errorMessage {
                            feedbackCard(title: "出错了", message: errorMessage, tint: .red)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .liquidGlassContainer(spacing: 18)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear {
            viewModel.saveConfig()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                viewModel.restoreFromLocalFile(url, settings: settings)
            }
        }
        .sheet(item: $exportURL) { file in
            BackupShareSheet(activityItems: [file.url])
        }
        .alert(
            "恢复备份",
            isPresented: Binding(
                get: { pendingRestoreItem != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingRestoreItem = nil
                    }
                }
            )
        ) {
            Button("恢复并覆盖", role: .destructive) {
                if let item = pendingRestoreItem {
                    Task {
                        await viewModel.restore(item, settings: settings)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("恢复会覆盖当前的供应商设置和对话记录,确定继续吗?")
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.remoteItems)
    }

    private var header: some View {
        SettingsHeaderBar(
            title: "数据备份",
            subtitle: "WebDAV 云备份与本地导入导出",
            backSymbol: "chevron.left",
            backLabel: "返回设置"
        ) {
            viewModel.saveConfig()
            dismiss()
        }
    }

    /// 对应 rikkahub 的 BackupStatusCard:上次备份时间 + 云端文件数
    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.icloud")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 46, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(lastBackupText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)

                Text(viewModel.remoteItems.isEmpty
                     ? "云端备份列表尚未加载"
                     : "云端共 \(viewModel.remoteItems.count) 份备份")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 12, shadowRadius: 16, shadowY: 8)
    }

    private var lastBackupText: String {
        guard let time = viewModel.lastBackupTime else {
            return "还没有备份过"
        }
        return "上次备份:\(time.formatted(date: .abbreviated, time: .shortened))"
    }

    private var webDAVSection: some View {
        SettingsSection(
            title: "WebDAV",
            subtitle: "坚果云、Nextcloud 等支持 WebDAV 的网盘均可"
        ) {
            SettingsField(title: "服务器地址", symbol: "link") {
                TextField("https://dav.example.com/dav", text: $viewModel.config.urlString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .settingsInputStyle()
            }

            SettingsField(title: "用户名", symbol: "person") {
                TextField("用户名", text: $viewModel.config.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .settingsInputStyle()
            }

            SettingsField(title: "密码", symbol: "key") {
                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("应用密码", text: $viewModel.password)
                        } else {
                            SecureField("应用密码", text: $viewModel.password)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "隐藏密码" : "显示密码")
                }
                .settingsInputStyle()
            }

            SettingsField(title: "备份目录", symbol: "folder") {
                TextField("sonetto_backups", text: $viewModel.config.path)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .settingsInputStyle()
            }
        }
    }

    /// 对应 rikkahub 的 BackupItem 多选(DATABASE / FILES)
    private var backupItemsSection: some View {
        SettingsSection(
            title: "备份内容",
            subtitle: "供应商设置和 API Key 始终包含在备份中"
        ) {
            Toggle(isOn: $viewModel.config.includeConversations) {
                Label("对话记录", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
            }
            .tint(Color.accentColor)

            Toggle(isOn: $viewModel.config.includeAttachments) {
                Label("附件文件", systemImage: "paperclip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
            }
            .tint(Color.accentColor)
            .disabled(!viewModel.config.includeConversations)
            .opacity(viewModel.config.includeConversations ? 1 : 0.5)
        }
    }

    private var webDAVActions: some View {
        HStack(spacing: 10) {
            actionButton(
                title: "测试连接",
                symbol: "bolt.horizontal",
                prominent: false
            ) {
                await viewModel.testConnection()
            }

            actionButton(
                title: "立即备份",
                symbol: "icloud.and.arrow.up",
                prominent: true
            ) {
                await viewModel.backupNow(settings: settings)
            }
        }
    }

    private var remoteListSection: some View {
        SettingsSection(
            title: "云端备份",
            subtitle: "点击恢复会覆盖当前数据"
        ) {
            Button {
                Task {
                    await viewModel.refreshList()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))

                    Text("刷新备份列表")
                        .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 8)
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(
                    cornerRadius: 10,
                    interactive: true,
                    fallbackFill: ChatChrome.field,
                    shadowRadius: 6,
                    shadowY: 3
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isBusy)

            if viewModel.remoteItems.isEmpty {
                Text("暂无云端备份,先填写 WebDAV 信息再刷新")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(viewModel.remoteItems) { item in
                    remoteItemRow(item)
                }
            }
        }
    }

    /// 对应 rikkahub 的 WebDavBackupItemCard:文件名/大小 + 恢复/删除
    private func remoteItemRow(_ item: WebDAVBackupItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(remoteItemSubtitle(item))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                pendingRestoreItem = item
            } label: {
                Image(systemName: "arrow.counterclockwise.icloud")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("恢复此备份")

            Button {
                Task {
                    await viewModel.delete(item)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除此备份")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlass(
            cornerRadius: 10,
            fallbackFill: ChatChrome.field,
            shadowRadius: 4,
            shadowY: 2
        )
        .disabled(viewModel.isBusy)
    }

    private func remoteItemSubtitle(_ item: WebDAVBackupItem) -> String {
        var parts = [AttachmentStore.formattedSize(Int(item.size))]
        if let modified = item.lastModified {
            parts.append(modified.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }

    /// 对应 rikkahub 的 ImportExportTab
    private var localSection: some View {
        SettingsSection(
            title: "本地导入导出",
            subtitle: "导出备份文件保存到文件 App,或从备份文件恢复"
        ) {
            HStack(spacing: 10) {
                actionButton(
                    title: "导出备份",
                    symbol: "square.and.arrow.up",
                    prominent: false
                ) {
                    if let url = viewModel.exportToLocalFile(settings: settings) {
                        exportURL = ExportURL(url: url)
                    }
                }

                actionButton(
                    title: "导入恢复",
                    symbol: "square.and.arrow.down",
                    prominent: false
                ) {
                    showFileImporter = true
                }
            }
        }
    }

    private func actionButton(
        title: String,
        symbol: String,
        prominent: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isBusy && prominent {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(prominent ? .white : Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .liquidGlass(
                cornerRadius: 11,
                tint: prominent ? .custom(Color.accentColor.opacity(0.82)) : .none,
                interactive: true,
                fallbackFill: prominent ? Color.accentColor : ChatChrome.field,
                shadowRadius: 8,
                shadowY: 4
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy)
        .opacity(viewModel.isBusy ? 0.65 : 1)
    }

    private func feedbackCard(title: String, message: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .textCase(.uppercase)

            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(ChatChrome.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(
            cornerRadius: 10,
            tint: .custom(tint.opacity(0.16)),
            fallbackFill: tint.opacity(0.08),
            fallbackStroke: tint.opacity(0.18),
            shadowRadius: 6,
            shadowY: 3
        )
    }
}

private struct ExportURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct BackupShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
