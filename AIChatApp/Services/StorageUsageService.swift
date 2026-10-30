import Foundation

/// 仿 kelivo 的 StorageUsageService:扫描应用数据,按分类汇总用量,
/// 并提供清理操作。kelivo 扫整个 app data 目录;这边数据面更窄,
/// 对应到附件目录 + UserDefaults 里的对话 JSON + tmp 临时文件。
enum StorageUsageService {
    struct CategoryUsage: Identifiable {
        enum Key: String {
            case images
            case files
            case chatData
            case temporary
            case orphans
        }

        let key: Key
        var fileCount: Int
        var bytes: Int

        var id: String { key.rawValue }
    }

    struct Report {
        var categories: [CategoryUsage]

        var totalBytes: Int {
            categories.reduce(0) { $0 + $1.bytes }
        }

        func usage(_ key: CategoryUsage.Key) -> CategoryUsage {
            categories.first { $0.key == key }
                ?? CategoryUsage(key: key, fileCount: 0, bytes: 0)
        }
    }

    private static let conversationsKey = "savedConversations"

    static func computeReport() -> Report {
        var images = CategoryUsage(key: .images, fileCount: 0, bytes: 0)
        var files = CategoryUsage(key: .files, fileCount: 0, bytes: 0)
        var chatData = CategoryUsage(key: .chatData, fileCount: 0, bytes: 0)
        var temporary = CategoryUsage(key: .temporary, fileCount: 0, bytes: 0)
        var orphans = CategoryUsage(key: .orphans, fileCount: 0, bytes: 0)

        let conversations = loadConversations()
        // 附件按消息引用分类;目录里不被任何消息引用的文件算孤儿(可清理)
        var imageFilenames = Set<String>()
        var fileFilenames = Set<String>()
        for conversation in conversations {
            for message in conversation.messages {
                for attachment in message.attachments {
                    if attachment.kind == .image {
                        imageFilenames.insert(attachment.storedFilename)
                    } else {
                        fileFilenames.insert(attachment.storedFilename)
                    }
                }
            }
        }

        for entry in contentsWithSize(of: AttachmentStore.rootURL) {
            if imageFilenames.contains(entry.name) {
                images.fileCount += 1
                images.bytes += entry.bytes
            } else if fileFilenames.contains(entry.name) {
                files.fileCount += 1
                files.bytes += entry.bytes
            } else {
                orphans.fileCount += 1
                orphans.bytes += entry.bytes
            }
        }

        if let data = UserDefaults.standard.data(forKey: conversationsKey) {
            chatData.fileCount = conversations.count
            chatData.bytes = data.count
        }

        for entry in contentsWithSize(of: FileManager.default.temporaryDirectory) {
            temporary.fileCount += 1
            temporary.bytes += entry.bytes
        }

        return Report(categories: [images, files, chatData, temporary, orphans])
    }

    /// 清理 tmp 目录(分享导出的 .md/.png 等)。系统本身也会回收 tmp,
    /// 这里只是让用户能立刻释放。
    static func clearTemporaryFiles() {
        let fileManager = FileManager.default
        let tmpURL = fileManager.temporaryDirectory
        let items = (try? fileManager.contentsOfDirectory(
            at: tmpURL,
            includingPropertiesForKeys: nil
        )) ?? []
        for item in items {
            try? fileManager.removeItem(at: item)
        }
    }

    /// 删除附件目录里不被任何对话引用的文件
    static func clearOrphanAttachments() {
        var referenced = Set<String>()
        for conversation in loadConversations() {
            for message in conversation.messages {
                for attachment in message.attachments {
                    referenced.insert(attachment.storedFilename)
                }
            }
        }

        for entry in contentsWithSize(of: AttachmentStore.rootURL) where !referenced.contains(entry.name) {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    /// 清空全部聊天记录和附件,然后广播 backupDidRestore 让
    /// ChatViewModel 走现有的热重载路径重置成一个空对话
    static func clearAllConversations() {
        UserDefaults.standard.removeObject(forKey: conversationsKey)
        try? FileManager.default.removeItem(at: AttachmentStore.rootURL)
        NotificationCenter.default.post(name: .backupDidRestore, object: nil)
    }

    private static func loadConversations() -> [Conversation] {
        guard let data = UserDefaults.standard.data(forKey: conversationsKey),
              let conversations = try? JSONDecoder().decode([Conversation].self, from: data) else {
            return []
        }
        return conversations
    }

    private struct FileEntry {
        let url: URL
        let name: String
        let bytes: Int
    }

    private static func contentsWithSize(of directory: URL) -> [FileEntry] {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return FileEntry(url: url, name: url.lastPathComponent, bytes: values.fileSize ?? 0)
        }
    }
}
