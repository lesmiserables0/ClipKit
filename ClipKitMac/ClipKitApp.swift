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
        case .bottom: "下侧"
        case .top:    "上侧"
        case .left:   "左侧"
        case .right:  "右侧"
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    @MainActor lazy var viewModel = ClipboardViewModel()
    private var statusItem: NSStatusItem!
    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
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
    }

    @MainActor @objc private func handleNewClipNotification() {
        flashStatusBarIcon()
    }

    @MainActor @objc private func handleRepositionNotification() {
        if let panel = panel {
            positionPanel(panel)
        }
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
            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    // MARK: - Global Hotkey (⇧⌘V)

    private func setupGlobalHotkey() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 9 {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .clipKitTogglePanel, object: nil)
                }
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 9 {
                NotificationCenter.default.post(name: .clipKitTogglePanel, object: nil)
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
        let screenFrame = screen.visibleFrame
        let margin: CGFloat = 16

        let position = PanelPosition(
            rawValue: UserDefaults.standard.string(forKey: Self.panelPositionKey) ?? ""
        ) ?? .bottom

        let width: CGFloat
        let height: CGFloat
        let x: CGFloat
        let y: CGFloat

        switch position {
        case .bottom:
            width = screenFrame.width - margin * 2
            height = 200
            x = screenFrame.minX + margin
            y = screenFrame.minY + margin
        case .top:
            width = screenFrame.width - margin * 2
            height = 200
            x = screenFrame.minX + margin
            y = screenFrame.maxY - height - margin
        case .left:
            width = 360
            height = screenFrame.height - margin * 2
            x = screenFrame.minX + margin
            y = screenFrame.minY + margin
        case .right:
            width = 360
            height = screenFrame.height - margin * 2
            x = screenFrame.maxX - width - margin
            y = screenFrame.minY + margin
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
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.delegate = self

        let contentView = BottomBarView(viewModel: viewModel) { [weak self] in
            self?.hidePanel()
        }
        let hostingView = NSHostingView(rootView: contentView)
        panel.contentView = hostingView

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
    @MainActor private func flashStatusBarIcon() {
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            button.image = normal
            button.contentTintColor = nil
        }
    }
}

extension Notification.Name {
    static let clipKitTogglePanel = Notification.Name("clipKitTogglePanel")
    static let clipKitRepositionPanel = Notification.Name("clipKitRepositionPanel")
    static let clipKitPanelDidShow = Notification.Name("clipKitPanelDidShow")
}

extension AppDelegate {
    /// 面板位置偏好的 UserDefaults 键
    static let panelPositionKey = "clipkit.panelPosition"
}
#endif
