import SwiftUI
import UIKit

struct AttachmentPreview: View {
    enum Variant {
        case composer
        case bubble
    }

    let attachment: ChatAttachment
    let variant: Variant
    var onRemove: (() -> Void)?

    init(
        attachment: ChatAttachment,
        variant: Variant,
        onRemove: (() -> Void)? = nil
    ) {
        self.attachment = attachment
        self.variant = variant
        self.onRemove = onRemove
    }

    var body: some View {
        if attachment.kind == .image,
           let image = ThumbnailCache.thumbnail(for: attachment, sidePoints: imageSidePoints) {
            imageTile(image)
        } else {
            filePill
        }
    }

    /// 图片附件只露缩略图本体,不带文件名;composer 是小方块,气泡里按原始宽高比放大
    private func imageTile(_ image: UIImage) -> some View {
        let size = imageDisplaySize(for: image)
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .accessibilityLabel("移除附件")
                }
            }
            .accessibilityLabel(attachment.filename)
    }

    private var imageSidePoints: CGFloat {
        variant == .composer ? 56 : 200
    }

    private var imageCornerRadius: CGFloat {
        variant == .composer ? 10 : 14
    }

    private func imageDisplaySize(for image: UIImage) -> CGSize {
        if variant == .composer {
            return CGSize(width: 56, height: 56)
        }

        let maxSide: CGFloat = 200
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else {
            return CGSize(width: maxSide, height: maxSide)
        }

        let scale = maxSide / max(width, height)
        return CGSize(width: width * scale, height: height * scale)
    }

    private var filePill: some View {
        HStack(spacing: 8) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(AttachmentStore.formattedSize(attachment.fileSize))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: variant == .composer ? 142 : 180, alignment: .leading)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ChatChrome.ink)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("移除附件")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(height: 54)
        .liquidGlass(
            cornerRadius: 8,
            fallbackFill: background,
            fallbackStroke: strokeColor,
            shadowRadius: variant == .composer ? 6 : 0,
            shadowY: variant == .composer ? 3 : 0
        )
    }

    private var thumbnail: some View {
        Image(systemName: attachment.kind == .image ? "photo" : "doc")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: 40, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
    }

    private var background: Color {
        switch variant {
        case .composer:
            return ChatChrome.surface.opacity(0.82)
        case .bubble:
            return Color.primary.opacity(0.06)
        }
    }

    private var strokeColor: Color {
        switch variant {
        case .composer:
            return ChatChrome.softLine
        case .bubble:
            return Color.primary.opacity(0.10)
        }
    }

    private var iconColor: Color {
        attachment.kind == .image ? Color.accentColor : ChatChrome.warmAccent
    }
}
