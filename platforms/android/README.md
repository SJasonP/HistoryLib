# HistoryLib for Android

**Release status:** deferred. HistoryLib v1.4 ships for iOS and macOS only.
The implementation below is retained for future releases and is not a v1.4
shipping or acceptance claim.

The Android client is the native Kotlin and Jetpack Compose implementation of
HistoryLib. It targets Android API 36 and later, supports only the `arm64-v8a`
ABI, and remains under development for a future release.
Its product UI supports American English, Simplified Chinese, Arabic, French,
Russian, and Spanish. Arabic uses Android's native right-to-left layout.

## Build

Open this directory in Android Studio, or run:

```sh
./gradlew test lintDebug checkArchitecture assembleRelease
```

`local.properties`, IDE state, Gradle caches, and build output are local-only
and must not be committed.

The default Release output is intentionally unsigned. For a local device test,
pass a keystore without committing it:

```sh
./gradlew :app:assembleRelease \
  -Phistorylib.releaseStoreFile=/absolute/path/test.keystore \
  -Phistorylib.releaseStorePassword=... \
  -Phistorylib.releaseKeyAlias=... \
  -Phistorylib.releaseKeyPassword=...
```

Use a real production keystore only for a release build. A debug keystore is
acceptable for local installation but must never be used for distribution.

## Product behavior

Android-specific UI and system integrations live here. Import detection,
deduplication, archive compatibility, privacy, and feature completeness are
defined by the contracts under `../../shared/specs`.

Implemented behavior includes Room-backed summary and paged library views,
local-time directory grouping, strict Safari/Chrome/HistoryLib import,
deduplicating merge, Safari and HistoryLib export, optional encrypted `.hlz`
archives, explicit transfer cancellation, favicon caching, cache inspection,
and confirmed destructive deletion. Sync is explicitly unavailable in Android
1.4; the app does not show a non-functional sync switch.

The detailed Android 1.4 product and implementation baseline is documented in
[`docs/Android-1.4-Specification.zh-CN.md`](docs/Android-1.4-Specification.zh-CN.md).
It records settled decisions, required parity behavior, architecture, data,
privacy, and testing requirements.

Code ownership and dependency direction are defined in
[`ARCHITECTURE.md`](ARCHITECTURE.md). Room schemas under `app/schemas` are
versioned compatibility artifacts and must be updated whenever the database
schema changes.
