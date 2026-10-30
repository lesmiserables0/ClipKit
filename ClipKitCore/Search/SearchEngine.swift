import Foundation

/// 搜索引擎
///
/// 支持多策略搜索：
/// - 关键词匹配（子字符串）
/// - 拼音搜索（中文转拼音后匹配）
/// - 类型/应用过滤
///
/// 使用方式：
/// ```swift
/// let results = SearchEngine.search(query: "swift", in: clips)
/// let filtered = SearchEngine.filter(type: .code, in: clips)
/// ```
enum SearchEngine {

    /// 综合搜索
    /// - Parameters:
    ///   - query: 搜索词
    ///   - clips: 待搜索的记录
    /// - Returns: 匹配的记录，按相关度排序
    static func search(query: String, in clips: [Clip]) -> [Clip] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return clips }

        let lowerQ = q.lowercased()
        let pinyinQ = pinyin(of: q)

        // 计算每个 clip 的匹配分数
        let scored = clips.compactMap { clip -> (Clip, Int)? in
            let text = clip.searchText
            let sourceName = clip.sourceAppIcon.lowercased()

            var score = 0

            // 精确匹配
            if text == lowerQ { score += 100 }

            // 前缀匹配
            if text.hasPrefix(lowerQ) { score += 50 }

            // 子串匹配
            if text.contains(lowerQ) { score += 20 }

            // 来源 App 匹配
            if sourceName.contains(lowerQ) { score += 10 }

            // 拼音匹配（中文转拼音）
            if !pinyinQ.isEmpty && text.contains(pinyinQ) { score += 15 }

            // 拼音首字母匹配（如 "khb" 匹配 "剪贴板"）
            if pinyinQ.count >= 2 {
                let initials = pinyinInitials(of: clip.text)
                if initials.hasPrefix(pinyinQ) { score += 25 }
            }

            return score > 0 ? (clip, score) : nil
        }

        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// 按类型过滤
    static func filter(type: ClipType?, in clips: [Clip]) -> [Clip] {
        guard let type else { return clips }
        return clips.filter { $0.type == type }
    }

    /// 按来源 App 过滤
    static func filter(sourceApp: String?, in clips: [Clip]) -> [Clip] {
        guard let app = sourceApp, !app.isEmpty else { return clips }
        return clips.filter { $0.sourceApp == app }
    }

    // MARK: - Pinyin Support

    /// 中文转拼音（简易实现）
    ///
    /// 注意：这是一个基础实现。生产环境建议使用完整拼音库。
    /// macOS 上可以利用 Core Foundation 的 CFStringTokenizer 做拼音转换。
    static func pinyin(of text: String) -> String {
        // 使用 CFStringTokenizer 获取拼音
        let mutableString = NSMutableString(string: text)
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        return (mutableString as String).lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    /// 获取拼音首字母
    static func pinyinInitials(of text: String) -> String {
        let pinyin = pinyin(of: text)
        return pinyin.split(separator: " ")
            .compactMap { $0.first }
            .map(String.init)
            .joined()
            .lowercased()
    }
}
