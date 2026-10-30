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
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(togglePanelFromNotification),
            name: .clipKitTogglePanel,
            object: nil
        )
    }

    @MainActor @objc func togglePanelFromNotification() {
        togglePanel()
    }

    // MARK: - Status Bar

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

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelWidth = min(CGFloat(900), screenFrame.width - 80)
            let panelHeight: CGFloat = 200
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.minY + 16
            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }

        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
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
        hidePanel()
    }
}

extension Notification.Name {
    static let clipKitTogglePanel = Notification.Name("clipKitTogglePanel")
}
#endif
