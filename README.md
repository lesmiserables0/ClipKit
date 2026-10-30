# ClipKit

> 开源 macOS 剪贴板管理器 — 快速、隐私优先、键盘驱动

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://www.apple.com/macos)

## 特性

- **快速** — 基于原生 NSPasteboard 监听，延迟 < 0.3s
- **全格式** — 文本、图片、文件、链接、代码、邮箱、电话号码、颜色
- **搜索** — 关键词搜索 + 拼音搜索 + 类型/应用过滤
- **隐私优先** — 所有数据本地存储，零网络请求
- **键盘驱动** — 全键盘操作，不离开主键盘区
- **智能识别** — 自动识别内容类型，彩色图标标记
- **固定/收藏** — Pin 常用内容到顶部
- **开源** — MIT 协议，完全免费

## 安装

### Homebrew (计划中)
```bash
brew install clipkit
```

### 手动构建
```bash
git clone https://github.com/yourname/clipkit.git
cd clipkit
open ClipKit.xcodeproj
# 在 Xcode 中 Build & Run (⌘R)
```

## 使用

| 操作 | 快捷键 |
|------|--------|
| 打开 ClipKit | `⇧ + ⌘ + C` 或点击菜单栏图标 |
| 搜索 | 直接输入文字 |
| 复制选中项 | 双击 或 `Enter` |
| 删除 | `⌫` 或右键 → 删除 |
| 固定/取消固定 | 右键 → 固定到顶部 |

## 项目结构

```
ClipKit/
├── ClipKitCore/               # 核心逻辑 (可跨平台复用)
│   ├── Models/
│   │   ├── Clip.swift          # 剪贴板记录模型
│   │   └── ClipType.swift      # 内容类型 + 自动推断
│   ├── Storage/
│   │   └── ClipStore.swift     # 持久化存储 (Actor)
│   ├── Monitor/
│   │   └── ClipboardMonitor.swift  # NSPasteboard 监听
│   └── Search/
│       └── SearchEngine.swift  # 搜索 + 拼音支持
│
├── ClipKitMac/                # macOS App
│   ├── ClipKitApp.swift        # @main 入口 + MenuBarExtra
│   ├── ClipboardViewModel.swift # MVVM ViewModel
│   ├── Views/
│   │   ├── ContentView.swift   # 主界面
│   │   └── SettingsView.swift  # 设置页
│   └── Components/
│       └── ClipRow.swift       # 单行视图
│
└── ClipKitTests/              # 单元测试
    └── ClipKitTests.swift
```

## 技术栈

| 组件 | 技术 |
|------|------|
| 语言 | Swift 6 |
| UI | SwiftUI + MenuBarExtra |
| 存储 | JSON 文件 (后续迁移到 SwiftData) |
| 同步 | CloudKit (计划中) |
| 架构 | MVVM + Actor |
| 最低系统 | macOS 14 (Sonoma) |

## Roadmap

- [x] 剪贴板历史记录 + 搜索
- [x] 内容类型自动识别
- [x] 拼音搜索
- [x] 固定/收藏
- [x] 图片缩略图预览
- [ ] 键盘快捷键完整支持 (⌘+数字选择)
- [ ] iCloud 同步 (CloudKit)
- [ ] iOS App + 键盘扩展
- [ ] AI 内容增强 (翻译/总结/代码分析)
- [ ] 顺序粘贴队列
- [ ] StoreKit 2 订阅

## 竞品对比

| | ClipKit | Maccy | Paste | PastePal | 灵剪 |
|---|---|---|---|---|---|
| 开源 | ✅ | ✅ | ❌ | ❌ | ❌ |
| 定价 | 免费 | 免费 | $9.99/年 | $14.99买断 | ¥28买断 |
| iCloud同步 | 计划中 | ❌ | ✅ | ✅ | ❌ |
| AI能力 | 计划中 | ❌ | ❌ | ❌ | ✅ |
| 拼音搜索 | ✅ | ❌ | ❌ | ❌ | ❌ |

## License

MIT © 2026 ClipKit
