# HistoryLib Apple 客户端

[English](README.md) | 简体中文

面向 iPhone、iPad 和 Mac 的原生 HistoryLib 应用，使用 SwiftUI、SwiftData 和 CloudKit 构建。

> HistoryLib 是一个 vibe coding 项目，绝大部分工作均由 AI 完成，介意者请勿使用。
> 如果发现问题或有建议，请优先提 Issue，而不是直接提交 PR。

支持导入 Safari、Google Takeout 和 HistoryLib 归档，浏览和搜索历史记录、查看活动统计、
通过 iCloud 同步，以及导出数据。原生归档可选密码保护。v1.4 还提供高级搜索、
记录操作、存储诊断和自愿支持开发者的小费功能。

最低支持 iOS/iPadOS 26 和 macOS 26。

## 源码与文档

- `HistoryLib/`：应用代码、资源和本地化文案。
- `HistoryLibTests/`：数据处理和行为自动测试。
- `HistoryLibUITests/`：界面回归测试。
- `HistoryLib.xcodeproj`：Xcode 工程。
- [`Documentation.docc`](Documentation.docc/Documentation.md)：Apple 文档。

使用说明见 [客户端概览](Documentation.docc/Apple-Client.zh-CN.md)，
从源码构建请阅读 [开发说明](Documentation.docc/Development.md)。
共享格式和产品规范位于 [`shared/specs`](../../shared/specs/README.md)。
