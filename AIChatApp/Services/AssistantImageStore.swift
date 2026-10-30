import Foundation
import UIKit

/// 助手头像/背景图的本地文件存储。文件存放在 Documents/avatars 下,
/// Assistant 模型里只保存文件名(避免沙盒路径变化导致失效)。
enum AssistantImageStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("avatars", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 一个值是否是本地图片文件名(而非 emoji)。
    static func isLocalFile(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return value.hasSuffix(".jpg") || value.hasSuffix(".jpeg") || value.hasSuffix(".png")
    }

    static func url(forFilename filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// 把图片数据写入本地,返回文件名。压缩为 JPEG。
    @discardableResult
    static func save(imageData: Data) -> String? {
        guard let image = UIImage(data: imageData),
              let jpeg = image.jpegData(compressionQuality: 0.85) else {
            return nil
        }
        let filename = "\(UUID().uuidString).jpg"
        let dest = directory.appendingPathComponent(filename)
        do {
            try jpeg.write(to: dest)
            return filename
        } catch {
            return nil
        }
    }

    /// 删除本地文件(若是本地文件名)。emoji 等忽略。
    static func removeIfLocal(_ value: String?) {
        guard isLocalFile(value), let value else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(value))
    }

    /// 复制一份本地文件并返回新文件名;非本地文件原样返回。
    static func duplicateIfLocal(_ value: String?) -> String? {
        guard isLocalFile(value), let value else { return value }
        let src = directory.appendingPathComponent(value)
        guard FileManager.default.fileExists(atPath: src.path) else { return nil }
        let ext = (value as NSString).pathExtension
        let newName = "\(UUID().uuidString).\(ext.isEmpty ? "jpg" : ext)"
        let dest = directory.appendingPathComponent(newName)
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            return newName
        } catch {
            return nil
        }
    }
}
