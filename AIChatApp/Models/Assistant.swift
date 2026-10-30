import Foundation

/// 预设对话消息:在每次会话最前面注入的固定开场白(user / assistant 轮流)。
struct PresetMessage: Identifiable, Codable, Equatable {
    let id: UUID
    /// 仅使用 .user / .assistant
    var role: ChatMessage.Role
    var content: String

    init(id: UUID = UUID(), role: ChatMessage.Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

/// 正则替换规则。可作用于用户消息、助手消息,可选择「仅显示」或「仅发送」。
struct AssistantRegex: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var pattern: String
    var replacement: String
    /// 是否作用于用户消息
    var applyToUser: Bool
    /// 是否作用于助手消息
    var applyToAssistant: Bool
    /// 仅影响界面显示,不改变发送给模型的内容
    var visualOnly: Bool
    /// 仅影响发送给模型的内容,不改变界面显示(与 visualOnly 互斥)
    var replaceOnly: Bool
    var enabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        pattern: String = "",
        replacement: String = "",
        applyToUser: Bool = true,
        applyToAssistant: Bool = true,
        visualOnly: Bool = false,
        replaceOnly: Bool = false,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.replacement = replacement
        self.applyToUser = applyToUser
        self.applyToAssistant = applyToAssistant
        self.visualOnly = visualOnly
        self.replaceOnly = replaceOnly
        self.enabled = enabled
    }
}

/// 一个可定制的 AI 助手(人格)。所有字段变更后立即持久化,聊天时按此组装请求。
struct Assistant: Identifiable, Codable, Equatable {
    static let defaultContextMessageSize = 64
    static let minContextMessageSize = 1
    static let maxContextMessageSize = 1024
    static let contextSliderStops = [1, 16, 32, 64, 128, 256, 512, 1024]

    let id: UUID
    var name: String
    /// emoji 字符,或 Documents/avatars 下的本地文件名;nil = 用名称首字母
    var avatar: String?
    /// 在聊天气泡中用助手头像替换模型图标
    var useAssistantAvatar: Bool
    /// 在聊天气泡中用助手名称替换模型名称
    var useAssistantName: Bool
    /// 覆盖默认模型;nil = 用当前供应商默认模型
    var chatModelId: String?
    /// nil = 不下发该参数;否则 0.0 - 2.0
    var temperature: Double?
    /// nil = 不下发该参数;否则 0.0 - 1.0
    var topP: Double?
    /// 携带的历史消息条数
    var contextMessageSize: Int
    /// 是否启用上述条数限制
    var limitContextMessages: Bool
    /// 是否流式输出
    var streamOutput: Bool
    /// nil = 不限制
    var maxTokens: Int?
    var systemPrompt: String
    /// 例如 "{{ message }}"
    var messageTemplate: String
    /// 聊天背景图:Documents/avatars 下的本地文件名;nil = 无
    var background: String?
    /// 助手记忆功能开关
    var enableMemory: Bool
    /// 手动记忆条目(发送时注入到系统提示词)
    var memories: [String]
    /// 预设对话消息
    var presetMessages: [PresetMessage]
    /// 正则替换规则
    var regexRules: [AssistantRegex]
    /// 助手作用域的快捷短语
    var quickPhrases: [QuickPhrase]

    init(
        id: UUID = UUID(),
        name: String,
        avatar: String? = nil,
        useAssistantAvatar: Bool = false,
        useAssistantName: Bool = false,
        chatModelId: String? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        contextMessageSize: Int = Assistant.defaultContextMessageSize,
        limitContextMessages: Bool = true,
        streamOutput: Bool = true,
        maxTokens: Int? = nil,
        systemPrompt: String = "",
        messageTemplate: String = "{{ message }}",
        background: String? = nil,
        enableMemory: Bool = false,
        memories: [String] = [],
        presetMessages: [PresetMessage] = [],
        regexRules: [AssistantRegex] = [],
        quickPhrases: [QuickPhrase] = []
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.useAssistantAvatar = useAssistantAvatar
        self.useAssistantName = useAssistantName
        self.chatModelId = chatModelId
        self.temperature = temperature
        self.topP = topP
        self.contextMessageSize = contextMessageSize
        self.limitContextMessages = limitContextMessages
        self.streamOutput = streamOutput
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
        self.messageTemplate = messageTemplate
        self.background = background
        self.enableMemory = enableMemory
        self.memories = memories
        self.presetMessages = presetMessages
        self.regexRules = regexRules
        self.quickPhrases = quickPhrases
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, avatar, useAssistantAvatar, useAssistantName, chatModelId
        case temperature, topP, contextMessageSize, limitContextMessages
        case streamOutput, maxTokens, systemPrompt, messageTemplate, background
        case enableMemory, memories, presetMessages, regexRules, quickPhrases
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        useAssistantAvatar = try c.decodeIfPresent(Bool.self, forKey: .useAssistantAvatar) ?? false
        useAssistantName = try c.decodeIfPresent(Bool.self, forKey: .useAssistantName) ?? false
        chatModelId = try c.decodeIfPresent(String.self, forKey: .chatModelId)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        topP = try c.decodeIfPresent(Double.self, forKey: .topP)
        contextMessageSize = try c.decodeIfPresent(Int.self, forKey: .contextMessageSize) ?? Assistant.defaultContextMessageSize
        limitContextMessages = try c.decodeIfPresent(Bool.self, forKey: .limitContextMessages) ?? true
        streamOutput = try c.decodeIfPresent(Bool.self, forKey: .streamOutput) ?? true
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens)
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        messageTemplate = try c.decodeIfPresent(String.self, forKey: .messageTemplate) ?? "{{ message }}"
        background = try c.decodeIfPresent(String.self, forKey: .background)
        enableMemory = try c.decodeIfPresent(Bool.self, forKey: .enableMemory) ?? false
        memories = try c.decodeIfPresent([String].self, forKey: .memories) ?? []
        presetMessages = try c.decodeIfPresent([PresetMessage].self, forKey: .presetMessages) ?? []
        regexRules = try c.decodeIfPresent([AssistantRegex].self, forKey: .regexRules) ?? []
        quickPhrases = try c.decodeIfPresent([QuickPhrase].self, forKey: .quickPhrases) ?? []
    }
}

/// 快捷短语:点一下插入到输入框。
struct QuickPhrase: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String

    init(id: UUID = UUID(), title: String = "", content: String = "") {
        self.id = id
        self.title = title
        self.content = content
    }
}
