import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct AttachmentStore {
    static let maxInlineAttachmentBytes = 32 * 1024 * 1024

    /// 仿 kelivo 的上传压缩:重编码后的图片最长边不超过这个像素数
    static let compressedImageMaxPixels: CGFloat = 2048
    static let compressedImageJPEGQuality: CGFloat = 0.82

    private static let folderName = "Attachments"

    static func saveImportedFile(from url: URL) throws -> ChatAttachment {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let filename = url.lastPathComponent.isEmpty ? "附件" : url.lastPathComponent
        let mimeType = detectMimeType(filename: filename, data: data)

        // 从文件导入的图片也走压缩路径,和相册选图一致
        if mimeType.hasPrefix("image/") {
            return try saveImage(data: data, filename: filename, mimeType: mimeType)
        }

        return try save(
            data: data,
            filename: filename,
            mimeType: mimeType,
            kind: .file
        )
    }

    static func saveImage(data: Data, filename: String, mimeType: String?) throws -> ChatAttachment {
        let detectedMimeType = mimeType ?? detectMimeType(filename: filename, data: data)

        // GIF 压缩会丢掉动画帧,保持原样;其他图统一重编码成 JPEG 控制体积
        if detectedMimeType != "image/gif",
           let compressed = compressImageData(data),
           compressed.count < data.count {
            return try save(
                data: compressed,
                filename: filenameReplacingExtension(filename, with: "jpg"),
                mimeType: "image/jpeg",
                kind: .image
            )
        }

        return try save(
            data: data,
            filename: filename,
            mimeType: detectedMimeType,
            kind: .image
        )
    }

    /// 上传前压缩:ImageIO 直接降采样解码(不把原始大图整张读进内存),
    /// 再 JPEG 重编码。kelivo 上传时同样限制最长边 + 有损压缩。
    private static func compressImageData(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: compressedImageMaxPixels
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage).jpegData(compressionQuality: compressedImageJPEGQuality)
    }

    private static func filenameReplacingExtension(_ filename: String, with newExtension: String) -> String {
        let base = (filename as NSString).deletingPathExtension
        return base.isEmpty ? "image.\(newExtension)" : "\(base).\(newExtension)"
    }

    static func data(for attachment: ChatAttachment) throws -> Data {
        try Data(contentsOf: fileURL(for: attachment))
    }

    static func dataURL(for attachment: ChatAttachment) throws -> String {
        let data = try data(for: attachment)
        return "data:\(attachment.mimeType);base64,\(data.base64EncodedString())"
    }

    static func remove(_ attachment: ChatAttachment) {
        try? FileManager.default.removeItem(at: fileURL(for: attachment))
    }

    /// 备份恢复:按原 storedFilename 落盘,保证恢复后的消息仍能找到附件
    static func restoreFile(named storedFilename: String, data: Data) throws {
        let sanitized = sanitizedFilename(storedFilename)
        guard !sanitized.isEmpty, !sanitized.hasPrefix(".") else {
            return
        }

        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        try data.write(to: rootURL.appendingPathComponent(sanitized), options: .atomic)
    }

    static func formattedSize(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private static func save(
        data: Data,
        filename: String,
        mimeType: String,
        kind: ChatAttachment.Kind
    ) throws -> ChatAttachment {
        guard data.count <= maxInlineAttachmentBytes else {
            throw AttachmentStoreError.fileTooLarge(
                maxSize: formattedSize(maxInlineAttachmentBytes)
            )
        }

        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let storedFilename = "\(UUID().uuidString)-\(sanitizedFilename(filename))"
        try data.write(to: rootURL.appendingPathComponent(storedFilename), options: .atomic)

        return ChatAttachment(
            kind: kind,
            filename: filename,
            storedFilename: storedFilename,
            mimeType: mimeType,
            fileSize: data.count
        )
    }

    /// 附件落盘目录,StorageUsageService 扫描用量时也要访问
    static var rootURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private static func fileURL(for attachment: ChatAttachment) -> URL {
        rootURL.appendingPathComponent(attachment.storedFilename)
    }

    private static func sanitizedFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let components = filename.components(separatedBy: invalidCharacters)
        let cleaned = components.joined(separator: "-")
        return cleaned.isEmpty ? "attachment" : cleaned
    }

    private static func detectMimeType(filename: String, data: Data) -> String {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }

        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }

        if data.starts(with: [0x47, 0x49, 0x46]) {
            return "image/gif"
        }

        if isWebP(data) {
            return "image/webp"
        }

        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) {
            return "application/pdf"
        }

        if let ext = filename.split(separator: ".").last,
           let type = UTType(filenameExtension: String(ext)),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }

        return "application/octet-stream"
    }

    private static func isWebP(_ data: Data) -> Bool {
        guard data.count >= 12 else {
            return false
        }

        let riff = Data([0x52, 0x49, 0x46, 0x46])
        let webp = Data([0x57, 0x45, 0x42, 0x50])
        return data.prefix(4) == riff && data.subdata(in: 8..<12) == webp
    }
}

enum AttachmentStoreError: LocalizedError {
    case fileTooLarge(maxSize: String)

    var errorDescription: String? {
        switch self {
        case let .fileTooLarge(maxSize):
            return "附件过大，请选择不超过 \(maxSize) 的文件"
        }
    }
}

private extension Data {
    func starts(with bytes: [UInt8]) -> Bool {
        guard count >= bytes.count else {
            return false
        }

        return prefix(bytes.count).elementsEqual(bytes)
    }
}
