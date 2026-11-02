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

    /// 面板停留位置（与 AppDelegate 共享 UserDefaults 键）
    @AppStorage("clipkit.panelPosition") private var positionRaw = PanelPosition.bottom.rawValue
    @State private var showPositionPicker = false

    // 分类（chip）：剪贴板 = 全部，其余为用户自定义分类
    @State private var categories: [ClipCategory] = []
    @State private var selectedCategoryID: UUID?
    @State private var showAddCategoryPopover = false
    @State private var showSearchField = false

    private var position: PanelPosition {
        PanelPosition(rawValue: positionRaw) ?? .bottom
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏（剪贴板 / 分类 / 搜索按钮 / 设置）
            topBar

            Divider()
                .background(Color.white.opacity(0.1))

            // 卡片条（横/竖随位置变化）
            if viewModel.clips.isEmpty {
                emptyState
            } else {
                cardStrip
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 0.95)))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        )
        .onAppear {
            loadCategoriesIfNeeded()
            searchFocused = true
            selectedIndex = 0
        }
        // 面板每次显示（包括从菜单栏图标呼出）都重置搜索状态
        .onReceive(NotificationCenter.default.publisher(for: .clipKitPanelDidShow)) { _ in
            showSearchField = false
            searchFocused = true
            selectedIndex = 0
        }
        .onKeyPress(.escape) {
            onClose()
        }
        .onChange(of: positionRaw) { _, _ in
            // 位置变化时通知 AppDelegate 重新定位面板
            NotificationCenter.default.post(name: .clipKitRepositionPanel, object: nil)
        }
    }

    // MARK: - Top Bar（顶部导航栏：剪贴板 / 分类 / 搜索按钮 / 设置）

    private var topBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            // 「剪贴板」= 全部记录
            chipView(
                title: "剪贴板",
                colorHex: nil,
                iconName: "clock",
                isSelected: selectedCategoryID == nil
            ) {
                selectCategory(nil)
            }

            // 搜索按钮 / 输入框（放在「剪贴板」旁边）
            if showSearchField {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    TextField("搜索...", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($searchFocused)
                        .frame(width: 150)
                        .onChange(of: viewModel.searchQuery) { _, _ in
                            viewModel.search()
                            selectedIndex = 0
                        }
                        .onSubmit {
                            selectCurrent()
                        }

                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.searchQuery = ""
                            viewModel.search()
                            withAnimation { showSearchField = false }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.08))
                )
            } else {
                Button {
                    withAnimation { showSearchField = true }
                    searchFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            // 用户自定义分类
            ForEach(categories) { category in
                chipView(
                    title: category.name,
                    colorHex: category.colorHex,
                    iconName: nil,
                    isSelected: selectedCategoryID == category.id
                ) {
                    selectCategory(category.id)
                }
                .contextMenu {
                    Button("删除分类", role: .destructive) {
                        deleteCategory(category)
                    }
                }
            }

            // 加号：新增分类
            Button {
                showAddCategoryPopover = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAddCategoryPopover) {
                AddCategoryView { name, type in
                    addCategory(name: name, type: type)
                }
            }

            Spacer(minLength: 0)

            // 右上角设置：调整面板停留位置
            Button {
                showPositionPicker.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPositionPicker) {
                positionPicker
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func chipView(
        title: String,
        colorHex: String?,
        iconName: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .primary : .secondary)
                } else if let colorHex {
                    Circle()
                        .fill(Color.fromHexString(colorHex))
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Persistence

    private static let categoriesDefaultsKey = "clipkit.categories"
    private static let selectedCategoryDefaultsKey = "clipkit.selectedCategoryId"
    private static let newCategoryPalette = [
        "#FFD60A", "#FF9F0A", "#30D158", "#64D2FF", "#FF375F", "#AC8E68"
    ]

    private func loadCategoriesIfNeeded() {
        guard categories.isEmpty else { return }

        if let data = UserDefaults.standard.data(forKey: Self.categoriesDefaultsKey),
           let saved = try? JSONDecoder().decode([ClipCategory].self, from: data) {
            categories = saved
        } else {
            // 首次启动的默认分类（对应截图中的「实用链接」）
            categories = [ClipCategory(name: "实用链接", colorHex: ClipType.link.categoryColorHex, type: .link)]
            saveCategories()
        }

        // 恢复上次选中的分类
        if let savedID = UserDefaults.standard
            .string(forKey: Self.selectedCategoryDefaultsKey)
            .flatMap(UUID.init(uuidString:)),
           categories.contains(where: { $0.id == savedID }) {
            selectedCategoryID = savedID
        }

        syncSelectedFilter()
    }

    private func saveCategories() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: Self.categoriesDefaultsKey)
        }
    }

    private func selectCategory(_ id: UUID?) {
        selectedCategoryID = id
        UserDefaults.standard.set(id?.uuidString, forKey: Self.selectedCategoryDefaultsKey)
        syncSelectedFilter()
        viewModel.refresh()
    }

    private func syncSelectedFilter() {
        viewModel.selectedFilter = categories
            .first { $0.id == selectedCategoryID }?
            .typeFilter
    }

    private func addCategory(name: String, type: ClipType?) {
        let colorHex = type?.categoryColorHex
            ?? Self.newCategoryPalette[categories.count % Self.newCategoryPalette.count]
        let category = ClipCategory(
            name: name.isEmpty ? "未命名" : name,
            colorHex: colorHex,
            type: type
        )
        categories.append(category)
        saveCategories()
        selectCategory(category.id)
    }

    private func deleteCategory(_ category: ClipCategory) {
        categories.removeAll { $0.id == category.id }
        saveCategories()
        if selectedCategoryID == category.id {
            selectCategory(nil)
        }
    }

    // MARK: - Position Picker (右上角设置)

    private var positionPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("面板停留位置")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(PanelPosition.allCases) { p in
                    Button {
                        positionRaw = p.rawValue
                        showPositionPicker = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: p.icon)
                                .font(.system(size: 18))
                            Text(p.displayName)
                                .font(.system(size: 11))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(
                            position == p
                            ? Color.accentColor.opacity(0.25)
                            : Color.gray.opacity(0.12)
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(width: 200)
    }

    // MARK: - Card Strip (横/竖滚动随位置)

    private var cardStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(position.isVertical ? .vertical : .horizontal, showsIndicators: false) {
                if position.isVertical {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                            StripCard(
                                clip: clip,
                                isSelected: index == selectedIndex,
                                isVertical: true,
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
                } else {
                    HStack(spacing: 10) {
                        ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                            StripCard(
                                clip: clip,
                                isSelected: index == selectedIndex,
                                isVertical: false,
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

// MARK: - 用户自定义分类

/// 分类（chip）：按内容类型过滤记录，持久化在 UserDefaults
struct ClipCategory: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String
    var typeRaw: String?

    var typeFilter: ClipType? {
        typeRaw.flatMap { ClipType(rawValue: $0) }
    }

    init(name: String, colorHex: String, type: ClipType?) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.typeRaw = type?.rawValue
    }
}

extension ClipType {
    /// 分类 chip 的默认颜色（与卡片类型色一致）
    var categoryColorHex: String {
        switch self {
        case .text, .richText: return "#0A84FF"  // 蓝
        case .link:            return "#FF453A"  // 红
        case .image:           return "#BF5AF2"  // 紫
        case .file:            return "#8E8E93"  // 灰
        default:               return "#FFD60A"  // 黄
        }
    }
}

// MARK: - 新增分类弹窗

private struct AddCategoryView: View {
    var onAdd: (String, ClipType?) -> Void

    @State private var name = "未命名"
    @State private var selectedType: ClipType?
    @Environment(\.dismiss) private var dismiss

    private let typeOptions: [ClipType?] = [nil, .text, .link, .image, .file]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建分类")
                .font(.headline)

            TextField("分类名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))

            Picker("类型过滤", selection: $selectedType) {
                ForEach(typeOptions, id: \.self) { type in
                    Text(type?.displayName ?? "全部内容")
                        .tag(type as ClipType?)
                }
            }
            .pickerStyle(.menu)

            Text("分类按内容类型过滤记录；选「全部内容」则不过滤。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("添加") {
                    onAdd(name, selectedType)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 240)
    }
}

#endif
