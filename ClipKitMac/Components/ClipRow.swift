#if canImport(AppKit)
import SwiftUI

/// 水平卡片条中的单个卡片
///
/// 布局：
/// - 顶部：类型圆点+标签 + 时间
/// - 中间：内容预览
/// - 底部：字符数 + 固定标记
struct StripCard: View {

    let clip: Clip
    let isSelected: Bool
    var onTap: () -> Void
    var onDoubleClick: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(width: 160, height: 120)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        )
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(typeColor)
                .frame(width: 6, height: 6)

            Text(clip.type.displayName)
                .font(.system(size: 10))
                .foregroundColor(typeColor)

            Spacer()

            if clip.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
            }

            Text(clip.timeString)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if clip.type == .image, let data = clip.payloadData,
           let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: 140, height: 56)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

        } else if clip.type == .code {
            Text(clip.previewText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        } else if clip.type == .link {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Image(systemName: "link")
                        .font(.system(size: 8))
                        .foregroundColor(typeColor)
                    Text(extractDomain(from: clip.text))
                        .font(.system(size: 9))
                        .foregroundColor(typeColor)
                        .lineLimit(1)
                }
                Text(clip.previewText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        } else {
            Text(clip.previewText)
                .font(.system(size: 10))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            Text("\(clip.size) 字符")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.6))

            Spacer()

            if clip.isPinned {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.orange.opacity(0.7))
            }
        }
    }

    // MARK: - Helpers

    private var cardBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        return Color.white.opacity(0.05)
    }

    private var typeColor: Color {
        switch clip.type {
        case .text:        return .yellow
        case .richText:    return .yellow
        case .link:        return .red
        case .image:       return .purple
        case .file:        return .gray
        case .color:       return .pink
        case .code:        return .blue
        case .email:       return .orange
        case .phoneNumber: return .teal
        case .unknown:     return .secondary
        }
    }

    private func extractDomain(from url: String) -> String {
        if let url = URL(string: url), let host = url.host {
            return host
        }
        return url
    }

    // MARK: - Context Actions

    private func copyClip() {
        #if canImport(AppKit)
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
        #endif
    }

    private func pasteClip() {
        copyClip()
        #if canImport(AppKit)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let cmdV = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            cmdV?.flags = .maskCommand
            let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            cmdVUp?.flags = .maskCommand
            cmdV?.post(tap: .cghidEventTap)
            cmdVUp?.post(tap: .cghidEventTap)
        }
        #endif
    }

    private func togglePin() {
        // 通过全局 ViewModel 操作（这里简化为直接通知）
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
