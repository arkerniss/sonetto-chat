import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var assistants: AssistantStore

    /// hub 卡片副标题用。扫目录有 IO 开销,进页面时算一次,
    /// 不能放在计算属性里跟着 body 反复执行
    @State private var storageTotalBytes: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                ChatChrome.canvas
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissKeyboard()
                    }

                VStack(spacing: 0) {
                    hubHeader

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            providerEntryCard
                            assistantEntryCard
                            backupEntryCard
                            storageEntryCard
                            appearanceCard
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .liquidGlassContainer(spacing: 18)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                storageTotalBytes = StorageUsageService.computeReport().totalBytes
            }
            .navigationDestination(for: SettingsHubRoute.self) { route in
                switch route {
                case .providerList:
                    ProviderListView()
                case .providerEditor(let id):
                    ProviderSettingsView(providerID: id)
                case .assistantList:
                    AssistantListView()
                case .backup:
                    BackupView()
                case .storage:
                    StorageView()
                }
            }
        }
    }
    private var hubHeader: some View {
        SettingsHeaderBar(
            title: "设置",
            subtitle: "管理供应商与生成参数",
            backSymbol: "xmark",
            backLabel: "关闭设置"
        ) {
            dismiss()
        }
    }

    private var providerEntryCard: some View {
        NavigationLink(value: SettingsHubRoute.providerList) {
            HStack(spacing: 14) {
                Image(systemName: "server.rack")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("供应商设置")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChatChrome.ink)

                    Text(providerSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 12, interactive: true, shadowRadius: 16, shadowY: 8)
        }
        .buttonStyle(.plain)
    }

    private var providerSummary: String {
        let count = settings.providers.count
        let activeName = settings.activeProvider.name
        return count <= 1 ? activeName : "\(count) 个供应商 · 当前 \(activeName)"
    }

    private var assistantEntryCard: some View {
        NavigationLink(value: SettingsHubRoute.assistantList) {
            HStack(spacing: 14) {
                Image(systemName: "person.2.badge.gearshape")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("助手设置")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChatChrome.ink)

                    Text(assistantSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 12, interactive: true, shadowRadius: 16, shadowY: 8)
        }
        .buttonStyle(.plain)
    }

    private var assistantSummary: String {
        let count = assistants.assistants.count
        let currentName = assistants.currentAssistant.name
        return count <= 1 ? currentName : "\(count) 个助手 · 当前 \(currentName)"
    }

    private var backupEntryCard: some View {
        NavigationLink(value: SettingsHubRoute.backup) {
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
                    Text("数据备份")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChatChrome.ink)

                    Text(backupSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 12, interactive: true, shadowRadius: 16, shadowY: 8)
        }
        .buttonStyle(.plain)
    }

    private var backupSummary: String {
        guard let time = BackupService.lastBackupTime else {
            return "WebDAV 云备份与本地导入导出"
        }
        return "上次备份 \(time.formatted(date: .abbreviated, time: .shortened))"
    }

    private var storageEntryCard: some View {
        NavigationLink(value: SettingsHubRoute.storage) {
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
                    Text("聊天记录存储")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChatChrome.ink)

                    Text(storageSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 12, interactive: true, shadowRadius: 16, shadowY: 8)
        }
        .buttonStyle(.plain)
    }

    private var storageSummary: String {
        guard let storageTotalBytes else {
            return "查看占用空间并清理"
        }
        return "已占用 \(AttachmentStore.formattedSize(storageTotalBytes))"
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("外观")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChatChrome.ink)

                    Text("浅色、深色或跟随系统")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                ForEach(AppearanceMode.allCases) { mode in
                    appearanceOption(mode)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 12, shadowRadius: 16, shadowY: 8)
    }

    private func appearanceOption(_ mode: AppearanceMode) -> some View {
        let isSelected = settings.appearance == mode

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.appearance = mode
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(mode.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? ChatChrome.ink : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .liquidGlass(
                cornerRadius: 10,
                tint: isSelected ? .accent : .none,
                interactive: true,
                fallbackFill: ChatChrome.field,
                fallbackStroke: isSelected ? Color.accentColor.opacity(0.32) : ChatChrome.softLine,
                shadowRadius: 6,
                shadowY: 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum SettingsHubRoute: Hashable {
    case providerList
    case providerEditor(UUID)
    case assistantList
    case backup
    case storage
}

struct ProviderListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

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
                    LazyVStack(spacing: 12) {
                        ForEach(settings.providers) { provider in
                            providerRow(provider)
                        }

                        addProviderButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .liquidGlassContainer(spacing: 14)
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: settings.providers)
        .animation(.easeInOut(duration: 0.2), value: settings.activeProviderID)
    }

    private var header: some View {
        SettingsHeaderBar(
            title: "供应商",
            subtitle: "\(settings.providers.count) 个供应商，点圆点设为当前",
            backSymbol: "chevron.left",
            backLabel: "返回设置"
        ) {
            dismiss()
        }
    }

    private func providerRow(_ provider: ProviderProfile) -> some View {
        let isActive = provider.id == settings.activeProviderID

        return HStack(spacing: 12) {
            Button {
                settings.setActiveProvider(provider.id)
            } label: {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isActive ? "当前供应商" : "设为当前供应商")

            NavigationLink(value: SettingsHubRoute.providerEditor(provider.id)) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(provider.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ChatChrome.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(rowSubtitle(provider))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
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

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
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
            .contextMenu {
                if settings.providers.count > 1 {
                    Button(role: .destructive) {
                        settings.deleteProvider(provider.id)
                    } label: {
                        Label("删除供应商", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func rowSubtitle(_ provider: ProviderProfile) -> String {
        let host: String = {
            let trimmed = provider.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
                return "未配置接口"
            }
            return host
        }()

        let model = provider.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? host : "\(host) · \(model)"
    }

    private var addProviderButton: some View {
        Button {
            settings.addProvider()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))

                Text("添加供应商")
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 12, tint: .accent, interactive: true, shadowRadius: 10, shadowY: 5)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

struct ProviderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

    let providerID: UUID

    @State private var name = ""
    @State private var baseURLString = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var selectedModels: Set<String> = []
    @State private var systemPrompt = ""
    @State private var temperature = 0.7
    @State private var validationMessage: String?
    @State private var fetchedModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelFetchMessage: String?
    @State private var hasLoadedDraft = false
    @State private var showSaveSuccess = false
    @State private var saveSuccessTrigger = 0

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
                        overviewCard
                        profileSection
                        connectionSection
                        modelSection
                        behaviorSection

                        if let validationMessage {
                            feedbackCard(
                                title: "保存失败",
                                message: validationMessage,
                                tint: .red
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 118)
                    .liquidGlassContainer(spacing: 18)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }

            if showSaveSuccess {
                saveSuccessToast
                    .padding(.top, 8)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .sensoryFeedback(.success, trigger: saveSuccessTrigger)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { destination in
            if destination == "modelManager" {
                ModelManagerView(
                    model: $model,
                    selectedModels: $selectedModels,
                    fetchedModels: fetchedModels
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            footerBar
        }
        .onAppear {
            guard !hasLoadedDraft else {
                return
            }

            hasLoadedDraft = true
            loadDraft()
        }
        .onChange(of: baseURLString) { _, _ in
            resetFetchedModels()
        }
        .onChange(of: apiKey) { _, _ in
            resetFetchedModels()
        }
    }

    private var header: some View {
        SettingsHeaderBar(
            title: name.isEmpty ? "供应商设置" : name,
            subtitle: "连接与生成参数",
            backSymbol: "chevron.left",
            backLabel: "返回供应商列表"
        ) {
            dismiss()
        }
    }

    private var profileSection: some View {
        SettingsSection(
            title: "名称",
            subtitle: "用于在供应商列表与聊天顶部区分"
        ) {
            SettingsField(title: "供应商名称", symbol: "tag") {
                TextField("例如 OpenAI、Azure、本地", text: $name)
                    .settingsInputStyle()
            }
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("当前会话")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                overviewPill(title: "接口", value: compactHost)
                overviewPill(title: "模型", value: compactModel)
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 12, shadowRadius: 16, shadowY: 8)
    }

    private var connectionSection: some View {
        SettingsSection(
            title: "接口",
            subtitle: "Base URL 与 API Key"
        ) {
            SettingsField(title: "Base URL", symbol: "link") {
                TextField("https://api.openai.com/v1", text: $baseURLString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .settingsInputStyle()
            }

            SettingsField(title: "API Key", symbol: "key") {
                SecureField("sk-...", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .settingsInputStyle()
            }
        }
    }

    private var modelSection: some View {
        SettingsSection(
            title: "模型",
            subtitle: "多选接口返回的模型，并指定当前使用项"
        ) {
            SettingsField(title: "当前模型", symbol: "cpu") {
                TextField("gpt-4o-mini", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .settingsInputStyle()
            }

            Button {
                Task {
                    await fetchModels()
                }
            } label: {
                HStack(spacing: 10) {
                    if isLoadingModels {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 16, weight: .semibold))
                    }

                    Text(isLoadingModels ? "正在拉取模型…" : "自动拉取模型")
                        .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(ChatChrome.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(
                    cornerRadius: 10,
                    interactive: true,
                    fallbackFill: ChatChrome.field,
                    shadowRadius: 8,
                    shadowY: 4
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoadingModels)
            .opacity(isLoadingModels ? 0.72 : 1)

            SettingsField(title: "模型列表", symbol: "list.bullet.rectangle") {
                modelManagerLink
            }

            if let modelFetchMessage {
                feedbackCard(
                    title: "接口反馈",
                    message: modelFetchMessage,
                    tint: Color.accentColor
                )
            }
        }
    }

    private var behaviorSection: some View {
        SettingsSection(
            title: "行为",
            subtitle: "System Prompt 与 temperature"
        ) {
            SettingsField(title: "System Prompt", symbol: "text.alignleft") {
                TextField("You are a helpful assistant.", text: $systemPrompt, axis: .vertical)
                    .lineLimit(3...7)
                    .settingsInputStyle()
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Temperature", systemImage: "dial.medium")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChatChrome.ink)

                    Spacer()

                    Text(temperature, format: .number.precision(.fractionLength(1)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Slider(value: $temperature, in: 0...2, step: 0.1)
                    .tint(Color.accentColor)
            }
            .padding(14)
            .liquidGlass(
                cornerRadius: 10,
                fallbackFill: ChatChrome.field,
                shadowRadius: 0,
                shadowY: 0
            )
        }
    }

    private var modelManagerLink: some View {
        NavigationLink(value: "modelManager") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedModelSummaryTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChatChrome.ink)

                    Text(selectedModelSummaryDetail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(
                cornerRadius: 10,
                interactive: true,
                fallbackFill: ChatChrome.field,
                shadowRadius: 8,
                shadowY: 4
            )
        }
        .buttonStyle(.plain)
    }

    private var footerBar: some View {
        Button {
            save()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))

                Text("保存设置")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 15)
            .liquidGlass(
                shape: Capsule(style: .continuous),
                tint: .custom(Color.accentColor.opacity(0.82)),
                interactive: true,
                fallbackFill: Color.accentColor,
                fallbackStroke: .white.opacity(0.22),
                shadowRadius: 18,
                shadowY: 10
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
        .liquidGlassContainer(spacing: 12)
    }

    private var saveSuccessToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Text("保存成功")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlass(
            shape: Capsule(style: .continuous),
            tint: .custom(Color.green.opacity(0.42)),
            fallbackFill: Color.green,
            shadowRadius: 12,
            shadowY: 6
        )
    }

    private func overviewPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChatChrome.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(
            cornerRadius: 10,
            fallbackFill: ChatChrome.field,
            shadowRadius: 0,
            shadowY: 0
        )
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

    private var compactHost: String {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            return "未设置"
        }

        return host
    }

    private var compactModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未设置" : trimmed
    }

    private var selectedModelSummaryTitle: String {
        if selectedModelOptions.isEmpty {
            return "管理已拉取模型"
        }

        return "已选 \(selectedModelOptions.count) 个模型"
    }

    private var selectedModelSummaryDetail: String {
        if selectedModelOptions.isEmpty {
            return "点开进入二级列表，可上下滑动并多选模型"
        }

        return selectedModelOptions.joined(separator: "、")
    }

    private var availableModelOptions: [String] {
        SettingsStore.normalizedModelList(
            Array(selectedModels).sorted() + fetchedModels,
            ensuring: model
        )
    }

    private var selectedModelOptions: [String] {
        let orderedSelectedModels = availableModelOptions.filter { selectedModels.contains($0) }
        return SettingsStore.normalizedModelList(orderedSelectedModels, ensuring: model)
    }

    private func loadDraft() {
        guard let provider = settings.provider(withID: providerID) else {
            return
        }

        name = provider.name
        baseURLString = provider.baseURLString
        apiKey = settings.apiKey(forID: providerID)
        model = provider.model
        selectedModels = Set(SettingsStore.normalizedModelList(provider.selectedModels, ensuring: provider.model))
        systemPrompt = provider.systemPrompt
        temperature = provider.temperature
        validationMessage = nil
        modelFetchMessage = nil
        fetchedModels = []
    }

    private func save() {
        do {
            let configuration = try settings.makeConfiguration(
                baseURLString: baseURLString,
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                temperature: temperature
            )

            guard var provider = settings.provider(withID: providerID) else {
                return
            }

            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            provider.name = trimmedName.isEmpty ? provider.name : trimmedName
            provider.baseURLString = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            provider.model = configuration.model
            provider.selectedModels = SettingsStore.normalizedModelList(selectedModelOptions, ensuring: configuration.model)
            provider.systemPrompt = systemPrompt
            provider.temperature = temperature

            settings.updateProvider(provider, apiKey: apiKey)
            name = provider.name

            validationMessage = nil
            saveSuccessTrigger += 1
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showSaveSuccess = true
            }

            Task {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                withAnimation(.easeInOut(duration: 0.25)) {
                    showSaveSuccess = false
                }
                try? await Task.sleep(nanoseconds: 260_000_000)
                dismiss()
            }
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func fetchModels() async {
        do {
            validationMessage = nil
            modelFetchMessage = nil
            isLoadingModels = true

            let connection = try settings.makeConnectionConfiguration(
                baseURLString: baseURLString,
                apiKey: apiKey
            )
            let models = try await OpenAIClient.fetchModels(using: connection)

            fetchedModels = models
            if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let firstModel = models.first {
                model = firstModel
                selectedModels.insert(firstModel)
            }

            modelFetchMessage = models.isEmpty ? "接口未返回可用模型" : "已拉取 \(models.count) 个模型，请进入模型列表勾选"
        } catch {
            validationMessage = error.localizedDescription
        }

        isLoadingModels = false
    }

    private func resetFetchedModels() {
        fetchedModels = []
        modelFetchMessage = nil
    }
}

private struct ModelManagerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var model: String
    @Binding var selectedModels: Set<String>
    let fetchedModels: [String]

    var body: some View {
        ZStack {
            ChatChrome.canvas
                .ignoresSafeArea()
                .onTapGesture {
                    dismissKeyboard()
                }

            VStack(spacing: 0) {
                header

                if availableModelOptions.isEmpty {
                    emptyState
                } else {
                    actionBar

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(availableModelOptions, id: \.self) { item in
                                modelRow(item)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .liquidGlassContainer(spacing: 12)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        SettingsHeaderBar(
            title: "模型列表",
            subtitle: "\(selectedModelOptions.count) 个已选，可上下滑动",
            backSymbol: "chevron.left",
            backLabel: "返回供应商设置"
        ) {
            dismiss()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("还没有可管理的模型")
                .font(.headline.weight(.semibold))
                .foregroundStyle(ChatChrome.ink)

            Text("先返回上一页拉取模型，或者直接填写当前模型名称。")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlass(cornerRadius: 12, shadowRadius: 14, shadowY: 8)
        .padding(16)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("全选") {
                selectedModels.formUnion(availableModelOptions)
                if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let firstModel = availableModelOptions.first {
                    model = firstModel
                }
            }
            .font(.caption.weight(.semibold))

            Button("仅当前") {
                let currentModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
                selectedModels = currentModel.isEmpty ? [] : [currentModel]
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text("\(availableModelOptions.count) 个可选")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func modelRow(_ item: String) -> some View {
        let isSelected = selectedModels.contains(item)
        let isActive = isCurrentModel(item)

        return HStack(spacing: 12) {
            Button {
                toggleSelection(for: item)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Button {
                setCurrentModel(item)
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ChatChrome.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(isActive ? "当前使用中" : "点按设为当前模型")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if isActive {
                        Text("当前")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(
                    cornerRadius: 10,
                    tint: isSelected || isActive ? .accent : .none,
                    interactive: true,
                    shadowRadius: 8,
                    shadowY: 4
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var availableModelOptions: [String] {
        SettingsStore.normalizedModelList(
            Array(selectedModels).sorted() + fetchedModels,
            ensuring: model
        )
    }

    private var selectedModelOptions: [String] {
        let orderedSelectedModels = availableModelOptions.filter { selectedModels.contains($0) }
        return SettingsStore.normalizedModelList(orderedSelectedModels, ensuring: model)
    }

    private func toggleSelection(for item: String) {
        let normalizedModel = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else {
            return
        }

        if selectedModels.contains(normalizedModel) {
            selectedModels.remove(normalizedModel)
            if isCurrentModel(normalizedModel) {
                model = selectedModels.sorted().first ?? ""
            }
        } else {
            selectedModels.insert(normalizedModel)
        }
    }

    private func setCurrentModel(_ item: String) {
        let normalizedModel = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else {
            return
        }

        selectedModels.insert(normalizedModel)
        model = normalizedModel
    }

    private func isCurrentModel(_ item: String) -> Bool {
        item == model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SettingsHeaderBar: View {
    let title: String
    let subtitle: String
    let backSymbol: String
    let backLabel: String
    let onBack: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Button(action: onBack) {
                Image(systemName: backSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ChatChrome.ink)
                    .frame(width: 38, height: 38)
                    .liquidGlass(shape: Circle(), interactive: true, shadowRadius: 8, shadowY: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(backLabel)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background {
            Rectangle()
                .fill(ChatChrome.canvas.opacity(0.86))
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(ChatChrome.softLine).frame(height: 1)
        }
        .liquidGlassContainer(spacing: 12)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(ChatChrome.ink)

                Text(subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .liquidGlass(cornerRadius: 12, shadowRadius: 14, shadowY: 8)
        }
    }
}

struct SettingsField<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ChatChrome.ink)

            content
        }
    }
}

extension View {
    func settingsInputStyle() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 12)
            .liquidGlass(
                cornerRadius: 10,
                interactive: true,
                fallbackFill: ChatChrome.field,
                shadowRadius: 0,
                shadowY: 0
            )
    }
}
