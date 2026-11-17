#if canImport(AppKit)
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// 设置窗口 —— 左侧纵向导航 + 右侧分组卡片，参考系统级剪贴板工具的设置页。
struct SettingsView: View {

    @ObservedObject var viewModel: ClipboardViewModel

    @State private var selection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(width: 860, height: 640)
        .background(Color(nsColor: NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)))
        .preferredColorScheme(.dark)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: section.icon)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 24)
                        Text(section.title)
                            .font(.system(size: 15, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selection == section ? .white : Color.primary.opacity(0.88))
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(selection == section ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                if let url = URL(string: "https://github.com/yourname/clipkit") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                    Text(String(localized: "settings.help", defaultValue: "帮助中心"))
                        .font(.system(size: 14))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: NSColor(red: 0.105, green: 0.105, blue: 0.115, alpha: 1.0)))
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:
            GeneralSettingsPage(viewModel: viewModel)
        case .intelligence:
            IntelligenceSettingsPage(viewModel: viewModel)
        case .privacy:
            PrivacySettingsPage()
        case .keyboard:
            KeyboardSettingsPage()
        case .about:
            AboutSettingsPage()
        }
    }
}

// MARK: - Sections

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case intelligence
    case privacy
    case keyboard
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "settings.general", defaultValue: "通用")
        case .intelligence: return String(localized: "settings.intelligence", defaultValue: "智能")
        case .privacy: return String(localized: "settings.privacy", defaultValue: "隐私")
        case .keyboard: return String(localized: "settings.keyboard", defaultValue: "键盘快捷键")
        case .about: return String(localized: "settings.about", defaultValue: "关于")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .intelligence: return "sparkles"
        case .privacy: return "hand.raised"
        case .keyboard: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Shared Components

private struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.top, 4)

                content
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(Color.white.opacity(0.075))
        )
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
    }
}

private struct SettingsSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.primary)
            .padding(.top, 2)
    }
}

private struct SettingToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 11)
    }
}

private struct SettingValueRow: View {
    let title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15))
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 13)
    }
}

// MARK: - General

private struct GeneralSettingsPage: View {
    @ObservedObject var viewModel: ClipboardViewModel

    @AppStorage(PreferenceKey.backgroundRunning) private var backgroundRunning = true
    @AppStorage(PreferenceKey.soundEnabled) private var soundEnabled = true
    @AppStorage(PreferenceKey.pasteAction) private var pasteActionRaw = PasteAction.activeApplication.rawValue
    @AppStorage(PreferenceKey.pasteAsPlainText) private var pasteAsPlainText = false
    @AppStorage(PreferenceKey.historyRetentionDays) private var retentionDays = 0
    @AppStorage(PreferenceKey.maxItems) private var maxItems = 500

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var showDeleteHistoryAlert = false
    @State private var launchError = false

    private var pasteAction: PasteAction {
        PasteAction(rawValue: pasteActionRaw) ?? .activeApplication
    }

    private var retention: HistoryRetention {
        HistoryRetention(rawValue: retentionDays) ?? .forever
    }

    var body: some View {
        SettingsPage(title: String(localized: "settings.general", defaultValue: "通用")) {
            SettingsGroup {
                SettingToggleRow(
                    title: String(localized: "settings.launchAtLogin", defaultValue: "登录时打开"),
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { setLaunchAtLogin($0) }
                    )
                )
                SettingsDivider()
                SettingToggleRow(
                    title: String(localized: "settings.backgroundRunning", defaultValue: "后台运行"),
                    subtitle: String(localized: "settings.backgroundRunning.detail", defaultValue: "关闭面板后仍驻留在菜单栏，随时响应快捷键。"),
                    isOn: $backgroundRunning
                )
                SettingsDivider()
                SettingValueRow(
                    title: String(localized: "settings.icloud", defaultValue: "iCloud 同步"),
                    value: String(localized: "settings.icloud.unavailable", defaultValue: "即将推出")
                )
                .opacity(0.65)
                SettingsDivider()
                SettingToggleRow(
                    title: String(localized: "settings.sound", defaultValue: "音效"),
                    subtitle: String(localized: "settings.sound.detail", defaultValue: "检测到新的剪贴板内容时播放轻提示音。"),
                    isOn: $soundEnabled
                )
            }
            .onChange(of: backgroundRunning) { _, _ in notifyPreferencesChanged() }
            .onChange(of: soundEnabled) { _, _ in notifyPreferencesChanged() }

            SettingsSectionTitle(title: String(localized: "settings.section.paste", defaultValue: "粘贴项目"))

            SettingsGroup {
                PasteActionRow(
                    action: .activeApplication,
                    selectedAction: pasteAction,
                    onSelect: { pasteActionRaw = PasteAction.activeApplication.rawValue; notifyPreferencesChanged() }
                ) {
                    PastePreviewIcon(kind: .application)
                }
                SettingsDivider()
                PasteActionRow(
                    action: .clipboard,
                    selectedAction: pasteAction,
                    onSelect: { pasteActionRaw = PasteAction.clipboard.rawValue; notifyPreferencesChanged() }
                ) {
                    PastePreviewIcon(kind: .clipboard)
                }
                SettingsDivider()
                HStack(spacing: 10) {
                    selectionCircle(isSelected: pasteAsPlainText)
                    Text(String(localized: "settings.paste.plainText", defaultValue: "始终以纯文本粘贴"))
                        .font(.system(size: 15))
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    pasteAsPlainText.toggle()
                    notifyPreferencesChanged()
                }
                .padding(.vertical, 12)
            }

            SettingsSectionTitle(title: String(localized: "settings.section.history", defaultValue: "保留历史"))

            SettingsGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { retention.sliderValue },
                            set: { newValue in
                                retentionDays = HistoryRetention.fromSliderValue(newValue).rawValue
                                notifyPreferencesChanged()
                            }
                        ),
                        in: 0...Double(HistoryRetention.allCases.count - 1),
                        step: 1
                    )
                    .tint(.white)

                    HStack {
                        ForEach(HistoryRetention.allCases) { item in
                            Text(item.title)
                                .font(.system(size: 13))
                                .foregroundStyle(retention == item ? .primary : .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    SettingsDivider()

                    HStack {
                        Text(String(localized: "settings.maxItems.title", defaultValue: "最多保留记录"))
                            .font(.system(size: 14))
                        Spacer()
                        Stepper(
                            String(format: String(localized: "settings.maxItems.value", defaultValue: "%d 条"), maxItems),
                            value: $maxItems,
                            in: 100...5000,
                            step: 100
                        )
                        .onChange(of: maxItems) { _, _ in notifyPreferencesChanged() }
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            showDeleteHistoryAlert = true
                        } label: {
                            Text(String(localized: "settings.deleteHistory", defaultValue: "删除历史…"))
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.bottom, 8)
                }
                .padding(.vertical, 12)
            }
        }
        .alert(
            String(localized: "settings.deleteHistory.title", defaultValue: "删除所有历史记录？"),
            isPresented: $showDeleteHistoryAlert
        ) {
            Button(String(localized: "settings.cancel", defaultValue: "取消"), role: .cancel) {}
            Button(String(localized: "settings.delete", defaultValue: "删除"), role: .destructive) {
                viewModel.clearAll(keepPinned: false)
            }
        } message: {
            Text(String(localized: "settings.deleteHistory.message", defaultValue: "固定的项目也会被删除，此操作无法撤销。"))
        }
        .alert(
            String(localized: "settings.launchAtLogin.error.title", defaultValue: "无法修改登录项"),
            isPresented: $launchError
        ) {
            Button(String(localized: "settings.ok", defaultValue: "好"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.launchAtLogin.error.message", defaultValue: "请检查系统设置中的登录项权限后重试。"))
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if LaunchAtLogin.setEnabled(enabled) {
            launchAtLogin = enabled
        } else {
            launchAtLogin = LaunchAtLogin.isEnabled
            launchError = true
        }
    }

    private func selectionCircle(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Color.white : Color.secondary.opacity(0.65), lineWidth: 1.5)
                .frame(width: 17, height: 17)
            if isSelected {
                Circle()
                    .fill(Color.white)
                    .frame(width: 9, height: 9)
            }
        }
    }
}

private struct PasteActionRow<Preview: View>: View {
    let action: PasteAction
    let selectedAction: PasteAction
    let onSelect: () -> Void
    @ViewBuilder var preview: Preview

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(selectedAction == action ? Color.white : Color.secondary.opacity(0.65), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                if selectedAction == action {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.system(size: 15))
                Text(action.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            preview
                .frame(width: 94, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

private struct PastePreviewIcon: View {
    enum Kind { case application, clipboard }
    let kind: Kind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(kind == .application ? Color.orange.opacity(0.88) : Color.blue.opacity(0.82))
            Image(systemName: kind == .application ? "macwindow" : "doc.on.clipboard")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Intelligence

private struct IntelligenceSettingsPage: View {
    @ObservedObject var viewModel: ClipboardViewModel

    private var aiAvailable: Bool { AIProcessor.shared.isAvailable }

    var body: some View {
        SettingsPage(title: String(localized: "settings.intelligence", defaultValue: "智能")) {
            SettingsGroup {
                SettingToggleRow(
                    title: String(localized: "settings.aiEnabled", defaultValue: "启用 AI 增强"),
                    subtitle: String(localized: "settings.aiEnabled.detail", defaultValue: "自动翻译、格式化 JSON 和总结长文本。所有处理均在本机完成。"),
                    isOn: $viewModel.aiEnabled
                )
                SettingsDivider()
                SettingValueRow(
                    title: String(localized: "settings.ai.model", defaultValue: "Apple 智能"),
                    value: aiAvailable
                        ? String(localized: "settings.ai.available", defaultValue: "可用")
                        : String(localized: "settings.ai.unavailable", defaultValue: "当前系统不可用，使用本地降级处理")
                )
            }

            SettingsSectionTitle(title: String(localized: "settings.ai.features", defaultValue: "自动处理"))

            SettingsGroup {
                FeatureRow(icon: "character.bubble", title: String(localized: "ai.translate", defaultValue: "翻译"), detail: String(localized: "settings.ai.translate.detail", defaultValue: "文本语言与系统语言不一致时自动翻译。"))
                SettingsDivider()
                FeatureRow(icon: "curlybraces", title: String(localized: "ai.format", defaultValue: "JSON 格式化"), detail: String(localized: "settings.ai.format.detail", defaultValue: "识别 JSON 并生成两空格缩进的易读版本。"))
                SettingsDivider()
                FeatureRow(icon: "text.alignleft", title: String(localized: "ai.summary", defaultValue: "摘要"), detail: String(localized: "settings.ai.summary.detail", defaultValue: "长文本自动提取两到三句核心要点。"))
            }

            Text(String(localized: "settings.ai.privacyNote", defaultValue: "ClipKit 不会把剪贴板内容发送到网络；不支持 Apple 智能的设备只会执行本地 JSON 美化。"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 11)
    }
}

// MARK: - Privacy

private struct PrivacySettingsPage: View {
    @AppStorage(PreferenceKey.showDuringScreenSharing) private var showDuringScreenSharing = true
    @AppStorage(PreferenceKey.generateLinkPreviews) private var generateLinkPreviews = true
    @AppStorage(PreferenceKey.ignorePasswords) private var ignorePasswords = true
    @AppStorage(PreferenceKey.ignoreTransient) private var ignoreTransient = true

    @State private var ignoredAppBundleIds = AppPreferences.ignoredAppBundleIds
    @State private var selectedIgnoredAppBundleId: String?

    var body: some View {
        SettingsPage(title: String(localized: "settings.privacy", defaultValue: "隐私")) {
            SettingsGroup {
                SettingToggleRow(
                    title: String(localized: "settings.privacy.showDuringSharing", defaultValue: "在屏幕共享期间显示"),
                    subtitle: String(localized: "settings.privacy.showDuringSharing.detail", defaultValue: "允许在共享屏幕时向其他人显示 ClipKit 面板。"),
                    isOn: $showDuringScreenSharing
                )
                SettingsDivider()
                SettingToggleRow(
                    title: String(localized: "settings.privacy.linkPreview", defaultValue: "生成链接预览"),
                    subtitle: String(localized: "settings.privacy.linkPreview.detail", defaultValue: "保存链接时提取域名并生成快速预览。"),
                    isOn: $generateLinkPreviews
                )
            }
            .onChange(of: showDuringScreenSharing) { _, _ in notifyPreferencesChanged() }
            .onChange(of: generateLinkPreviews) { _, _ in notifyPreferencesChanged() }

            SettingsGroup {
                SettingToggleRow(
                    title: String(localized: "settings.privacy.ignorePasswords", defaultValue: "忽略机密内容"),
                    subtitle: String(localized: "settings.privacy.ignorePasswords.detail", defaultValue: "检测到密码和敏感数据时不保存。"),
                    isOn: $ignorePasswords
                )
                SettingsDivider()
                SettingToggleRow(
                    title: String(localized: "settings.privacy.ignoreTransient", defaultValue: "忽略瞬时内容"),
                    subtitle: String(localized: "settings.privacy.ignoreTransient.detail", defaultValue: "不要保存其他应用程序生成的临时数据。"),
                    isOn: $ignoreTransient
                )
            }
            .onChange(of: ignorePasswords) { _, _ in notifyPreferencesChanged() }
            .onChange(of: ignoreTransient) { _, _ in notifyPreferencesChanged() }

            VStack(alignment: .leading, spacing: 5) {
                SettingsSectionTitle(title: String(localized: "settings.privacy.ignoredApps", defaultValue: "忽略应用程序"))
                Text(String(localized: "settings.privacy.ignoredApps.detail", defaultValue: "不要保存从以下应用程序复制的内容。"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            SettingsGroup {
                VStack(spacing: 0) {
                    ForEach(ignoredAppBundleIds, id: \.self) { bundleId in
                        IgnoredAppRow(
                            bundleId: bundleId,
                            isSelected: selectedIgnoredAppBundleId == bundleId
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedIgnoredAppBundleId = bundleId
                        }
                        if bundleId != ignoredAppBundleIds.last {
                            SettingsDivider()
                        }
                    }

                    if ignoredAppBundleIds.isEmpty {
                        Text(String(localized: "settings.privacy.ignoredApps.empty", defaultValue: "尚未忽略任何应用程序"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                    }

                    SettingsDivider()
                    HStack(spacing: 12) {
                        Button {
                            addIgnoredApplications()
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "settings.privacy.ignoredApps.add", defaultValue: "添加应用程序"))

                        Divider().frame(height: 16)

                        Button {
                            removeSelectedIgnoredApplication()
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedIgnoredAppBundleId == nil)
                        .help(String(localized: "settings.privacy.ignoredApps.remove", defaultValue: "移除应用程序"))

                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private func addIgnoredApplications() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "settings.privacy.ignoredApps.panelTitle", defaultValue: "选择要忽略的应用程序")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK else { return }
        var updated = ignoredAppBundleIds
        for url in panel.urls {
            if let bundleId = Bundle(url: url)?.bundleIdentifier,
               !updated.contains(bundleId) {
                updated.append(bundleId)
            }
        }
        ignoredAppBundleIds = updated.sorted()
        AppPreferences.setIgnoredAppBundleIds(ignoredAppBundleIds)
    }

    private func removeSelectedIgnoredApplication() {
        guard let id = selectedIgnoredAppBundleId else { return }
        ignoredAppBundleIds.removeAll { $0 == id }
        selectedIgnoredAppBundleId = nil
        AppPreferences.setIgnoredAppBundleIds(ignoredAppBundleIds)
    }
}

private struct IgnoredAppRow: View {
    let bundleId: String
    let isSelected: Bool

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }

    private var displayName: String {
        if let appURL {
            return FileManager.default.displayName(atPath: appURL.path)
        }
        return bundleId
    }

    private var icon: NSImage? {
        guard let appURL else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 20))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
            }
            Text(displayName)
                .font(.system(size: 14))
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.white.opacity(0.11) : Color.clear)
        )
    }
}

// MARK: - Keyboard

@MainActor
private final class HotkeyRecorder: ObservableObject {
    @Published var isRecording = false
    private var monitor: Any?
    private var onCapture: ((Hotkey) -> Void)?

    func start(onCapture: @escaping (Hotkey) -> Void) {
        stop()
        self.onCapture = onCapture
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc 取消录制
                self.stop()
                return nil
            }
            let hotkey = Hotkey.from(event: event)
            guard !hotkey.modifiers.isEmpty else { return nil }
            self.stop()
            self.onCapture?(hotkey)
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        onCapture = nil
    }
}

private struct KeyboardSettingsPage: View {
    @State private var openHotkey = AppPreferences.openHotkey
    @StateObject private var recorder = HotkeyRecorder()

    var body: some View {
        SettingsPage(title: String(localized: "settings.keyboard", defaultValue: "键盘快捷键")) {
            SettingsGroup {
                HStack {
                    Text(String(localized: "settings.keyboard.open", defaultValue: "启动 ClipKit"))
                        .font(.system(size: 15))
                    Spacer()
                    Button {
                        if recorder.isRecording {
                            recorder.stop()
                        } else {
                            recorder.start { hotkey in
                                openHotkey = hotkey
                                AppPreferences.setOpenHotkey(hotkey)
                            }
                        }
                    } label: {
                        Text(recorder.isRecording
                             ? String(localized: "settings.keyboard.recording", defaultValue: "按下快捷键…")
                             : openHotkey.displayString)
                            .font(.system(size: 14, weight: .medium))
                            .frame(minWidth: 104)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.white.opacity(recorder.isRecording ? 0.16 : 0.10))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
            }

            SettingsGroup {
                SettingValueRow(
                    title: String(localized: "settings.keyboard.quickPaste", defaultValue: "快速粘贴"),
                    value: "⌘ Command + 1…9"
                )
                SettingsDivider()
                SettingValueRow(
                    title: String(localized: "settings.keyboard.plainText", defaultValue: "纯文本模式"),
                    value: "⇧ Shift"
                )
            }

            HStack {
                Text(String(localized: "settings.keyboard.hint", defaultValue: "快捷键全局生效。若无法使用，请在「系统设置 → 隐私与安全性 → 辅助功能」中允许 ClipKit。"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Button(String(localized: "settings.keyboard.reset", defaultValue: "将快捷键重置为默认…")) {
                    recorder.stop()
                    AppPreferences.resetOpenHotkey()
                    openHotkey = AppPreferences.openHotkey
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 2)
        }
        .onDisappear {
            recorder.stop()
        }
    }
}

// MARK: - About

private struct AboutSettingsPage: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        SettingsPage(title: String(localized: "settings.about", defaultValue: "关于")) {
            VStack(spacing: 12) {
                Image(systemName: "clipboard.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 10)

                Text("ClipKit")
                    .font(.system(size: 26, weight: .bold))

                Text(String(localized: "about.subtitle", defaultValue: "开源剪贴板管理器"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                Text("v\(version)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)

            SettingsGroup {
                SettingValueRow(title: String(localized: "settings.about.version", defaultValue: "版本"), value: version)
                SettingsDivider()
                SettingValueRow(title: String(localized: "settings.about.license", defaultValue: "许可证"), value: "MIT License")
                SettingsDivider()
                SettingValueRow(title: String(localized: "settings.about.storage", defaultValue: "数据存储"), value: String(localized: "settings.about.storage.local", defaultValue: "仅保存在本机"))
            }

            HStack {
                Link(
                    String(localized: "about.github", defaultValue: "GitHub 仓库"),
                    destination: URL(string: "https://github.com/yourname/clipkit")!
                )
                Spacer()
                Button(String(localized: "settings.about.help", defaultValue: "帮助中心")) {
                    if let url = URL(string: "https://github.com/yourname/clipkit") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Helpers

private func notifyPreferencesChanged() {
    NotificationCenter.default.post(name: .clipKitPreferencesChanged, object: nil)
}

#endif
