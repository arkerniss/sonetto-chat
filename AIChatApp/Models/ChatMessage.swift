import Foundation

struct ChatAttachment: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case image
        case file
    }

    let id: UUID
    var kind: Kind
    var filename: String
    var storedFilename: String
    var mimeType: String
    var fileSize: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        filename: String,
        storedFilename: String,
        mimeType: String,
        fileSize: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.storedFilename = storedFilename
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.createdAt = createdAt
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    let id: UUID
    var role: Role
    var content: String
    var attachments: [ChatAttachment]
    var createdAt: Date
    /// 生成这条回复时所用的模型名(仅 assistant 消息有);旧数据没有此字段
    var model: String?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        attachments: [ChatAttachment] = [],
        createdAt: Date = Date(),
        model: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.createdAt = createdAt
        self.model = model
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case attachments
        case createdAt
        case model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        model = try container.decodeIfPresent(String.self, forKey: .model)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(model, forKey: .model)
    }
}

struct Conversation: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}
