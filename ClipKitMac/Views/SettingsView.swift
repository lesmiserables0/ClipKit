#if canImport(AppKit)
import SwiftUI

/// 设置页面
struct SettingsView: View {

    @ObservedObject var viewModel: ClipboardViewModel
    @AppStorage("clipkit.maxItems") private var maxItems = 500
    @AppStorage("clipkit.launchAtLogin") private var launchAtLogin = false
    @AppStorage("clipkit.ignorePasswords") private var ignorePasswords = true
    @AppStorage("clipkit.pollInterval") private var pollInterval = 0.3

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            aboutTab
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 400, height: 300)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("启动") {
                Toggle("开机自动启动", isOn: $launchAtLogin)
            }

            Section("历史记录") {
                Stepper("最多保留 \(maxItems) 条", value: $maxItems, in: 100...5000, step: 100)

                Toggle("自动忽略密码内容", isOn: $ignorePasswords)
                    .help("密码管理器复制的临时内容不会被记录")
            }

            Section("监听") {
                Slider(value: $pollInterval, in: 0.1...2.0, step: 0.1) {
                    Text("检查间隔")
                } minimumValueLabel: {
                    Text("0.1s")
                        .font(.caption2)
                } maximumValueLabel: {
                    Text("2.0s")
                        .font(.caption2)
                }
            }

            Section("数据") {
                Button("清除所有记录") {
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

            Text("开源剪贴板管理器")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("MIT License")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            Link("GitHub 仓库", destination: URL(string: "https://github.com/yourname/clipkit")!)
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#endif
