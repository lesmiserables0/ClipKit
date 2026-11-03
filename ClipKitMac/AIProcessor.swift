import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// AI 对剪贴板文本的处理结果
struct AIProcessed: Identifiable, Codable, Sendable {
    let id: UUID
    let kind: AIKind
    let output: String
    let detectedLanguage: String?
    let createdAt: Date

    init(kind: AIKind, output: String, detectedLanguage: String? = nil) {
        self.id = UUID()
        self.kind = kind
        self.output = output
        self.detectedLanguage = detectedLanguage
        self.createdAt = Date()
    }
}

/// AI 处理的动作类型
enum AIKind: String, Codable, CaseIterable, Sendable {
    case translate   // 翻译
    case formatJSON  // JSON 格式化
    case summarize   // 摘要
    case none        // 无需处理
}

/// 剪贴板智能处理
///
/// 用苹果原生 Foundation Models（Apple Intelligence）处理剪贴板文本：
/// - 内容语言与系统语言不一致 → 翻译
/// - 是 JSON 字符串 → 格式化
/// - 长文本 → 总结概要
///
/// 在 macOS 14/15 SDK（无 FoundationModels）或系统不支持 Apple Intelligence 时，
/// 自动走 `#else` 降级实现（仅 JSON 美化）。
@MainActor
final class AIProcessor {

    static let shared = AIProcessor()

    /// 触发 AI 的最短文本长度（过短的复制不值得调用）
    private let minLength = 15

    /// 当前是否可用苹果原生模型
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
        #else
        return false
        #endif
    }

    /// 处理一段文本，返回 AI 结果（无需处理返回 nil）
    func process(_ text: String, systemLanguage: String) async -> AIProcessed? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minLength else { return nil }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable {
            return await processWithFoundationModels(trimmed, systemLanguage: systemLanguage)
        }
        #endif
        return fallbackProcess(trimmed, systemLanguage: systemLanguage)
    }

    // MARK: - 苹果原生 Foundation Models 实现

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func processWithFoundationModels(_ text: String, systemLanguage: String) async -> AIProcessed? {
        let session = LanguageModelSession()

        let prompt = """
        你是一个剪贴板智能助手。请判断下面这段文本的意图，并只做一件事：

        1) 如果文本是 JSON（对象或数组），将其整理为易读格式（2 空格缩进、保持键顺序、内容不变），kind = "formatJSON"。
        2) 否则，如果文本的主要语言与系统语言（\(systemLanguage)）不同，将整段翻译成系统语言，kind = "translate"。
        3) 否则，如果文本较长（超过 200 字符），用 2–3 句话概括要点，kind = "summarize"。
        4) 否则 kind = "none"（不要处理）。

        只返回一个 JSON 对象，不要任何解释，也不要使用 markdown 代码块标记：
        {"kind":"translate|formatJSON|summarize|none","language":"检测到的 BCP-47 语言码","output":"处理后的文本"}

        若 kind 为 "none"，output 留空字符串。

        --- 待处理文本 ---
        \(text)
        """

        do {
            let response = try await session.respond(to: prompt)
            return try parseResponse(response.content)
        } catch {
            return fallbackProcess(text, systemLanguage: systemLanguage)
        }
    }

    private func parseResponse(_ content: String) throws -> AIProcessed? {
        // 去除可能的 ```json ... ``` 围栏
        var raw = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("```") {
            if let newline = raw.firstIndex(of: "\n") {
                raw = String(raw[raw.index(after: newline)...])
            }
            if raw.hasSuffix("```") {
                raw = String(raw.dropLast(3))
            }
            raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = raw.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kindRaw = obj["kind"] as? String,
              let kind = AIKind(rawValue: kindRaw) else {
            return nil
        }

        let output = obj["output"] as? String ?? ""

        if kind == .none || output.isEmpty {
            return nil
        }
        let language = obj["language"] as? String
        return AIProcessed(kind: kind, output: output, detectedLanguage: language)
    }
    #endif

    // MARK: - 降级实现（无 Apple Intelligence 时）

    /// 降级实现：仅对 JSON 做美化；翻译/摘要需要模型，降级时返回 nil
    private func fallbackProcess(_ text: String, systemLanguage: String) -> AIProcessed? {
        if let json = prettyPrintJSON(text) {
            return AIProcessed(kind: .formatJSON, output: json)
        }
        return nil
    }

    private func prettyPrintJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let pretty = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            return String(data: pretty, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
