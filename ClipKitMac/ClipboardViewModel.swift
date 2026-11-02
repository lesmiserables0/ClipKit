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

    private let store: ClipStore
    private var monitor: ClipboardMonitor?
    private var refreshTask: Task<Void, Never>?

    init() {
        self.store = ClipStore(maxItems: 500)
        self.monitor = ClipboardMonitor(store: store)
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
                await _ = self?.store.add(clip)
                self?.refresh()
            }
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
        var results = await store.allClips()
        if !searchQuery.isEmpty {
            results = SearchEngine.search(query: searchQuery, in: results)
        }
        if let filter = selectedFilter {
            results = results.filter { $0.type == filter }
        }
        clips = results
    }

    func copyClip(_ clip: Clip) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch clip.type {
        case .image:
            if let data = clip.payloadData,
               let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .file:
            // clip.text 可能是文件路径 ("/Users/...") 或 file URL 字符串 ("file:///Users/...")
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

    /// 复制并粘贴到当前焦点应用
    func copyAndPaste(_ clip: Clip) {
        copyClip(clip)

        // 模拟 Cmd+V 粘贴
        #if canImport(AppKit)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let cmdV = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // 'V' key
            cmdV?.flags = .maskCommand
            let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            cmdVUp?.flags = .maskCommand
            cmdV?.post(tap: .cghidEventTap)
            cmdVUp?.post(tap: .cghidEventTap)
        }
        #endif
    }

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
