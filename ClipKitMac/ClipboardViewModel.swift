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
                await self?.store.add(clip)
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

    func refresh() {
        Task {
            let all = await store.allClips()
            await MainActor.run {
                self.clips = all
            }
        }
    }

    func search() {
        Task {
            let results: [Clip]
            if searchQuery.isEmpty {
                var all = await store.allClips()
                if let filter = selectedFilter {
                    all = all.filter { $0.type == filter }
                }
                results = all
            } else {
                var searched = SearchEngine.search(query: searchQuery, in: await store.allClips())
                if let filter = selectedFilter {
                    searched = searched.filter { $0.type == filter }
                }
                results = searched
            }
            await MainActor.run {
                self.clips = results
            }
        }
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
