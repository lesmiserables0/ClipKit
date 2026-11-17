import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

/// 主 ViewModel
///
/// 连接 ClipboardMonitor（监听剪贴板）和 UI 层。
/// 使用 @MainActor 确保 UI 操作在主线程。
@MainActor
final class ClipboardViewModel: ObservableObject {

    @Published var clips: [Clip] = []
    @Published var searchQuery: String = ""
    @Published var selectedFilter: ClipType? = nil
    @Published var isPaused: Bool = false

    /// AI 增强开关（与设置页共享 UserDefaults 键）
    @Published var aiEnabled: Bool = true {
        didSet { UserDefaults.standard.set(aiEnabled, forKey: PreferenceKey.aiEnabled) }
    }

    private let store: ClipStore
    private var monitor: ClipboardMonitor?
    private var refreshTask: Task<Void, Never>?

    init() {
        self.store = ClipStore(maxItems: AppPreferences.maxItems)
        self.monitor = ClipboardMonitor(store: store, pollInterval: AppPreferences.pollInterval)
        self.aiEnabled = AppPreferences.aiEnabled
        setupNotificationObservers()
        startMonitoring()
        loadInitialData()
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .clipKitTogglePin,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let clipId = notification.userInfo?["clipId"] as? UUID else { return }
            Task { @MainActor in
                self?.togglePinById(clipId)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .clipKitDeleteClip,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let clipId = notification.userInfo?["clipId"] as? UUID else { return }
            Task { @MainActor in
                self?.deleteClipById(clipId)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .clipKitNewClip,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let clipData = notification.userInfo?["clipData"] as? Data,
                  let clip = try? JSONDecoder().decode(Clip.self, from: clipData) else { return }
            Task { @MainActor in
                let inserted = await self?.store.add(clip)
                self?.refresh()
                // 只有真正新增的记录才做 AI 处理，重复内容直接忽略。
                if inserted != nil {
                    self?.enrichWithAI(clip)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .clipKitPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyRuntimePreferences()
            }
        }
    }

    /// 设置页修改监听间隔、记录上限、AI 开关后即时生效。
    private func applyRuntimePreferences() {
        aiEnabled = AppPreferences.aiEnabled
        monitor?.updatePollInterval(AppPreferences.pollInterval)
        refresh()
    }

    /// 对符合条件的文本剪贴板调用 AI 增强（翻译 / JSON 格式化 / 摘要）
    private func enrichWithAI(_ clip: Clip) {
        guard aiEnabled else { return }
        let textType = clip.type == .text || clip.type == .richText || clip.type == .code
        guard textType, clip.text.count >= 15 else { return }

        let systemLanguage = Locale.preferredLanguages.first ?? "en"
        Task {
            let result = await AIProcessor.shared.process(clip.text, systemLanguage: systemLanguage)
            guard let result, result.kind != .none else { return }
            await store.updateAI(id: clip.id, output: result.output, kind: result.kind.rawValue)
            refresh()
        }
    }

    nonisolated private func togglePinById(_ id: UUID) {
        Task { @MainActor in
            await store.togglePin(id: id)
            refresh()
        }
    }

    nonisolated private func deleteClipById(_ id: UUID) {
        Task { @MainActor in
            await store.delete(id: id)
            refresh()
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        monitor?.start()
        startRefreshLoop()
    }

    func stopMonitoring() {
        monitor?.stop()
        refreshTask?.cancel()
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            monitor?.stop()
            refreshTask?.cancel()
        } else {
            monitor?.start()
            startRefreshLoop()
        }
    }

    // MARK: - Data Operations

    /// 从 store 拉取数据并应用当前搜索词与类型过滤
    /// 定时刷新循环也走这里，保证搜索/过滤状态不被周期刷新覆盖
    func refresh() {
        Task {
            await reloadClips()
        }
    }

    /// 搜索（输入框每次输入后调用；与 refresh 走同一过滤逻辑）
    func search() {
        Task {
            await reloadClips()
        }
    }

    private func reloadClips() async {
        // 记录上限与保留期限属于数据层偏好，每次刷新时同步一次；
        // ClipStore 内部只在配置变化时执行裁剪和落盘。
        await store.applyPreferences(
            maxItems: AppPreferences.maxItems,
            retentionDays: AppPreferences.historyRetentionDays
        )

        var results = await store.allClips()
        if !searchQuery.isEmpty {
            results = SearchEngine.search(query: searchQuery, in: results)
        }
        if let filter = selectedFilter {
            results = results.filter { $0.type == filter }
        }
        clips = results
    }

    // MARK: - Pasteboard

    /// 将一条记录写入系统剪贴板。
    /// - Parameter forcePlainText: 为 true 时只写入纯文本表示（设置页「始终以纯文本粘贴」）。
    func copyClip(_ clip: Clip, forcePlainText: Bool? = nil) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let plainText = forcePlainText ?? AppPreferences.pasteAsPlainText
        if plainText {
            switch clip.type {
            case .file:
                pasteboard.setString(clip.filePath ?? clip.text, forType: .string)
            case .image:
                pasteboard.setString(clip.text, forType: .string)
            default:
                pasteboard.setString(clip.text, forType: .string)
            }
            return
        }

        switch clip.type {
        case .image:
            if let data = clip.payloadData,
               let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            } else {
                pasteboard.setString(clip.text, forType: .string)
            }
        case .file:
            // clip.text 可能是文件路径 ("/Users/...") 或 file URL 字符串 ("file:///Users/...")
            let pathString = clip.filePath ?? clip.text
            let url: URL
            if let parsed = URL(string: pathString), parsed.isFileURL {
                url = parsed
            } else {
                url = URL(fileURLWithPath: pathString)
            }
            pasteboard.writeObjects([url as NSURL])
        default:
            pasteboard.setString(clip.text, forType: .string)
        }
        #endif
    }

    /// 复制并粘贴到当前焦点应用（设置页也可改为仅复制到剪贴板）。
    func copyAndPaste(_ clip: Clip) {
        copyClip(clip)

        #if canImport(AppKit)
        guard AppPreferences.pasteAction == .activeApplication else { return }
        simulatePasteShortcut()
        #endif
    }

    /// 仅把记录复制到剪贴板，不触发粘贴。双击卡片时使用。
    func copyToClipboard(_ clip: Clip) {
        copyClip(clip)
    }

    #if canImport(AppKit)
    private func simulatePasteShortcut() {
        // 给面板隐藏、目标应用重新获得焦点留出时间。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let cmdV = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // 'V' key
            cmdV?.flags = .maskCommand
            let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            cmdVUp?.flags = .maskCommand
            cmdV?.post(tap: .cghidEventTap)
            cmdVUp?.post(tap: .cghidEventTap)
        }
    }
    #endif

    func deleteClip(_ clip: Clip) {
        Task {
            await store.delete(id: clip.id)
            refresh()
        }
    }

    func togglePin(_ clip: Clip) {
        Task {
            await store.togglePin(id: clip.id)
            refresh()
        }
    }

    func clearAll(keepPinned: Bool = true) {
        Task {
            await store.clearAll(keepPinned: keepPinned)
            refresh()
        }
    }

    // MARK: - Private

    private func loadInitialData() {
        refresh()
    }

    /// 定时从 store 拉取最新数据到 UI
    /// 因为 ClipboardMonitor 在后台 actor 中写入，UI 需要定期同步
    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                if !isPaused {
                    refresh()
                }
            }
        }
    }
}
