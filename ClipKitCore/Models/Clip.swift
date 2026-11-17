import Foundation
import CryptoKit

/// 剪贴板记录模型
///
/// 每次复制操作产生一个 Clip 对象。
/// 文本内容直接存储在 text 字段；图片/文件存储在文件系统中，path 指向实际文件。
struct Clip: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var text: String           // 纯文本内容（图片/文件存路径）
    var type: ClipType
    var sourceApp: String      // 来源 App bundle ID
    var sourceAppIcon: String  // 来源 App 显示名
    var createdAt: Date
    var isPinned: Bool         // 是否固定到顶部
    var pinnedOrder: Int       // 固定排序（0 = 未固定）
    var filePath: String?     // 图片/文件的本地存储路径
    var bundlePath: String?   // 文件的 bundle 路径
    var payloadData: Data?    // 图片缩略图数据（用于列表快速预览）
    var size: Int             // 内容大小（字节）

    // AI 增强结果（苹果原生 Foundation Models 处理）
    var aiOutput: String?     // AI 处理后的文本（翻译/格式化 JSON/摘要）
    var aiKindRaw: String?    // AI 动作类型（AIKind.rawValue）

    // 搜索辅助
    var searchText: String {   // 拼音搜索支持的基础文本
        text.lowercased()
    }

    init(
        id: UUID = UUID(),
        text: String,
        type: ClipType,
        sourceApp: String = "",
        sourceAppIcon: String = "",
        createdAt: Date = Date(),
        isPinned: Bool = false,
        pinnedOrder: Int = 0,
        filePath: String? = nil,
        bundlePath: String? = nil,
        payloadData: Data? = nil,
        size: Int = 0
    ) {
        self.id = id
        self.text = text
        self.type = type
        self.sourceApp = sourceApp
        self.sourceAppIcon = sourceAppIcon
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.pinnedOrder = pinnedOrder
        self.filePath = filePath
        self.bundlePath = bundlePath
        self.payloadData = payloadData
        self.size = size > 0 ? size : text.utf8.count
    }

    /// 内容指纹（用于去重）。
    ///
    /// 哈希同时涵盖内容类型、文本以及图片/文件载荷，因此即使两条记录的
    /// UUID 或来源应用不同，只要实际剪贴板内容一致就会被判定为重复。
    var contentHash: String {
        var hasher = SHA256()
        hasher.update(data: Data(type.rawValue.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(text.utf8))
        if let payloadData {
            hasher.update(data: Data([0]))
            hasher.update(data: payloadData)
        }
        if let bundlePath {
            hasher.update(data: Data([0]))
            hasher.update(data: Data(bundlePath.utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 用于列表显示的预览文本（截断）
    var previewText: String {
        if text.count <= 200 {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(text.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    /// 时间格式化（用于UI显示）
    var timeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}
