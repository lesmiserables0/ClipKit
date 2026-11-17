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
    private var pollInterval: TimeInterval

    /// 未配置自定义列表时默认忽略的密码/钥匙串应用。
    private static let defaultIgnoredAppBundleIds = [
        "com.agilebits.onepassword",
        "com.keeweb.kdbxviewer",
        "com.apple.passwords",
        "com.apple.keychainaccess"
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

    /// 设置页调整检查间隔后无需重建监听器。
    func updatePollInterval(_ interval: TimeInterval) {
        let clamped = min(max(interval, 0.1), 2.0)
        guard abs(clamped - pollInterval) > 0.001 else { return }
        pollInterval = clamped
        guard timer != nil else { return }
        stop()
        start()
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
        if ignoredAppBundleIds().contains(sourceBundleId) {
            return
        }

        // 检查密码管理器隐藏内容 / 临时内容
        if shouldIgnoreConcealed(pasteboardTypes) {
            return
        }

        // 提取文本内容。图片剪贴板可能没有文本表示，因此不能在这里直接丢弃。
        let text = extractText(from: pasteboard) ?? ""
        let clipType = ClipType.infer(from: text, pasteboardTypes: pasteboardTypes)
        guard !text.isEmpty || clipType == .image else { return }

        // 尝试提取图片数据
        var imageData: Data? = nil
        var filePath: String? = nil
        if clipType == .image {
            imageData = extractImageData(from: pasteboard)
            guard imageData != nil else { return }
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

    /// 被忽略的 App bundle ID（读取设置页配置，未配置时使用密码管理器默认列表）。
    private func ignoredAppBundleIds() -> Set<String> {
        let defaults = UserDefaults.standard
        let saved = defaults.stringArray(forKey: "clipkit.ignoredAppBundleIds")
            ?? Self.defaultIgnoredAppBundleIds
        return Set(saved)
    }

    /// 检查是否为密码管理器隐藏内容或临时内容。
    private func shouldIgnoreConcealed(_ types: [String]) -> Bool {
        let typeSet = Set(types)
        let defaults = UserDefaults.standard
        let ignorePasswords = defaults.object(forKey: "clipkit.ignorePasswords") as? Bool ?? true
        let ignoreTransient = defaults.object(forKey: "clipkit.ignoreTransient") as? Bool ?? true

        if ignorePasswords,
           typeSet.contains("org.nspasteboard.ConcealedType") {
            return true
        }
        if ignoreTransient,
           !typeSet.isDisjoint(with: [
                "org.nspasteboard.TransientType",
                "org.nspasteboard.AutoGeneratedType"
           ]) {
            return true
        }
        return false
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
