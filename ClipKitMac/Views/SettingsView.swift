#if canImport(AppKit)
import SwiftUI

/// 设置页面
struct SettingsView: View {

    @ObservedObject var viewModel: ClipboardViewModel
    @AppStorage("clipkit.maxItems") private var maxItems = 500
    @AppStorage("clipkit.launchAtLogin") private var launchAtLogin = false
    @AppStorage("clipkit.ignorePasswords") private var ignorePasswords = true
    @AppStorage("clipkit.pollInterval") private var pollInterval = 0.3
    @AppStorage("clipkit.aiEnabled") private var aiEnabled = true

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label {
                        Text(String(localized: "settings.general", defaultValue: "通用"))
                    } icon: {
                        Image(systemName: "gear")
                    }
                }

            aboutTab
                .tabItem {
                    Label {
                        Text(String(localized: "settings.about", defaultValue: "关于"))
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                }
        }
        .frame(width: 400, height: 300)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section(String(localized: "settings.section.launch", defaultValue: "启动")) {
                Toggle(String(localized: "settings.launchAtLogin", defaultValue: "开机自动启动"), isOn: $launchAtLogin)
            }

            Section(String(localized: "settings.section.history", defaultValue: "历史记录")) {
                Stepper(String(format: String(localized: "settings.maxItems", defaultValue: "最多保留 %d 条"), maxItems), value: $maxItems, in: 100...5000, step: 100)

                Toggle(String(localized: "settings.ignorePasswords", defaultValue: "自动忽略密码内容"), isOn: $ignorePasswords)
                    .help(String(localized: "settings.ignorePasswords.help", defaultValue: "密码管理器复制的临时内容不会被记录"))
            }

            Section(String(localized: "settings.section.monitor", defaultValue: "监听")) {
                Slider(value: $pollInterval, in: 0.1...2.0, step: 0.1) {
                    Text(String(localized: "settings.checkInterval", defaultValue: "检查间隔"))
                } minimumValueLabel: {
                    Text(String(localized: "settings.interval.min", defaultValue: "0.1s"))
                        .font(.caption2)
                } maximumValueLabel: {
                    Text(String(localized: "settings.interval.max", defaultValue: "2.0s"))
                        .font(.caption2)
                }
            }

            Section(String(localized: "settings.aiEnabled", defaultValue: "启用 AI 增强")) {
                Toggle(String(localized: "settings.aiEnabled", defaultValue: "启用 AI 增强"), isOn: $aiEnabled)
                Text(String(localized: "settings.aiUnavailable", defaultValue: "当前系统不支持 Apple 智能，AI 功能将自动降级为仅 JSON 美化。"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Section(String(localized: "settings.section.data", defaultValue: "数据")) {
                Button(String(localized: "settings.clearAll", defaultValue: "清除所有记录")) {
                    viewModel.clearAll(keepPinned: false)
                }
                .foregroundColor(.red)
            }
        }
        .padding()
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "clipboard")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("ClipKit")
                .font(.title2.bold())

            Text(String(localized: "about.subtitle", defaultValue: "开源剪贴板管理器"))
                .font(.caption)
                .foregroundColor(.secondary)

            Text("MIT License")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            Link(String(localized: "about.github", defaultValue: "GitHub 仓库"), destination: URL(string: "https://github.com/yourname/clipkit")!)
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#endif
