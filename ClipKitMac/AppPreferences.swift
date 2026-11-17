import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(ServiceManagement)
import ServiceManagement
#endif

// MARK: - Preference Keys

/// 应用的偏好设置键。集中定义，避免 UI、监听器与存储层使用不一致的字符串。
enum PreferenceKey {
    static let maxItems = "clipkit.maxItems"
    static let launchAtLogin = "clipkit.launchAtLogin"
    static let backgroundRunning = "clipkit.backgroundRunning"
    static let soundEnabled = "clipkit.soundEnabled"
    static let pollInterval = "clipkit.pollInterval"
    static let aiEnabled = "clipkit.aiEnabled"
    static let pasteAction = "clipkit.pasteAction"
    static let pasteAsPlainText = "clipkit.pasteAsPlainText"
    static let historyRetentionDays = "clipkit.historyRetentionDays"
    static let showDuringScreenSharing = "clipkit.showDuringScreenSharing"
    static let generateLinkPreviews = "clipkit.generateLinkPreviews"
    static let ignorePasswords = "clipkit.ignorePasswords"
    static let ignoreTransient = "clipkit.ignoreTransient"
    static let ignoredAppBundleIds = "clipkit.ignoredAppBundleIds"
    static let openHotkey = "clipkit.openHotkey"
    static let panelPosition = "clipkit.panelPosition"
}

// MARK: - App Preferences

/// 偏好设置的类型化访问入口。所有值均持久化在 UserDefaults。
enum AppPreferences {
    private static var defaults: UserDefaults { .standard }

    static func bool(_ key: String, default defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    static var maxItems: Int {
        let value = defaults.object(forKey: PreferenceKey.maxItems) as? Int ?? 500
        return max(1, value)
    }

    static var pollInterval: TimeInterval {
        let value = defaults.object(forKey: PreferenceKey.pollInterval) as? Double ?? 0.3
        return min(max(value, 0.1), 2.0)
    }

    static var soundEnabled: Bool {
        bool(PreferenceKey.soundEnabled, default: true)
    }

    static var backgroundRunning: Bool {
        bool(PreferenceKey.backgroundRunning, default: true)
    }

    static var aiEnabled: Bool {
        bool(PreferenceKey.aiEnabled, default: true)
    }

    static var pasteAsPlainText: Bool {
        bool(PreferenceKey.pasteAsPlainText, default: false)
    }

    static var showDuringScreenSharing: Bool {
        bool(PreferenceKey.showDuringScreenSharing, default: true)
    }

    static var generateLinkPreviews: Bool {
        bool(PreferenceKey.generateLinkPreviews, default: true)
    }

    static var ignorePasswords: Bool {
        bool(PreferenceKey.ignorePasswords, default: true)
    }

    static var ignoreTransient: Bool {
        bool(PreferenceKey.ignoreTransient, default: true)
    }

    static var historyRetentionDays: Int {
        defaults.object(forKey: PreferenceKey.historyRetentionDays) as? Int ?? 0
    }

    static var pasteAction: PasteAction {
        guard let raw = defaults.string(forKey: PreferenceKey.pasteAction),
              let value = PasteAction(rawValue: raw) else {
            return .activeApplication
        }
        return value
    }

    /// 默认忽略的密码/钥匙串应用。
    static let defaultIgnoredAppBundleIds = [
        "com.agilebits.onepassword",
        "com.keeweb.kdbxviewer",
        "com.apple.passwords",
        "com.apple.keychainaccess"
    ]

    static var ignoredAppBundleIds: [String] {
        if let saved = defaults.stringArray(forKey: PreferenceKey.ignoredAppBundleIds) {
            return saved
        }
        return defaultIgnoredAppBundleIds
    }

    static func setIgnoredAppBundleIds(_ ids: [String]) {
        defaults.set(Array(Set(ids)).sorted(), forKey: PreferenceKey.ignoredAppBundleIds)
        NotificationCenter.default.post(name: .clipKitPreferencesChanged, object: nil)
    }

    // MARK: Open hotkey

    static var openHotkey: Hotkey {
        guard let data = defaults.data(forKey: PreferenceKey.openHotkey),
              let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data) else {
            return .defaultOpen
        }
        return hotkey
    }

    static func setOpenHotkey(_ hotkey: Hotkey) {
        if let data = try? JSONEncoder().encode(hotkey) {
            defaults.set(data, forKey: PreferenceKey.openHotkey)
        }
        NotificationCenter.default.post(name: .clipKitPreferencesChanged, object: nil)
    }

    static func resetOpenHotkey() {
        defaults.removeObject(forKey: PreferenceKey.openHotkey)
        NotificationCenter.default.post(name: .clipKitPreferencesChanged, object: nil)
    }

    /// 将保留期限转换为最早允许的创建时间；nil 表示永久保留。
    static var historyCutoffDate: Date? {
        let days = historyRetentionDays
        guard days > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())
    }
}

// MARK: - Paste Action

enum PasteAction: String, CaseIterable, Identifiable {
    case activeApplication
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activeApplication: return String(localized: "paste.activeApp", defaultValue: "到当前活动应用")
        case .clipboard: return String(localized: "paste.clipboard", defaultValue: "到剪贴板")
        }
    }

    var detail: String {
        switch self {
        case .activeApplication:
            return String(localized: "paste.activeApp.detail", defaultValue: "将选定的项目直接粘贴到您当前正在使用的应用程序中。")
        case .clipboard:
            return String(localized: "paste.clipboard.detail", defaultValue: "将选定的项目复制到系统剪贴板，以便稍后手动粘贴。")
        }
    }
}

// MARK: - History Retention

enum HistoryRetention: Int, CaseIterable, Identifiable {
    case day = 1
    case week = 7
    case month = 30
    case year = 365
    case forever = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .day: return String(localized: "history.day", defaultValue: "天")
        case .week: return String(localized: "history.week", defaultValue: "周")
        case .month: return String(localized: "history.month", defaultValue: "个月")
        case .year: return String(localized: "history.year", defaultValue: "年")
        case .forever: return String(localized: "history.forever", defaultValue: "永久")
        }
    }

    var sliderValue: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 4)
    }

    static func fromSliderValue(_ value: Double) -> HistoryRetention {
        let index = min(max(Int(value.rounded()), 0), allCases.count - 1)
        return allCases[index]
    }
}

// MARK: - Hotkey

/// 一个可持久化的键盘快捷键。
struct Hotkey: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifiersRawValue: UInt

    static let defaultOpen = Hotkey(keyCode: 9, modifiersRawValue: NSEvent.ModifierFlags([.command, .shift]).rawValue)

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRawValue)
    }

    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    static func from(event: NSEvent) -> Hotkey {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .shift, .option, .control])
        return Hotkey(keyCode: event.keyCode, modifiersRawValue: flags.rawValue)
    }

    private static func keyName(for keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 50: "`", 36: "↩", 48: "⇥",
            49: "Space", 51: "⌫", 53: "Esc", 123: "←", 124: "→", 125: "↑", 126: "↓"
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}

// MARK: - Launch At Login

enum LaunchAtLogin {
    static var isEnabled: Bool {
        #if canImport(ServiceManagement)
        return SMAppService.mainApp.status == .enabled
        #else
        return false
        #endif
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        #if canImport(ServiceManagement)
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}

extension Notification.Name {
    static let clipKitPreferencesChanged = Notification.Name("clipKitPreferencesChanged")
}
