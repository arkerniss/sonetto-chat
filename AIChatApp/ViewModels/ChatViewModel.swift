import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var conversations: [Conversation]
    @Published var selectedConversationID: UUID
    @Published var draft = ""
    @Published private(set) var selectedAttachments: [ChatAttachment] = []
    @Published var isSending = false
    @Published var errorMessage: String?

    private static let conversationsKey = "savedConversations"
    private static let selectedConversationKey = "selectedConversationID"

    private let defaults: UserDefaults
    private var activeTask: Task<Void, Never>?
    private var restoreObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initialConversations: [Conversation]

        if let loadedConversations = Self.loadConversations(from: defaults, key: Self.conversationsKey),
           !loadedConversations.isEmpty {
            initialConversations = loadedConversations.sorted(by: Self.sortConversations)
        } else {
            initialConversations = [Conversation()]
        }
        self.conversations = initialConversations

        let savedSelection = defaults.string(forKey: Self.selectedConversationKey)
            .flatMap(UUID.init(uuidString:))
        if let savedSelection,
           initialConversations.contains(where: { $0.id == savedSelection }) {
            self.selectedConversationID = savedSelection
        } else {
            self.selectedConversationID = initialConversations[0].id
        }

        persist()

        // 备份恢复后从 UserDefaults 重新加载对话(rikkahub 是杀进程重启,
        // 这里热加载即可)
        restoreObserver = NotificationCenter.default.addObserver(
            forName: .backupDidRestore,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadAfterRestore()
            }
        }
    }

    deinit {
        if let restoreObserver {
            NotificationCenter.default.removeObserver(restoreObserver)
        }
    }

    private func reloadAfterRestore() {
        activeTask?.cancel()
        isSending = false
        errorMessage = nil

        let restored = Self.loadConversations(from: defaults, key: Self.conversationsKey)?
            .sorted(by: Self.sortConversations)
        conversations = (restored?.isEmpty == false) ? restored! : [Conversation()]
        selectedConversationID = conversations[0].id
        persistSelection()
    }

    var messages: [ChatMessage] {
        selectedConversation?.messages ?? []
    }

    var selectedConversationTitle: String {
        selectedConversation?.title ?? ""
    }

    var canSend: Bool {
        !isSending && (!trimmedDraft.isEmpty || !selectedAttachments.isEmpty)
    }

    func selectConversation(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else {
            return
        }

        selectedConversationID = id
        errorMessage = nil
        persistSelection()
    }

    func startNewConversation() {
        guard !isSending else {
            return
        }

        let conversation = Conversation()
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        clearPendingAttachments()
        errorMessage = nil
        persist()
    }

    func deleteConversation(_ id: UUID) {
        guard !isSending,
              let removedIndex = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }

        // 附件文件不随对话 JSON 一起消失,不删会留孤儿文件占空间
        for message in conversations[removedIndex].messages {
            for attachment in message.attachments {
                AttachmentStore.remove(attachment)
            }
        }

        conversations.remove(at: removedIndex)

        if conversations.isEmpty {
            let conversation = Conversation()
            conversations = [conversation]
            selectedConversationID = conversation.id
        } else if selectedConversationID == id {
            let nextIndex = min(removedIndex, conversations.count - 1)
            selectedConversationID = conversations[nextIndex].id
        }

        errorMessage = nil
        persist()
    }

    func deleteMessage(_ messageID: UUID) {
        guard !isSending else {
            return
        }

        mutateConversation(id: selectedConversationID) { conversation in
            if let message = conversation.messages.first(where: { $0.id == messageID }) {
                for attachment in message.attachments {
                    AttachmentStore.remove(attachment)
                }
            }
            conversation.messages.removeAll { $0.id == messageID }
        }
    }

    func editMessage(_ messageID: UUID, newContent: String) {
        guard !isSending else {
            return
        }

        mutateConversation(id: selectedConversationID) { conversation in
            guard let index = conversation.messages.firstIndex(where: { $0.id == messageID }) else {
                return
            }

            conversation.messages[index].content = newContent
            conversation.updatedAt = Date()
            refreshTitle(for: &conversation)
        }
    }

    /// 重新生成：丢弃目标消息（及其之后的所有消息），用截断后的历史重新请求一次。
    /// - 对 assistant 消息：删掉它本身及后续，基于之前的对话重答。
    /// - 对 user 消息：保留该用户消息，删掉其后的回复，重新作答。
    func regenerate(messageID: UUID, using settings: SettingsStore, assistant: Assistant) {
        guard !isSending,
              let currentConversation = selectedConversation,
              let index = currentConversation.messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        let target = currentConversation.messages[index]
        let cutoffIndex: Int
        switch target.role {
        case .assistant:
            cutoffIndex = index
        case .user:
            cutoffIndex = index + 1
        case .system:
            return
        }

        do {
            let configuration = try makeAssistantConfiguration(assistant: assistant, settings: settings)
            settings.save()
            errorMessage = nil

            let conversationID = selectedConversationID

            mutateConversation(id: conversationID) { conversation in
                if cutoffIndex < conversation.messages.count {
                    for message in conversation.messages[cutoffIndex...] {
                        for attachment in message.attachments {
                            AttachmentStore.remove(attachment)
                        }
                    }
                    conversation.messages.removeSubrange(cutoffIndex...)
                }
                conversation.updatedAt = Date()
            }

            let rawHistory = conversation(withID: conversationID)?
                .messages
                .filter { !$0.content.isEmpty || !$0.attachments.isEmpty } ?? []

            guard !rawHistory.isEmpty else {
                return
            }

            let history = buildHistory(rawMessages: rawHistory, assistant: assistant)

            let assistantMessage = ChatMessage(role: .assistant, content: "", model: configuration.model)
            appendMessages([assistantMessage], to: conversationID)

            startStreaming(
                history: history,
                assistantID: assistantMessage.id,
                conversationID: conversationID,
                configuration: configuration
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markdownExportFile(for conversation: Conversation) throws -> URL {
        let markdown = Self.makeMarkdownExport(for: conversation)
        let filename = "\(Self.sanitizedFilename(from: conversation.title))-对话记录.md"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func attachImportedFile(from url: URL) {
        do {
            selectedAttachments.append(try AttachmentStore.saveImportedFile(from: url))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func attachImage(data: Data, suggestedFilename: String, mimeType: String?) {
        do {
            selectedAttachments.append(try AttachmentStore.saveImage(
                data: data,
                filename: suggestedFilename,
                mimeType: mimeType
            ))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeSelectedAttachment(_ attachment: ChatAttachment) {
        guard let index = selectedAttachments.firstIndex(where: { $0.id == attachment.id }) else {
            return
        }

        let removed = selectedAttachments.remove(at: index)
        AttachmentStore.remove(removed)
    }

    func send(using settings: SettingsStore, assistant: Assistant) {
        let text = trimmedDraft
        let attachments = selectedAttachments
        guard (!text.isEmpty || !attachments.isEmpty), !isSending else {
            return
        }

        do {
            let configuration = try makeAssistantConfiguration(assistant: assistant, settings: settings)
            settings.save()

            draft = ""
            selectedAttachments = []
            errorMessage = nil

            let conversationID = selectedConversationID
            let userMessage = ChatMessage(
                role: .user,
                content: text,
                attachments: attachments
            )
            let assistantMessage = ChatMessage(role: .assistant, content: "", model: configuration.model)
            appendMessages([userMessage, assistantMessage], to: conversationID)

            let rawMessages = conversation(withID: conversationID)?
                .messages
                .filter { !$0.content.isEmpty || !$0.attachments.isEmpty } ?? []

            let conversationMessages = buildHistory(rawMessages: rawMessages, assistant: assistant)

            startStreaming(
                history: conversationMessages,
                assistantID: assistantMessage.id,
                conversationID: conversationID,
                configuration: configuration
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 助手请求组装

    /// 用助手设置构造请求配置:模型、系统提示词(变量替换 + 记忆注入)、采样参数、流式开关。
    private func makeAssistantConfiguration(assistant: Assistant, settings: SettingsStore) throws -> ChatConfiguration {
        // 助手可覆盖模型,否则用当前供应商模型
        let model = assistant.chatModelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = (model?.isEmpty == false ? model! : settings.model)

        // 系统提示词:替换变量
        var systemPrompt = PromptKit.substituteSystemPrompt(
            assistant.systemPrompt,
            assistant: assistant,
            modelID: resolvedModel
        )
        // 记忆注入
        if assistant.enableMemory {
            let memories = assistant.memories
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !memories.isEmpty {
                let memoryBlock = "以下是你需要记住的信息:\n" + memories.map { "- \($0)" }.joined(separator: "\n")
                systemPrompt = systemPrompt.isEmpty ? memoryBlock : "\(systemPrompt)\n\n\(memoryBlock)"
            }
        }

        return try settings.makeConfiguration(
            baseURLString: settings.baseURLString,
            apiKey: settings.apiKey,
            model: resolvedModel,
            systemPrompt: systemPrompt,
            temperature: assistant.temperature,
            topP: assistant.topP,
            maxTokens: assistant.maxTokens,
            stream: assistant.streamOutput
        )
    }

    /// 组装发送给模型的历史:预设消息 + 上下文截断 + 消息模板 + 发送侧正则。
    private func buildHistory(rawMessages: [ChatMessage], assistant: Assistant) -> [ChatMessage] {
        // 1. 上下文截断(只截真实对话,不含预设)
        var conversation = rawMessages
        if assistant.limitContextMessages {
            let size = max(Assistant.minContextMessageSize, assistant.contextMessageSize)
            if conversation.count > size {
                conversation = Array(conversation.suffix(size))
            }
        }

        // 2. 对真实消息套消息模板 + 发送侧正则
        let transformed: [ChatMessage] = conversation.map { message in
            guard message.role != .system else { return message }
            var content = message.content
            // 仅在纯文本消息上套模板(带附件的多模态消息保持原文)
            if message.attachments.isEmpty {
                content = PromptKit.applyMessageTemplate(
                    assistant.messageTemplate,
                    role: message.role,
                    message: content
                )
            }
            content = PromptKit.applyRegexRules(
                assistant.regexRules,
                to: content,
                role: message.role,
                forDisplay: false
            )
            var copy = message
            copy.content = content
            return copy
        }

        // 3. 预设消息插到最前面
        let presets = assistant.presetMessages
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { ChatMessage(role: $0.role, content: $0.content) }

        return presets + transformed
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isSending = false
    }

    private func startStreaming(
        history: [ChatMessage],
        assistantID: UUID,
        conversationID: UUID,
        configuration: ChatConfiguration
    ) {
        let client = OpenAIClient(configuration: configuration)

        isSending = true
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            do {
                if configuration.stream {
                    let stream = try await client.streamChat(messages: history)
                    for try await token in stream {
                        await MainActor.run {
                            self?.appendToken(token, assistantID: assistantID, to: conversationID)
                        }
                    }
                } else {
                    let full = try await client.completeChat(messages: history)
                    await MainActor.run {
                        self?.appendToken(full, assistantID: assistantID, to: conversationID)
                    }
                }

                await MainActor.run {
                    self?.finishStreaming()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.handleCancellation(assistantID: assistantID, in: conversationID)
                }
            } catch {
                await MainActor.run {
                    self?.handleStreamingError(
                        error,
                        assistantID: assistantID,
                        in: conversationID
                    )
                }
            }
        }
    }

    private var selectedConversation: Conversation? {
        conversation(withID: selectedConversationID)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearPendingAttachments() {
        selectedAttachments.forEach(AttachmentStore.remove)
        selectedAttachments = []
    }

    private func finishStreaming() {
        isSending = false
        activeTask = nil
        persist()
    }

    private func handleCancellation(assistantID: UUID, in conversationID: UUID) {
        isSending = false
        activeTask = nil

        mutateConversation(id: conversationID) { conversation in
            guard let index = conversation.messages.firstIndex(where: { $0.id == assistantID }) else {
                return
            }

            if conversation.messages[index].content.isEmpty {
                conversation.messages.remove(at: index)
            }
        }
    }

    private func handleStreamingError(_ error: Error, assistantID: UUID, in conversationID: UUID) {
        isSending = false
        activeTask = nil
        errorMessage = error.localizedDescription

        mutateConversation(id: conversationID) { conversation in
            guard let index = conversation.messages.firstIndex(where: { $0.id == assistantID }) else {
                return
            }

            if conversation.messages[index].content.isEmpty {
                conversation.messages[index].content = "请求出错：\(error.localizedDescription)"
            }
        }
    }

    private func appendMessages(_ newMessages: [ChatMessage], to conversationID: UUID) {
        mutateConversation(id: conversationID) { conversation in
            conversation.messages.append(contentsOf: newMessages)
            conversation.updatedAt = Date()
            refreshTitle(for: &conversation)
        }
    }

    private func appendToken(_ token: String, assistantID: UUID, to conversationID: UUID) {
        mutateConversation(id: conversationID, persistAfterMutation: false) { conversation in
            guard let index = conversation.messages.firstIndex(where: { $0.id == assistantID }) else {
                return
            }

            conversation.messages[index].content += token
            conversation.updatedAt = Date()
        }
    }

    private func mutateConversation(
        id: UUID,
        persistAfterMutation: Bool = true,
        _ update: (inout Conversation) -> Void
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }

        var updatedConversations = conversations
        update(&updatedConversations[index])
        updatedConversations.sort(by: Self.sortConversations)
        conversations = updatedConversations

        if persistAfterMutation {
            persist()
        } else {
            persistSelection()
        }
    }

    private func refreshTitle(for conversation: inout Conversation) {
        guard let firstUserMessage = conversation.messages.first(where: { message in
            message.role == .user &&
                (!message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                 !message.attachments.isEmpty)
        }) else {
            return
        }

        if !firstUserMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            conversation.title = Self.makeTitle(from: firstUserMessage.content)
        } else if let firstAttachment = firstUserMessage.attachments.first {
            conversation.title = Self.makeTitle(from: firstAttachment.filename)
        }
    }

    private func conversation(withID id: UUID) -> Conversation? {
        conversations.first(where: { $0.id == id })
    }

    private func persist() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(conversations) else {
            persistSelection()
            return
        }

        defaults.set(data, forKey: Self.conversationsKey)
        persistSelection()
    }

    private func persistSelection() {
        defaults.set(selectedConversationID.uuidString, forKey: Self.selectedConversationKey)
    }

    private static func loadConversations(from defaults: UserDefaults, key: String) -> [Conversation]? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode([Conversation].self, from: data)
    }

    private static func sortConversations(_ lhs: Conversation, _ rhs: Conversation) -> Bool {
        lhs.updatedAt > rhs.updatedAt
    }

    private static func makeTitle(from text: String) -> String {
        let compactText = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compactText.isEmpty else {
            return "新对话"
        }

        let prefix = compactText.prefix(18)
        return compactText.count > 18 ? "\(prefix)..." : String(prefix)
    }

    private static func makeMarkdownExport(for conversation: Conversation) -> String {
        var lines: [String] = [
            "# \(conversation.title)",
            "",
            "- 创建时间：\(conversation.createdAt.formatted(date: .numeric, time: .shortened))",
            "- 更新时间：\(conversation.updatedAt.formatted(date: .numeric, time: .shortened))",
            ""
        ]

        let visibleMessages = conversation.messages.filter { $0.role != .system }
        guard !visibleMessages.isEmpty else {
            lines.append("_暂无消息_")
            return lines.joined(separator: "\n")
        }

        for message in visibleMessages {
            lines.append("## \(exportRoleName(for: message.role)) · \(message.createdAt.formatted(date: .numeric, time: .shortened))")
            lines.append("")

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
        }

        return lines.joined(separator: "\n")
    }

    private static func exportRoleName(for role: ChatMessage.Role) -> String {
        switch role {
        case .system:
            return "系统"
        case .user:
            return "用户"
        case .assistant:
            return "AI"
        }
    }

    private static func sanitizedFilename(from title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        let replaced = title
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !replaced.isEmpty else {
            return "conversation"
        }

        return String(replaced.prefix(60))
    }
}
