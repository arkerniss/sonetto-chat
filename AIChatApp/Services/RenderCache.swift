import Foundation
import SwiftUI
import UIKit
import ImageIO

/// Caches parsed markdown blocks per message. Block parsing plus inline
/// styling costs tens of milliseconds for long replies, and every keyboard
/// show/hide re-lays-out all visible bubbles — without a cache each of them
/// re-parses synchronously on the main thread, which is what made the
/// keyboard slow to appear.
enum MarkdownCache {
    private final class Entry {
        let contentHash: Int
        let blocks: [MarkdownBlock]

        init(contentHash: Int, blocks: [MarkdownBlock]) {
            self.contentHash = contentHash
            self.blocks = blocks
        }
    }

    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 300
        return cache
    }()

    static func blocks(for message: ChatMessage) -> [MarkdownBlock] {
        let key = message.id.uuidString as NSString
        let contentHash = message.content.hashValue

        if let entry = cache.object(forKey: key), entry.contentHash == contentHash {
            return entry.blocks
        }

        let blocks = MarkdownParser.parse(message.content)
        cache.setObject(Entry(contentHash: contentHash, blocks: blocks), forKey: key)
        return blocks
    }
}

/// Caches downsampled attachment thumbnails. Preview tiles are small (56–200pt),
/// so decoding the full-resolution image from disk on every body evaluation is
/// wasted work; ImageIO downsampling decodes straight to thumbnail size.
enum ThumbnailCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    static func thumbnail(for attachment: ChatAttachment, sidePoints: CGFloat) -> UIImage? {
        // 同一附件会以不同尺寸出现(输入框 56pt、气泡 200pt),key 必须带上尺寸,
        // 否则先缓存的小图会被放大复用导致模糊
        let key = "\(attachment.storedFilename)@\(Int(sidePoints))" as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = loadDownsampled(attachment: attachment, sidePoints: sidePoints) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    private static func loadDownsampled(attachment: ChatAttachment, sidePoints: CGFloat) -> UIImage? {
        guard let data = try? AttachmentStore.data(for: attachment),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let maxPixels = sidePoints * UIScreen.main.scale
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
