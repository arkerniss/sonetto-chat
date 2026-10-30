import Foundation

extension Notification.Name {
    /// 备份恢复完成后广播,各 Store/ViewModel 收到后从持久层重新加载。
    /// rikkahub 恢复后是强制杀进程重启;iOS 端直接热重载,体验更好。
    static let backupDidRestore = Notification.Name("backupDidRestore")
}

/// 备份归档:单个 JSON 文件,包含设置(含 API Key)、对话记录、附件(base64)。
/// 对应 rikkahub 的 zip 包(settings.json + 数据库 + upload 目录),
/// iOS 端没有内置 zip API,而附件本身限制 32MB 以内,JSON 一把梭足够。
struct BackupArchive: Codable {
    struct ProviderBackup: Codable {
        var profile: ProviderProfile
        var apiKey: String
    }

    struct AttachmentFile: Codable {
        var storedFilename: String
        var data: Data
    }

    var version = 1
    var appName = "Sonetto Chat"
    var createdAt: Date
    var providers: [ProviderBackup]
    var activeProviderID: UUID
    var appearance: AppearanceMode
    var conversations: [Conversation]?
    var attachments: [AttachmentFile]?
}

enum BackupError: LocalizedError {
    case invalidArchive
    case unsupportedVersion(Int)
    case emptyArchive

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "备份文件格式无效,请确认选择的是本应用导出的备份"
        case .unsupportedVersion(let version):
            return "备份文件版本(\(version))过新,请先升级应用"
        case .emptyArchive:
            return "备份文件中没有可恢复的内容"
        }
    }
}

@MainActor
enum BackupService {
    static let webDAVPasswordAccount = "webdav.password"
    private static let webDAVConfigKey = "webDAVConfig"
    private static let lastBackupTimeKey = "lastBackupTime"
    private static let conversationsKey = "savedConversations"

    // MARK: - 归档构建

    static func makeArchive(
        settings: SettingsStore,
        includeConversations: Bool,
        includeAttachments: Bool
    ) -> BackupArchive {
        let conversations: [Conversation]? = includeConversations ? loadConversations() : nil

        var attachmentFiles: [BackupArchive.AttachmentFile]?
        if includeConversations, includeAttachments, let conversations {
            let referenced = conversations
                .flatMap(\.messages)
                .flatMap(\.attachments)
            var files: [BackupArchive.AttachmentFile] = []
            var seen = Set<String>()
            for attachment in referenced where !seen.contains(attachment.storedFilename) {
                seen.insert(attachment.storedFilename)
                if let data = try? AttachmentStore.data(for: attachment) {
                    files.append(.init(storedFilename: attachment.storedFilename, data: data))
                }
            }
            attachmentFiles = files
        }

        return BackupArchive(
            createdAt: Date(),
            providers: settings.providers.map {
                .init(profile: $0, apiKey: settings.apiKey(forID: $0.id))
            },
            activeProviderID: settings.activeProviderID,
            appearance: settings.appearance,
            conversations: conversations,
            attachments: attachmentFiles
        )
    }

    static func encode(_ archive: BackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// rikkahub 同款命名:backup_yyyyMMdd_HHmmss
    static func makeFilename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "backup_\(formatter.string(from: date)).json"
    }

    /// 导出到临时目录,供系统分享面板/文件 App 保存
    static func exportToFile(
        settings: SettingsStore,
        includeConversations: Bool,
        includeAttachments: Bool
    ) throws -> URL {
        let archive = makeArchive(
            settings: settings,
            includeConversations: includeConversations,
            includeAttachments: includeAttachments
        )
        let data = try encode(archive)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SonettoChat_\(makeFilename())")
        try data.write(to: url, options: .atomic)
        recordBackupTime()
        return url
    }

    // MARK: - 恢复

    /// 覆盖式恢复(rikkahub 同款语义):设置整体替换;备份里带对话则替换对话。
    static func restore(from data: Data, settings: SettingsStore) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(BackupArchive.self, from: data) else {
            throw BackupError.invalidArchive
        }
        guard archive.version <= 1 else {
            throw BackupError.unsupportedVersion(archive.version)
        }
        guard !archive.providers.isEmpty else {
            throw BackupError.emptyArchive
        }

        settings.restore(
            providers: archive.providers.map(\.profile),
            apiKeys: Dictionary(
                uniqueKeysWithValues: archive.providers.map { ($0.profile.id, $0.apiKey) }
            ),
            activeProviderID: archive.activeProviderID,
            appearance: archive.appearance
        )

        if let conversations = archive.conversations {
            for file in archive.attachments ?? [] {
                try? AttachmentStore.restoreFile(named: file.storedFilename, data: file.data)
            }
            if let encoded = try? JSONEncoder().encode(conversations) {
                UserDefaults.standard.set(encoded, forKey: conversationsKey)
            }
        }

        NotificationCenter.default.post(name: .backupDidRestore, object: nil)
    }

    // MARK: - WebDAV 配置持久化

    static func loadWebDAVConfig() -> WebDAVConfig {
        guard let data = UserDefaults.standard.data(forKey: webDAVConfigKey),
              let config = try? JSONDecoder().decode(WebDAVConfig.self, from: data) else {
            return WebDAVConfig()
        }
        return config
    }

    static func saveWebDAVConfig(_ config: WebDAVConfig, password: String) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: webDAVConfigKey)
        }
        KeychainStore.saveAPIKey(
            password.trimmingCharacters(in: .whitespacesAndNewlines),
            account: webDAVPasswordAccount
        )
    }

    static func loadWebDAVPassword() -> String {
        KeychainStore.readAPIKey(account: webDAVPasswordAccount) ?? ""
    }

    // MARK: - 最近备份时间(对应 rikkahub 的 BackupReminder lastBackupTime)

    static var lastBackupTime: Date? {
        let timestamp = UserDefaults.standard.double(forKey: lastBackupTimeKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    static func recordBackupTime() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastBackupTimeKey)
    }

    private static func loadConversations() -> [Conversation] {
        guard let data = UserDefaults.standard.data(forKey: conversationsKey),
              let conversations = try? JSONDecoder().decode([Conversation].self, from: data) else {
            return []
        }
        return conversations
    }
}
