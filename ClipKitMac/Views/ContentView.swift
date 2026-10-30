#if canImport(AppKit)
import SwiftUI

/// 底部悬浮面板主视图
///
/// 水平卡片条 + 搜索框：
/// - 顶部：搜索栏（输入即过滤）
/// - 中间：水平滚动的卡片列表
/// - 卡片：类型标签 + 时间 + 内容预览 + 字符数
/// - 选中卡片回车 → 复制并粘贴，自动关闭面板
struct BottomBarView: View {

    @ObservedObject var viewModel: ClipboardViewModel
    var onClose: () -> Void

    @State private var selectedIndex: Int = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            searchBar

            Divider()
                .background(Color.white.opacity(0.1))

            // 水平卡片条
            if viewModel.clips.isEmpty {
                emptyState
            } else {
                cardStrip
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 0.95)))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        )
        .onAppear {
            searchFocused = true
            selectedIndex = 0
        }
        .onKeyPress(.escape) {
            onClose()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 13))

            TextField("搜索...", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onChange(of: viewModel.searchQuery) { _, _ in
                    viewModel.search()
                    selectedIndex = 0
                }
                .onSubmit {
                    selectCurrent()
                }

            Text("\(viewModel.clips.count)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .cornerRadius(4)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Card Strip (水平滚动)

    private var cardStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                        StripCard(
                            clip: clip,
                            isSelected: index == selectedIndex,
                            onTap: {
                                selectedIndex = index
                                selectCurrent()
                            },
                            onDoubleClick: {
                                selectedIndex = index
                                selectCurrent()
                            }
                        )
                        .id(clip.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: selectedIndex) { _, newValue in
                if newValue < viewModel.clips.count {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(viewModel.clips[newValue].id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("还没有剪贴板记录")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(height: 120)
    }

    // MARK: - Actions

    private func selectCurrent() {
        guard selectedIndex < viewModel.clips.count else { return }
        let clip = viewModel.clips[selectedIndex]
        viewModel.copyAndPaste(clip)
        onClose()
    }
}

// MARK: - Key Press Support (macOS 14+)

extension View {
    func onKeyPress(_ key: KeyEquivalent, perform action: @escaping () -> Void) -> some View {
        self.background(KeyPressHandler(action: action))
    }
}

private struct KeyPressHandler: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyPressNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyPressNSView)?.action = action
    }
}

private final class KeyPressNSView: NSView {
    var action: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key code = 53
            action?()
            return
        }
        super.keyDown(with: event)
    }
}

#endif
