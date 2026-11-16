# Apple 客户端

[English](Apple-Client.md) | 简体中文

HistoryLib 在 iPhone、iPad 和 Mac 上整理导入的浏览器历史记录。
应用使用 SwiftUI 构建界面、SwiftData 保存本机数据，并通过 CloudKit 提供 iCloud 同步。

## 导入与导出

支持从文件、文件夹或 ZIP 导入 Safari、Google Takeout Chrome 历史记录和 HistoryLib 归档，
自动识别格式并合并重复记录。

可导出为 Safari、Google Takeout 或 HistoryLib `.hlz` 格式，原生归档可选密码保护。
导出便于转移数据；能否导回某个浏览器，取决于该浏览器支持的导入格式。
原生格式说明见 [HistoryLib 归档格式](HistoryLib-Archive-Format.md)。

## 浏览与搜索

Library 按年、月、日整理记录，关键词搜索匹配标题和网址。
高级搜索默认关闭，开启后可以编辑关键词、域名、浏览器和日期条件。
AI 解析和 Siri AI 搜索目前未启用。

点击记录时可以打开浏览器、复制完整网址，或什么都不做；
长按和右键菜单也提供记录操作。删除操作需要先开启对应设置。

Summary 展示保存的记录条数、访问次数、活跃天数、时间跨度、月度活动和浏览器及网站排名。

## 存储与隐私

历史记录的浏览和管理可以离线进行。正常情况下，iCloud 同步由系统设置控制。
Manage 展示空间占用、观察到的同步活动，以及本机和云端的记录数量。同步不等于备份。

macOS 默认启用基于系统认证的隐私锁；iPhone 和 iPad 使用 Apple 的系统 App 锁定功能。
可选的网站图标功能会访问对应网站。
详情见 [隐私和数据](Privacy-and-Data.md) 及 [版本兼容](Version-Compatibility.md)。

## 支持与系统要求

应用完全开源、无广告、免费使用。小费只是自愿支持开发者，不会解锁任何功能。
Help 提供 GitHub Issues 和私密邮件反馈入口。

最低支持 iOS/iPadOS 26、macOS 26。
界面支持英文、简体中文、阿拉伯语、法语、俄语和西班牙语。

## 开发

构建和测试方式见 [开发说明](Development.md)，
代码组织见 [项目结构](Project-Structure.md)，
第三方依赖声明见 [此处](THIRD-PARTY-NOTICES.md)。
共享规范索引见 [此处](../../../shared/specs/README.md)，
更新记录见 [Changelog](../../../CHANGELOG.md)。
