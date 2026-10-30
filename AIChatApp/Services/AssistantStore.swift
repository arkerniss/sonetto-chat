import Foundation
import Combine

/// 助手的本地存储与生命周期管理。所有变更立即写入 UserDefaults。
@MainActor
final class AssistantStore: ObservableObject {
    @Published private(set) var assistants: [Assistant]
    @Published private(set) var currentAssistantID: UUID

    private static let assistantsKey = "assistants_v1"
    private static let currentIDKey = "current_assistant_id_v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let loaded = Self.loadAssistants(from: defaults)
        if loaded.isEmpty {
            let seeded = Self.makeDefaultAssistants()
            assistants = seeded
            currentAssistantID = seeded[0].id
            Self.persist(seeded, currentID: seeded[0].id, to: defaults)
        } else {
            assistants = loaded
            let savedID = defaults.string(forKey: Self.currentIDKey).flatMap(UUID.init(uuidString:))
            if let savedID, loaded.contains(where: { $0.id == savedID }) {
                currentAssistantID = savedID
            } else {
                currentAssistantID = loaded[0].id
            }
        }
    }

    // MARK: - 查询

    var currentAssistant: Assistant {
        assistants.first(where: { $0.id == currentAssistantID }) ?? assistants[0]
    }

    func assistant(withID id: UUID) -> Assistant? {
        assistants.first(where: { $0.id == id })
    }

    // MARK: - 选择

    func setCurrent(_ id: UUID) {
        guard assistants.contains(where: { $0.id == id }) else { return }
        currentAssistantID = id
        defaults.set(id.uuidString, forKey: Self.currentIDKey)
    }

    // MARK: - 增删改

    @discardableResult
    func addAssistant(name: String) -> Assistant {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistant = Assistant(name: trimmed.isEmpty ? "新助手" : trimmed)
        assistants.append(assistant)
        persist()
        return assistant
    }

    /// 仅在内存与磁盘里更新某个助手(供编辑页逐字段保存)。
    func update(_ assistant: Assistant) {
        guard let index = assistants.firstIndex(where: { $0.id == assistant.id }) else { return }
        assistants[index] = assistant
        persist()
    }

    func deleteAssistant(_ id: UUID) {
        guard assistants.count > 1,
              let index = assistants.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removed = assistants.remove(at: index)
        // 清理本地头像/背景文件,避免孤儿文件
        AssistantImageStore.removeIfLocal(removed.avatar)
        AssistantImageStore.removeIfLocal(removed.background)

        if currentAssistantID == id {
            currentAssistantID = assistants[min(index, assistants.count - 1)].id
            defaults.set(currentAssistantID.uuidString, forKey: Self.currentIDKey)
        }
        persist()
    }

    @discardableResult
    func duplicateAssistant(_ id: UUID) -> Assistant? {
        guard let index = assistants.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = assistants[index]
        let newID = UUID()
        // 复制本地头像/背景文件,避免两个助手共享同一文件后删除互相影响
        let copiedAvatar = AssistantImageStore.duplicateIfLocal(copy.avatar)
        let copiedBackground = AssistantImageStore.duplicateIfLocal(copy.background)
        copy = Assistant(
            id: newID,
            name: nextCopyName(for: copy.name),
            avatar: copiedAvatar,
            useAssistantAvatar: copy.useAssistantAvatar,
            useAssistantName: copy.useAssistantName,
            chatModelId: copy.chatModelId,
            temperature: copy.temperature,
            topP: copy.topP,
            contextMessageSize: copy.contextMessageSize,
            limitContextMessages: copy.limitContextMessages,
            streamOutput: copy.streamOutput,
            maxTokens: copy.maxTokens,
            systemPrompt: copy.systemPrompt,
            messageTemplate: copy.messageTemplate,
            background: copiedBackground,
            enableMemory: copy.enableMemory,
            memories: copy.memories,
            presetMessages: copy.presetMessages.map { PresetMessage(role: $0.role, content: $0.content) },
            regexRules: copy.regexRules.map {
                AssistantRegex(name: $0.name, pattern: $0.pattern, replacement: $0.replacement,
                               applyToUser: $0.applyToUser, applyToAssistant: $0.applyToAssistant,
                               visualOnly: $0.visualOnly, replaceOnly: $0.replaceOnly, enabled: $0.enabled)
            },
            quickPhrases: copy.quickPhrases.map { QuickPhrase(title: $0.title, content: $0.content) }
        )
        assistants.insert(copy, at: index + 1)
        persist()
        return copy
    }

    func moveAssistants(from source: IndexSet, to destination: Int) {
        assistants.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - 备份恢复:整体替换

    func restore(assistants newAssistants: [Assistant], currentID: UUID?) {
        guard !newAssistants.isEmpty else { return }
        assistants = newAssistants
        if let currentID, newAssistants.contains(where: { $0.id == currentID }) {
            currentAssistantID = currentID
        } else {
            currentAssistantID = newAssistants[0].id
        }
        persist()
    }

    // MARK: - 持久化

    private func persist() {
        Self.persist(assistants, currentID: currentAssistantID, to: defaults)
    }

    private static func persist(_ assistants: [Assistant], currentID: UUID, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(assistants) {
            defaults.set(data, forKey: assistantsKey)
        }
        defaults.set(currentID.uuidString, forKey: currentIDKey)
    }

    private static func loadAssistants(from defaults: UserDefaults) -> [Assistant] {
        guard let data = defaults.data(forKey: assistantsKey),
              let decoded = try? JSONDecoder().decode([Assistant].self, from: data) else {
            return []
        }
        return decoded
    }

    private func nextCopyName(for base: String) -> String {
        let existing = Set(assistants.map(\.name))
        var candidate = "\(base) 副本"
        var n = 2
        while existing.contains(candidate) {
            candidate = "\(base) 副本 \(n)"
            n += 1
        }
        return candidate
    }

    // MARK: - 首次启动种子

    private static func makeDefaultAssistants() -> [Assistant] {
        let defaultAssistant = Assistant(
            name: "默认助手",
            temperature: 0.6,
            systemPrompt: ""
        )

        let samplePrompt = """
        你是一个乐于助人的 AI 助手。

        当前模型:{model_name}
        当前时间:{cur_datetime}
        语言环境:{locale}
        时区:{timezone}
        设备:{device_info}
        系统版本:{system_version}

        请用简洁、友好的语气回答用户的问题。
        """

        let sampleAssistant = Assistant(
            name: "示例助手",
            temperature: 0.6,
            systemPrompt: samplePrompt
        )

        return [defaultAssistant, sampleAssistant]
    }
}
