# HistoryLib for Windows

**Release status:** deferred. HistoryLib v1.4 ships for iOS and macOS only.
The implementation below is retained for future releases and is not a v1.4
shipping or acceptance claim.

This directory contains the native Windows client for a future
HistoryLib release. The implementation uses C# with WinUI 3 and the
Windows App SDK. Product behavior follows `../../shared/specs`.

Windows uses an app-owned privacy lock enabled by default. Settings can disable
it. The implementation must use Windows Hello or another native local
authentication mechanism and must keep the library unavailable until launch
authentication succeeds.

## Build

Open `HistoryLib.Windows.sln` in Visual Studio, or run:

```powershell
dotnet build .\HistoryLib.Windows.sln -p:Platform=x64
```

The current client provides a usable local workflow: import detected Safari,
Chrome Takeout, and HistoryLib JSON files (or ZIP containers), deduplicate and
persist records in the per-user application data directory, browse/search/delete
records, open a URL in the default browser, view summary statistics, and export
Safari or HistoryLib JSON. Unknown files are ignored without changing stored
history. Page labels are read through the Windows RESW resource loader, using
the checked-in six-language resource sets.

Site icons are optional. They are fetched only when enabled, cached by host in
the per-user application data directory, and removed by the cache-clear action;
the setting is persisted independently from history records.

`Resources` contains the checked-in RESW baseline for American English,
Simplified Chinese, Arabic, French, Russian, and Spanish. Their key and
placeholder parity is covered by the shared localization validator.

The remaining release work is full runtime smoke testing on a packaged Windows
installation.

## 运行

构建后直接运行生成的桌面程序：

```powershell
$exe = Resolve-Path .\HistoryLib.Windows\bin\x64\Debug\net8.0-windows10.0.19041.0\HistoryLib.Windows.exe
Start-Process $exe
```

也可以在 Visual Studio 中打开 `HistoryLib.Windows.sln`，选择 `x64` 和 `Debug`，然后按 `F5`。

本次实际启动验证已确认窗口标题为 `HistoryLib`，程序保持运行；首次直接启动失败的问题来自 Windows App SDK 运行时注册方式，项目现已配置为自包含桌面模式。

## Interface

The Windows client follows the Apple client information architecture: Manage is
organized into Import, Export, Data, Settings, and Help sections instead of a
flat button list. Export format and password fields stay in the Export card;
Help explains HistoryLib Helper and supported browsers. The desktop shell uses a
fixed-pixel Grid layout with layout rounding and PerMonitorV2 DPI awareness.
