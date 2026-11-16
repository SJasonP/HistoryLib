# HistoryLib

[English](README.md) | 简体中文

HistoryLib 给浏览器历史记录一个独立的去处。将 Safari、Google Takeout 或 HistoryLib
归档导入后，就能随时翻看、搜索和整理，不必再把所有记录导回浏览器。

Apple 版完全开源、无广告、免费使用。你也可以自愿给开发者一点小费；是否支持，都不影响任何功能。

> 这是一个 vibe coding 项目，绝大部分工作均由 AI 完成，介意者请勿使用。
> 如果发现问题或有建议，请优先提 Issue，而不是直接提交 PR。

## 主要功能

- **导入历史记录**：自动识别支持的文件、文件夹和 ZIP 归档，合并重复记录。
- **找回看过的页面**：按年、月、日浏览，搜索标题和网址；开启高级搜索后，还能组合关键词、域名、浏览器和日期条件。
- **看看自己的浏览足迹**：查看月度活动、浏览器分布、常访问的网站和时间跨度，并区分保存的记录条数与访问次数。
- **在 Apple 设备间同步**：系统设置允许时，通过 iCloud 同步历史记录和设置。
- **自由导出**：支持 Safari、Google Takeout 和 HistoryLib `.hlz` 格式；原生归档可选密码保护。
- **选择点击行为**：点击记录时打开网页、复制完整网址，或者什么都不做；长按或右键也能打开操作菜单。

历史记录的浏览和管理可以离线进行。同步、网站图标和 App 内购买需要相应的网络服务。

## 支持平台

v1.4 面向 iPhone、iPad 和 Mac，最低支持 iOS/iPadOS 26、macOS 26。
Android 和 Windows 客户端仍在开发中，不包含在本次发布内。

Apple 界面支持英文、简体中文、阿拉伯语、法语、俄语和西班牙语。

## 开始使用

在 **Manage** 导入浏览器导出的历史记录，到 **Library** 浏览和搜索，
再到 **Summary** 查看统计。HistoryLib 归档可以在兼容的安装之间转移记录。

已发布版本见 [Releases](https://github.com/SJasonP/HistoryLib/releases)，
更新内容见 [Changelog](CHANGELOG.md)。

如果希望从源码构建，请先阅读 [Apple 开发说明](platforms/apple/Documentation.docc/Development.md)；
Android 和 Windows 的构建方式见各自平台目录。

## 仓库结构

| 目录 | 内容 |
| --- | --- |
| [`platforms/apple`](platforms/apple) | SwiftUI 应用、SwiftData 存储、CloudKit 集成和 Apple 文档 |
| [`platforms/android`](platforms/android) | Kotlin 与 Jetpack Compose Android 客户端 |
| [`platforms/windows`](platforms/windows) | C# 与 WinUI 3 Windows 客户端 |
| [`shared/specs`](shared/specs/README.md) | 产品行为、归档格式和兼容性规范 |
| [`shared/fixtures`](shared/fixtures/README.md) | 导入、导出和兼容性测试使用的虚构数据 |

各客户端采用原生平台技术，通过共享规范和测试数据约定格式与行为。

## 隐私与反馈

历史记录保存在本机，也可能通过你的 iCloud 账户同步。可选的网站图标功能会访问对应网站。
导出的文件包含浏览历史，请妥善保管。
详细说明见 [隐私和数据](platforms/apple/Documentation.docc/Privacy-and-Data.md)。

问题和建议欢迎提交到 [GitHub Issues](https://github.com/SJasonP/HistoryLib/issues)。
如果需要私密反馈，也可以发送邮件至 [SJasonP@iCloud.com](mailto:SJasonP@iCloud.com)。
反馈时请使用虚构数据，或先隐去个人信息。

## 许可证

本项目采用 [MIT 许可证](LICENSE) 分发，不提供任何担保。
Apple 客户端的第三方依赖声明见 [此处](platforms/apple/Documentation.docc/THIRD-PARTY-NOTICES.md)。
