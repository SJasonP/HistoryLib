# HistoryLib

[English](README.md)

HistoryLib 是一个原生多平台应用，用于导入、浏览、搜索、去重、同步和重新导出浏览器历史记录。

1.4 仅发布 Apple 客户端（iOS 和 macOS）。Android 和 Windows 暂缓发布，代码保留在仓库中供后续开发。各客户端采用平台原生技术，通过共享规范和虚构测试数据保持行为与格式一致。

所有客户端统一支持联合国六种官方语言：美式英语、简体中文、阿拉伯语、法语、俄语和西班牙语。阿拉伯语使用平台原生从右到左布局，涉及数量的文案遵循各平台的复数规则。

## 仓库结构

- `platforms/apple`：Swift、SwiftUI、SwiftData 与 CloudKit 客户端。
- `platforms/android`：Kotlin 与 Jetpack Compose 客户端，最低 API 36。
- `platforms/windows`：C# 与 WinUI 3 客户端源码，不包含在本次发布中。
- `shared/specs`：跨平台行为与格式契约。
- `shared/fixtures`：虚构的互操作和拒绝测试数据。

整个产品只有一份 Git 历史和一个产品版本。各应用商店的内部构建号可以不同。实际发布的客户端使用产品版本号；暂缓发布的客户端不宣称已经发布或完成兼容性验收。

公共规范索引见 [`shared/specs/README.md`](shared/specs/README.md)。

## 当前状态

- Apple 1.4 的安全审计及必要修复已完成；分发准备和真人验收仍属于发布门槛。
- Android 和 Windows 属于开发中的客户端，暂缓发布。
- 1.4 的变更和发布范围见 [CHANGELOG.md](CHANGELOG.md)。

各平台的构建方式见对应目录内的 README。

Android 1.4 的详细产品与技术实施基线见
[`platforms/android/docs/Android-1.4-Specification.zh-CN.md`](platforms/android/docs/Android-1.4-Specification.zh-CN.md)。

## 隐私

浏览器历史记录是敏感个人数据。不得向仓库提交真实浏览记录。HistoryLib 不提供产品级备份功能；导出属于用户主动发起的数据转移。

## 许可证

HistoryLib 使用 MIT License，详见 `LICENSE`。
