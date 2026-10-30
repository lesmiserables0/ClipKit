import Foundation

/// 剪贴板存储管理
///
/// 负责持久化 Clip 数据到磁盘，支持：
/// - 保存 / 查询 / 删除 / 固定
/// - 历史记录上限管理
/// - 去重
/// - 搜索过滤
final actor ClipStore {

    // MARK: - Properties

    private let maxItems: Int
    private var clips: [Clip] = []
    private let storageURL: URL

    // MARK: - Init

    init(maxItems: Int = 500) {
        self.maxItems = maxItems
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let clipKitDir = appSupport.appendingPathComponent("ClipKit", isDirectory: true)
        self.storageURL = clipKitDir.appendingPathComponent("clips.json")
        // actor init 中不能调用 isolated 方法，直接内联
        let dir = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: storageURL.path) {
            if let data = try? Data(contentsOf: storageURL) {
                clips = (try? JSONDecoder().decode([Clip].self, from: data)) ?? []
            }
        }
    }

    // MARK: - Public API

    /// 添加一条剪贴板记录（自动去重）
    /// - Returns: 新增的 Clip（如果成功），nil 表示重复被忽略
    func add(_ clip: Clip) -> Clip? {
        // 去重：如果最近一条内容完全相同，跳过
        if let last = clips.first(where: { !$0.isPinned }),
           last.text == clip.text {
            return nil
        }

        clips.insert(clip, at: 0)
        enforceLimit()
        save()
        return clip
    }

    /// 获取所有记录（固定的排前面，按时间倒序）
    func allClips() -> [Clip] {
        let pinned = clips.filter(\.isPinned).sorted { $0.pinnedOrder < $1.pinnedOrder }
        let normal = clips.filter { !$0.isPinned }.sorted { $0.createdAt > $1.createdAt }
        return pinned + normal
    }

    /// 搜索
    func search(query: String) -> [Clip] {
        guard !query.isEmpty else {
            return allClips()
        }
        let q = query.lowercased()
        let all = allClips()
        return all.filter { clip in
            // 基础文本匹配
            if clip.searchText.contains(q) {
                return true
            }
            // 拼音搜索（简单实现：匹配来源App名）
            if clip.sourceAppIcon.lowercased().contains(q) {
                return true
            }
            return false
        }
    }

    /// 按 ID 获取
    func get(id: UUID) -> Clip? {
        clips.first { $0.id == id }
    }

    /// 删除
    func delete(id: UUID) {
        clips.removeAll { $0.id == id }
        save()
    }

    /// 清空所有（保留固定的）
    func clearAll(keepPinned: Bool = true) {
        if keepPinned {
            clips = clips.filter(\.isPinned)
        } else {
            clips.removeAll()
        }
        save()
    }

    /// 固定/取消固定
    func togglePin(id: UUID) {
        if let idx = clips.firstIndex(where: { $0.id == id }) {
            clips[idx].isPinned.toggle()
            if clips[idx].isPinned {
                clips[idx].pinnedOrder = maxPinnedOrder() + 1
            } else {
                clips[idx].pinnedOrder = 0
            }
            save()
        }
    }

    /// 记录数
    var count: Int { clips.count }

    // MARK: - Private

    private func ensureDirectory() {
        let dir = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            clips = try JSONDecoder().decode([Clip].self, from: data)
        } catch {
            // 文件损坏，从空开始
            clips = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(clips)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // 存储失败，静默处理（生产环境应加日志）
        }
    }

    private func enforceLimit() {
        // 只裁剪非固定的记录
        let nonPinned = clips.filter { !$0.isPinned }
        if nonPinned.count > maxItems {
            let toRemove = nonPinned.count - maxItems
            let idsToRemove = Set(nonPinned.sorted { $0.createdAt < $1.createdAt }
                .suffix(toRemove)
                .map(\.id))
            clips.removeAll { idsToRemove.contains($0.id) }
        }
    }

    private func maxPinnedOrder() -> Int {
        clips.filter(\.isPinned).map(\.pinnedOrder).max() ?? 0
    }
}
