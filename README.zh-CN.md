# HistoryLib

[English](README.md) | 简体中文

HistoryLib 是一个 SwiftUI app，用于收集、浏览、搜索、去重并重新导出浏览器历史记录。目前它主要面向 Safari 历史记录导出文件和 HistoryLib 自己的 `.hlz` 归档格式。

导入的记录使用 SwiftData 存储。app 可以通过 CloudKit 使用 iCloud 同步，也可以将大数据集导出为基于 ZIP 的 `.hlz` 归档，内部包含 JSONL 分块和校验索引。

## 状态

此项目仍处于早期阶段，并且偏向个人使用。app 已经足够用于导入、浏览、汇总、导出和去重历史记录数据，但公开 API、归档格式细节和 UI 仍可能变化。

浏览器历史记录是敏感的个人数据。除非你已经检查过其中内容，否则不要发布导出的 `.hlz`、`.zip` 或 `.json` 历史记录文件。

## 功能

- 导入 Safari 历史记录 JSON 文件、文件夹和 ZIP 归档。
- 导入 HistoryLib `.hlz` 归档。
- 按年、月、日浏览记录。
- 按 URL 或标题搜索。
- 在系统浏览器中打开记录。
- 显示已缓存的网站 favicon。
- 生成汇总快照。
- 导出 Safari 兼容的 ZIP 归档。
- 导出优化后的 HistoryLib `.hlz` 归档。
- 对导入或同步的记录去重。
- 启用 iCloud 时同步记录和 app 设置。

## 平台

- iOS
- macOS

项目当前的部署目标是 iOS 26.x 和 macOS 26.x。

## 要求

- 支持已配置部署目标的 Xcode，以及 Swift、SwiftUI、SwiftData 和 CloudKit 支持。
- 如果你希望 CloudKit 同步能在设备上工作，需要 Apple Developer team 和有效的 iCloud entitlements。
- 解析包依赖和获取 favicon 时需要网络访问。

项目使用 Swift Package Manager，目前依赖 [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 0.9.20。

## 构建

在 Xcode 中打开 `HistoryLib.xcodeproj`，然后运行 `HistoryLib` scheme。

通过命令行：

```sh
xcodebuild -list -project HistoryLib.xcodeproj
xcodebuild -project HistoryLib.xcodeproj -scheme HistoryLib build
```

对于模拟器或真机构建，请传入与你本地 Xcode 安装匹配的 destination，例如：

```sh
xcodebuild \
  -project HistoryLib.xcodeproj \
  -scheme HistoryLib \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

## 测试

从 Xcode 运行测试，或使用 `xcodebuild`：

```sh
xcodebuild \
  -project HistoryLib.xcodeproj \
  -scheme HistoryLib \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

## 文档

- [项目文档](Documentation.docc/Documentation.md)
- [归档格式](Documentation.docc/HistoryLib-Archive-Format.md)
- [隐私和数据](Documentation.docc/Privacy-and-Data.md)
- [项目结构](Documentation.docc/Project-Structure.md)
- [开发说明](Documentation.docc/Development.md)

## 许可证

HistoryLib 使用 MIT License 授权。请参阅 [LICENSE](LICENSE)。

第三方依赖声明列在 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
