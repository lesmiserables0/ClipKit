import Foundation

/// 剪贴板内容类型
enum ClipType: String, Codable, CaseIterable, Sendable {
    case text
    case richText
    case link
    case image
    case file
    case color
    case code
    case email
    case phoneNumber
    case unknown

    /// 从 NSPasteboard 内容自动推断类型
    static func infer(from content: String, pasteboardTypes: [String]) -> ClipType {
        // 文件路径
        if pasteboardTypes.contains("public.file-url") {
            return .file
        }
        // 图片
        if pasteboardTypes.contains("public.image") || pasteboardTypes.contains("public.tiff") {
            return .image
        }
        // 颜色 (hex 格式)
        if content.matchesHexColor() {
            return .color
        }
        // 链接
        if content.matchesURL() {
            return .link
        }
        // 邮箱
        if content.matchesEmail() {
            return .email
        }
        // 电话号码
        if content.matchesPhoneNumber() {
            return .phoneNumber
        }
        // 代码 (简单启发式)
        if content.looksLikeCode() {
            return .code
        }
        // 富文本
        if pasteboardTypes.contains("public.rtf") || pasteboardTypes.contains("public.html") {
            return .richText
        }
        // 纯文本
        return .text
    }

    var iconName: String {
        switch self {
        case .text:       return "text.alignleft"
        case .richText:   return "textformat"
        case .link:       return "link"
        case .image:      return "photo"
        case .file:       return "doc"
        case .color:      return "paintpalette"
        case .code:       return "chevron.left.forwardslash.chevron.right"
        case .email:      return "envelope"
        case .phoneNumber:return "phone"
        case .unknown:    return "questionmark.circle"
        }
    }

    var displayName: String {
        switch self {
        case .text:        return "文本"
        case .richText:    return "富文本"
        case .link:        return "链接"
        case .image:       return "图片"
        case .file:        return "文件"
        case .color:       return "颜色"
        case .code:        return "代码"
        case .email:       return "邮箱"
        case .phoneNumber: return "电话"
        case .unknown:     return "未知"
        }
    }
}

// MARK: - 启发式推断辅助 (扩展到 String)
private extension String {
    func matchesURL() -> Bool {
        guard let url = URL(string: self) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    func matchesEmail() -> Bool {
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return range(of: pattern, options: .regularExpression) != nil
    }

    func matchesPhoneNumber() -> Bool {
        let digits = filter(\.isNumber)
        return digits.count >= 7 && digits.count <= 15 && self.contains(where: \.isNumber)
    }

    func matchesHexColor() -> Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^#?([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    func looksLikeCode() -> Bool {
        let codeIndicators = ["func ", "var ", "let ", "import ", "class ", "struct ",
                              "public ", "private ", "if ", "for ", "while ", "return ",
                              "console.log", "def ", "print(", "swift", "{", "}", ";",
                              "->", "=>", "==", "!="]
        let lowercased = self
        let matchCount = codeIndicators.filter { lowercased.contains($0) }.count
        return matchCount >= 2
    }
}
