#if canImport(AppKit)
import AppKit
import SwiftUI

/// 卡片视图（横条 / 竖排通用）
///
/// 布局（参考 Paste 风格）：
/// - 头部：内容类型（文件/文本/链接/图片）+ 距今时间 + 来源 App 图标（彩色背景条）
/// - 中间：内容预览
/// - 底部：文件 → 文件路径；图片/链接 → 路径 URL；文本 → 字符数
struct StripCard: View {

    let clip: Clip
    let isSelected: Bool
    let isVertical: Bool
    var onTap: () -> Void
    var onDoubleClick: () -> Void

    /// 来源 App 图标缓存（bundleId → icon）
    private static let appIconCache = NSCache<NSString, NSImage>()

    var body: some View {
        VStack(spacing: 0) {
            header

            content
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)

            footer
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: isVertical ? .infinity : 160, minHeight: 124)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.08),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
        .onTapGesture(count: 1) {
            onTap()
        }
        .contextMenu {
            Button("复制") { copyClip() }
            Button("粘贴到当前应用") { pasteClip() }
            Divider()
            Button(clip.isPinned ? "取消固定" : "固定") { togglePin() }
            Divider()
            Button("删除") { deleteClip() }
        }
    }

    // MARK: - 类型归类（文件/文本/链接/图片）

    private struct Category {
        let name: String
        let color: Color
    }

    private var category: Category {
        switch clip.type {
        case .file:  return Category(name: "文件", color: .gray)
        case .image: return Category(name: "图片", color: .purple)
        case .link:  return Category(name: "链接", color: .red)
        default:     return Category(name: "文本", color: .blue) // text/richText/code/email/phone/color
        }
    }

    // MARK: - Header（类型 + 时间 + 来源 App 图标）

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(category.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(clip.timeString)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if clip.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.9))
            }

            appIconView
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(category.color.opacity(0.85))
    }

    // MARK: - 来源 App 图标

    @ViewBuilder
    private var appIconView: some View {
        if let icon = sourceAppIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                )
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.18))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "app.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                )
        }
    }

    /// 根据 bundleId 取来源 App 图标（带缓存）
    private var sourceAppIcon: NSImage? {
        guard !clip.sourceApp.isEmpty else { return nil }
        let key = clip.sourceApp as NSString
        if let cached = Self.appIconCache.object(forKey: key) {
            return cached
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: clip.sourceApp) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 32, height: 32)
        Self.appIconCache.setObject(icon, forKey: key)
        return icon
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if clip.type == .image, let data = clip.payloadData,
           let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .clipped()
                .cornerRadius(4)

        } else if clip.type == .color {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.fromHexString(clip.text))
                    .frame(width: 20, height: 20)
                Text(clip.text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        } else if clip.type == .code {
            Text(clip.previewText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)

        } else if clip.type == .link {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Image(systemName: "link")
                        .font(.system(size: 8))
                        .foregroundColor(category.color)
                    Text(extractDomain(from: clip.text))
                        .font(.system(size: 9))
                        .foregroundColor(category.color)
                        .lineLimit(1)
                }
                Text(clip.previewText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

        } else {
            Text(clip.previewText)
                .font(.system(size: 10))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Footer（路径 / URL / 字符数）

    private var footer: some View {
        HStack(spacing: 4) {
            Text(footerText)
                .font(.system(size: 9, design: footerUsesMonospace ? .monospaced : .default))
                .foregroundColor(.secondary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
    }

    private var footerUsesMonospace: Bool {
        switch clip.type {
        case .file, .image, .link: return true
        default: return false
        }
    }

    private var footerText: String {
        switch clip.type {
        case .file:
            return displayPath ?? "文件"
        case .image:
            // 图片优先显示存储路径，无路径时退化为类型名
            return displayPath ?? "图片"
        case .link:
            return clip.text
        default:
            return "\(clip.size) 个字符"
        }
    }

    /// 文件/图片的可读路径（file:// URL → 本地路径）
    private var displayPath: String? {
        let raw = clip.filePath ?? (clip.type == .file ? clip.text : nil)
        guard let raw, !raw.isEmpty else { return nil }
        if let url = URL(string: raw), url.isFileURL {
            return url.path
        }
        return raw
    }

    // MARK: - Helpers

    private var cardBackground: Color {
        if isSelected {
            return Color(nsColor: NSColor(red: 0.14, green: 0.14, blue: 0.17, alpha: 1.0))
        }
        return Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 0.98))
    }

    private func extractDomain(from url: String) -> String {
        if let url = URL(string: url), let host = url.host {
            return host
        }
        return url
    }

    // MARK: - Context Actions

    private func copyClip() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch clip.type {
        case .image:
            if let data = clip.payloadData, let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .file:
            let pathString = clip.filePath ?? clip.text
            if let url = URL(string: pathString) {
                pasteboard.writeObjects([url as NSURL])
            } else {
                let url = URL(fileURLWithPath: pathString)
                pasteboard.writeObjects([url as NSURL])
            }
        default:
            pasteboard.setString(clip.text, forType: .string)
        }
    }

    private func pasteClip() {
        copyClip()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let cmdV = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            cmdV?.flags = .maskCommand
            let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            cmdVUp?.flags = .maskCommand
            cmdV?.post(tap: .cghidEventTap)
            cmdVUp?.post(tap: .cghidEventTap)
        }
    }

    private func togglePin() {
        NotificationCenter.default.post(
            name: .clipKitTogglePin,
            object: nil,
            userInfo: ["clipId": clip.id]
        )
    }

    private func deleteClip() {
        NotificationCenter.default.post(
            name: .clipKitDeleteClip,
            object: nil,
            userInfo: ["clipId": clip.id]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let clipKitTogglePin = Notification.Name("clipKitTogglePin")
    static let clipKitDeleteClip = Notification.Name("clipKitDeleteClip")
}

// MARK: - Color Extension

extension Color {
    static func fromHexString(_ hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let length = hexSanitized.count
        let r, g, b, a: Double

        switch length {
        case 3:
            r = Double((rgb & 0xF00) >> 8) / 15
            g = Double((rgb & 0x0F0) >> 4) / 15
            b = Double(rgb & 0x00F) / 15
            a = 1.0
        case 6:
            r = Double((rgb & 0xFF0000) >> 16) / 255
            g = Double((rgb & 0x00FF00) >> 8) / 255
            b = Double(rgb & 0x0000FF) / 255
            a = 1.0
        case 8:
            r = Double((rgb & 0xFF000000) >> 24) / 255
            g = Double((rgb & 0x00FF0000) >> 16) / 255
            b = Double((rgb & 0x00FF00) >> 8) / 255
            a = Double(rgb & 0x0000FF) / 255
        default:
            r = 0.5; g = 0.5; b = 0.5; a = 1.0
        }

        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

#endif
