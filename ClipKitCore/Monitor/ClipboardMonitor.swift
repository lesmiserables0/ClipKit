#if canImport(AppKit)
import AppKit
import Foundation

/// 剪贴板监听器
///
/// 使用 Timer 轮询 NSPasteboard.changeCount 来检测变化。
/// 这是 macOS 上最可靠的方式（NSPasteboard 没有通知机制）。
///
/// 使用方式：
/// ```swift
/// let monitor = ClipboardMonitor(store: store)
/// monitor.start()   // 开始监听
/// monitor.stop()    // 停止监听
/// ```
final class ClipboardMonitor {

    private let store: ClipStore
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    private let queue = DispatchQueue(label: "com.clipkit.clipboard-monitor", qos: .utility)
    private let pollInterval: TimeInterval

    /// 被忽略的 App bundle ID（密码管理器等敏感应用）
    private let ignoredApps: Set<String> = [
        "com.agilebits.onepassword",       // 1Password
        "com.keeweb.kdbxviewer",           // KeeWeb
        "com.apple.passwords",             // Apple Passwords
    ]

    init(store: ClipStore, pollInterval: TimeInterval = 0.3) {
        self.store = store
        self.pollInterval = pollInterval
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Start / Stop

    func start() {
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            self?.checkPasteboard()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Core Logic

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        // 获取内容
        let pasteboardTypes = pasteboard.types?.map(\.rawValue) ?? []
        guard !pasteboardTypes.isEmpty else { return }

        // 检查是否来自被忽略的 App
        let sourceBundleId = sourceAppBundleId()
        if ignoredApps.contains(sourceBundleId) {
            return
        }

        // 检查是否标记为临时的（密码管理器隐藏内容）
        if isConcealed(pasteboardTypes) {
            return
        }

        // 提取文本内容
        guard let text = extractText(from: pasteboard) else { return }

        // 推断类型
        let clipType = ClipType.infer(from: text, pasteboardTypes: pasteboardTypes)

        // 尝试提取图片数据
        var imageData: Data? = nil
        var filePath: String? = nil
        if clipType == .image {
            imageData = extractImageData(from: pasteboard)
        }
        if clipType == .file {
            filePath = extractFilePath(from: pasteboard)
        }

        // 获取来源 App 名称
        let sourceAppName = appName(for: sourceBundleId)

        // 创建 Clip
        let clip = Clip(
            text: filePath ?? text,
            type: clipType,
            sourceApp: sourceBundleId,
            sourceAppIcon: sourceAppName,
            createdAt: Date(),
            payloadData: imageData,
            size: imageData?.count ?? text.utf8.count
        )

        // 异步存储（通过通知避免直接跨 actor 捕获）
        if let clipData = try? JSONEncoder().encode(clip) {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .clipKitNewClip,
                    object: nil,
                    userInfo: ["clipData": clipData]
                )
            }
        }
    }

    // MARK: - Content Extraction

    private func extractText(from pasteboard: NSPasteboard) -> String? {
        // 优先纯文本
        if let str = pasteboard.string(forType: .string) {
            return str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : str
        }
        // 文件 URL
        if let url = pasteboard.string(forType: .fileURL) {
            return url
        }
        return nil
    }

    private func extractImageData(from pasteboard: NSPasteboard) -> Data? {
        if let data = pasteboard.data(forType: .tiff) {
            // 压缩为 PNG 减少存储
            if let image = NSImage(data: data),
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                // 生成缩略图（最大 200x200）
                return makeThumbnail(from: png, maxSize: 200)
            }
            return data
        }
        if let data = pasteboard.data(forType: .png) {
            return makeThumbnail(from: data, maxSize: 200)
        }
        return nil
    }

    private func extractFilePath(from pasteboard: NSPasteboard) -> String? {
        guard let url = pasteboard.string(forType: .fileURL) else { return nil }
        return url
    }

    // MARK: - Helpers

    /// 检查是否为密码管理器隐藏的内容
    private func isConcealed(_ types: [String]) -> Bool {
        let concealedTypes: Set<String> = [
            "org.nspasteboard.TransientType",
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.AutoGeneratedType",
        ]
        return !concealedTypes.isDisjoint(with: Set(types))
    }

    /// 获取当前前台 App 的 Bundle ID
    private func sourceAppBundleId() -> String {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        return frontmostApp?.bundleIdentifier ?? ""
    }

    /// 获取 App 显示名
    private func appName(for bundleId: String) -> String {
        guard !bundleId.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return "Unknown"
        }
        return Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Unknown"
    }

    /// 生成缩略图
    private func makeThumbnail(from data: Data, maxSize: CGFloat) -> Data? {
        guard let image = NSImage(data: data) else { return data }
        let size = image.size
        guard size.width > maxSize || size.height > maxSize else { return data }

        let scale = min(maxSize / size.width, maxSize / size.height)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: .zero,
                   operation: .copy,
                   fraction: 1.0)
        thumbnail.unlockFocus()

        return thumbnail.tiffRepresentation
            .flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
    }
}

extension Notification.Name {
    static let clipKitNewClip = Notification.Name("clipKitNewClip")
}

#endif
