# HistoryLib for Windows

> HistoryLib is a vibe coding project; AI has done most of the work. If that
> concerns you, please do not use it. Please open an Issue first rather than
> submitting a pull request directly.

This directory contains the Windows client built with C#, WinUI 3, and the
Windows App SDK. It is under development and is not included in the Apple-only
v1.4 release.

The client includes local history import, browsing, search, export, settings,
and summary views. Shared formats and product behavior are defined in
[`shared/specs`](../../shared/specs/README.md); source availability does not
establish compatibility with every Apple feature or archive variant.

## Build and run

Open `HistoryLib.Windows.sln` in Visual Studio, select `x64`, and run the
Windows app project. From PowerShell:

```powershell
dotnet build .\HistoryLib.Windows.sln -p:Platform=x64
```

The app is configured for self-contained Windows App SDK deployment. Runtime,
packaging, archive interoperability, and native-authentication checks are
required before a Windows release.

## Source layout

- `HistoryLib.Windows/`: desktop interface, persistence, and platform services.
- `HistoryLib.Windows.sln`: Visual Studio solution.

The interface uses native Windows controls and localized RESW resources.
The six product languages are English, Simplified Chinese, Arabic, French,
Russian, and Spanish.

## Development

Follow the [privacy contract](../../shared/specs/privacy-and-data.md) for local
history, temporary files, website icons, and native authentication. Import and
export implementations must use the [shared format contracts](../../shared/specs/README.md).
Use synthetic history when testing or reporting a problem.
