#if canImport(AppKit)
import AppKit
import SwiftUI

/// macOS 应用入口
///
/// 架构：
/// - 菜单栏图标（NSStatusItem）常驻
/// - 全局快捷键 ⇧⌘V 呼出底部悬浮面板
/// - 底部面板：水平卡片条 + 搜索框
/// - 面板失去焦点自动隐藏
// MARK: - 面板停留位置

/// 剪贴板面板可停留的位置
enum PanelPosition: String, CaseIterable, Identifiable {
    case bottom, top, left, right

    var id: String { rawValue }

    /// 用户可见名称
    var displayName: String {
        switch self {
        case .bottom: String(localized: "position.bottom", defaultValue: "下侧")
        case .top:    String(localized: "position.top", defaultValue: "上侧")
        case .left:   String(localized: "position.left", defaultValue: "左侧")
        case .right:  String(localized: "position.right", defaultValue: "右侧")
        }
    }

    /// 选择器图标
    var icon: String {
        switch self {
        case .bottom: "arrow.down.to.line"
        case .top:    "arrow.up.to.line"
        case .left:   "arrow.left.to.line"
        case .right:  "arrow.right.to.line"
        }
    }

    /// 是否为竖向停靠（左右）
    var isVertical: Bool { self == .left || self == .right }
}

// MARK: - App

@main
struct ClipKitApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
        }
    }
}

// MARK: - AppDelegate: 菜单栏 + 全局快捷键 + 底部面板

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {

    @MainActor lazy var viewModel = ClipboardViewModel()
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu?
    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupStatusMenu()
        setupGlobalHotkey()
        setupNotificationObservers()
        setupFlashObserver()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(togglePanelFromNotification),
            name: .clipKitTogglePanel,
            object: nil
        )
    }

    /// 监听新剪贴板内容，触发菜单栏图标闪烁
    private func setupFlashObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewClipNotification),
            name: .clipKitNewClip,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRepositionNotification),
            name: .clipKitRepositionPanel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreferencesChanged),
            name: .clipKitPreferencesChanged,
            object: nil
        )
    }

    @MainActor @objc private func handleNewClipNotification() {
        flashStatusBarIcon()
        if AppPreferences.soundEnabled {
            NSSound(named: "Pop")?.play()
        }
    }

    @MainActor @objc private func handleRepositionNotification() {
        if let panel = panel {
            positionPanel(panel)
        }
    }

    @MainActor @objc private func handlePreferencesChanged() {
        guard let panel else { return }
        panel.sharingType = AppPreferences.showDuringScreenSharing ? .readOnly : .none
        positionPanel(panel)
    }

    @MainActor @objc func togglePanelFromNotification() {
        togglePanel()
    }

    // MARK: - Status Bar
    @MainActor
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "clipboard",
                accessibilityDescription: "ClipKit"
            )
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @MainActor @objc private func handleStatusItemClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    // MARK: - Status Bar Menu（关于 / 设置 / 停留位置 / 退出）

    @MainActor
    private func setupStatusMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let openItem = NSMenuItem(
            title: String(localized: "menu.open", defaultValue: "打开 ClipKit"),
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: String(localized: "menu.about", defaultValue: "关于 ClipKit"),
            action: #selector(showAboutPanel),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let settingsItem = NSMenuItem(
            title: String(localized: "menu.settings", defaultValue: "设置…"),
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let positionItem = NSMenuItem(
            title: String(localized: "menu.position", defaultValue: "停留位置"),
            action: nil,
            keyEquivalent: ""
        )
        let positionMenu = NSMenu()
        for position in PanelPosition.allCases {
            let item = NSMenuItem(
                title: position.displayName,
                action: #selector(selectPanelPosition(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = position.rawValue
            positionMenu.addItem(item)
        }
        positionItem.submenu = positionMenu
        menu.addItem(positionItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "menu.quit", defaultValue: "退出 ClipKit"),
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusMenu = menu
    }

    @MainActor
    private func showStatusMenu() {
        guard let menu = statusMenu, let button = statusItem.button else { return }
        refreshStatusMenuStates()
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    @MainActor
    private func refreshStatusMenuStates() {
        let current = UserDefaults.standard.string(forKey: AppDelegate.panelPositionKey)
            ?? PanelPosition.bottom.rawValue
        guard let positionItem = statusMenu?.items.first(where: {
            $0.title == String(localized: "menu.position", defaultValue: "停留位置")
        }), let submenu = positionItem.submenu else { return }

        for item in submenu.items {
            item.state = (item.representedObject as? String) == current ? .on : .off
        }
    }

    @MainActor @objc private func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @MainActor @objc private func openSettingsWindow() {
        hidePanel()
        NSApp.activate(ignoringOtherApps: true)
        // SwiftUI 的 Settings scene 在 macOS 14 上响应 showSettingsWindow:。
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @MainActor @objc private func selectPanelPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              PanelPosition(rawValue: raw) != nil else { return }
        UserDefaults.standard.set(raw, forKey: AppDelegate.panelPositionKey)
        NotificationCenter.default.post(name: .clipKitRepositionPanel, object: nil)
    }

    @MainActor @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    // MARK: - Global Hotkey (⇧⌘V)

    private func setupGlobalHotkey() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let hotkey = AppPreferences.openHotkey
            let flags = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .intersection([.command, .shift, .option, .control])
            if event.keyCode == hotkey.keyCode && flags.rawValue == hotkey.modifiersRawValue {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .clipKitTogglePanel, object: nil)
                }
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let hotkey = AppPreferences.openHotkey
            let flags = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .intersection([.command, .shift, .option, .control])
            if event.keyCode == hotkey.keyCode && flags.rawValue == hotkey.modifiersRawValue {
                NotificationCenter.default.post(name: .clipKitTogglePanel, object: nil)
                return nil
            }

            // 面板显示时支持 ⌘1…⌘9 快速粘贴对应卡片。
            // 通过通知交给 BottomBarView 判断是否有对应索引，避免在监听到
            // 键盘事件时跨隔离域访问 AppKit 窗口状态。
            if event.modifierFlags.contains(.command),
               let character = event.charactersIgnoringModifiers,
               let number = Int(character),
               (1...9).contains(number) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .clipKitQuickPaste,
                        object: nil,
                        userInfo: ["index": number - 1]
                    )
                }
                return nil
            }
            return event
        }
    }

    // MARK: - Panel Toggle

    @MainActor @objc func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    @MainActor private func showPanel() {
        viewModel.refresh()

        if panel == nil {
            createPanel()
        }

        guard let panel = panel else { return }

        positionPanel(panel)

        panel.orderFrontRegardless()
        // 让面板立即成为 key window，搜索框随之获得焦点
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 面板只创建一次，onAppear 不会重复触发；每次显示都通知 UI 重新聚焦搜索框
        NotificationCenter.default.post(name: .clipKitPanelDidShow, object: nil)
    }

    /// 根据偏好位置与当前屏幕，定位面板
    /// - 上/下：宽度达到屏幕宽度（水平卡片条）
    /// - 左/右：高度达到屏幕高度（竖向卡片条）
    @MainActor private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        // 面板铺满屏幕可见区域：上/下停靠使用全宽，左/右停靠使用全高。
        let screenFrame = screen.visibleFrame

        let position = PanelPosition(
            rawValue: UserDefaults.standard.string(forKey: Self.panelPositionKey) ?? ""
        ) ?? .bottom

        let width: CGFloat
        let height: CGFloat
        let x: CGFloat
        let y: CGFloat

        switch position {
        case .bottom:
            width = screenFrame.width
            height = 200
            x = screenFrame.minX
            y = screenFrame.minY
        case .top:
            width = screenFrame.width
            height = 200
            x = screenFrame.minX
            y = screenFrame.maxY - height
        case .left:
            width = 360
            height = screenFrame.height
            x = screenFrame.minX
            y = screenFrame.minY
        case .right:
            width = 360
            height = screenFrame.height
            x = screenFrame.maxX - width
            y = screenFrame.minY
        }

        panel.setFrame(
            NSRect(x: x, y: y, width: width, height: height),
            display: true,
            animate: true
        )
    }

    @MainActor private func hidePanel() {
        panel?.orderOut(nil)
    }

    // MARK: - Create Panel

    @MainActor private func createPanel() {
        let panel = ClipKitPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 点击面板任意位置即可成为 key window，TextField 才能聚焦输入
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.sharingType = AppPreferences.showDuringScreenSharing ? .readOnly : .none
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.delegate = self

        let contentView = BottomBarView(viewModel: viewModel) { [weak self] in
            self?.hidePanel()
        }
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // 用容器 NSView 包住 hostingView，并把 hostingView 四边钉到面板内容区。
        // 否则 NSHostingView 的 intrinsicContentSize 会让窗口去"贴合"内容尺寸，
        // 导致点击分类等触发重新布局时面板被内容反向撑宽。
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = container
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        self.panel = panel
    }

    // MARK: - Window Delegate

    func windowDidResignKey(_ notification: Notification) {
        // 只处理面板自身失焦
        guard (notification.object as? NSWindow) === panel, panel?.isVisible == true else { return }

        // 失焦目标是状态栏图标（点击图标切换面板）时不隐藏，
        // 交给 togglePanel 的开关逻辑处理，避免"先隐藏再弹出"的竞态
        if let statusWindow = statusItem?.button?.window, NSApp.keyWindow === statusWindow {
            return
        }

        hidePanel()
    }

    // MARK: - Status Bar Icon Flash

    /// 检测到复制动作后，让菜单栏图标闪一下
    @MainActor     private func flashStatusBarIcon() {
        guard let button = statusItem.button else { return }
        let normal = NSImage(
            systemSymbolName: "clipboard",
            accessibilityDescription: "ClipKit"
        )
        let filled = NSImage(
            systemSymbolName: "clipboard.fill",
            accessibilityDescription: "ClipKit"
        )

        // 短暂切换为填充图标 + 蓝色高亮，再复原，形成一次闪烁
        button.contentTintColor = .systemBlue
        button.image = filled

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let button = self?.statusItem.button else { return }
            button.image = normal
            button.contentTintColor = nil
        }
    }
}

// MARK: - 面板：允许点击时成为 key，从而让 TextField 能聚焦输入

private final class ClipKitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension Notification.Name {
    static let clipKitTogglePanel = Notification.Name("clipKitTogglePanel")
    static let clipKitRepositionPanel = Notification.Name("clipKitRepositionPanel")
    static let clipKitPanelDidShow = Notification.Name("clipKitPanelDidShow")
    static let clipKitOpenSettings = Notification.Name("clipKitOpenSettings")
    static let clipKitQuickPaste = Notification.Name("clipKitQuickPaste")
}

extension AppDelegate {
    /// 面板位置偏好的 UserDefaults 键
    static let panelPositionKey = "clipkit.panelPosition"
}
#endif
