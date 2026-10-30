import SwiftUI

/// 助手头像:支持 emoji、本地图片文件、或名称首字母回退(主题色圆圈)。
struct AssistantAvatarView: View {
    let avatar: String?
    let name: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let avatar, AssistantImageStore.isLocalFile(avatar),
               let image = loadLocalImage(avatar) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let avatar, !avatar.isEmpty, !AssistantImageStore.isLocalFile(avatar) {
                // emoji 或短字符
                Text(avatar)
                    .font(.system(size: size * 0.55))
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.accentColor.opacity(0.12)))
            } else {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.accentColor.opacity(0.12)))
            }
        }
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private func loadLocalImage(_ filename: String) -> UIImage? {
        let url = AssistantImageStore.url(forFilename: filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
