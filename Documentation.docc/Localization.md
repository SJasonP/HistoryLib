# Localization

HistoryLib ships full support for two languages and treats them as equals:

- **English (US)** — `en`, the development/base language.
- **Simplified Chinese** — `zh-Hans`.

"Full support" means every user-facing string the app can show is localized and
has a translation in both languages. Shipping an English-only string is a bug.

## Where Strings Live

- In-app strings live in the **String Catalog** at
  `HistoryLib/Localizable.xcstrings`. Its `sourceLanguage` is `en`.
- The project registers both languages in `knownRegions` (`en`, `zh-Hans`).
- The iOS **Settings bundle** (`HistoryLib/Settings.bundle`) is localized
  separately with per-language `*.lproj/Root.strings` files, because system
  Settings does not read the String Catalog.

## Rules

- Do not display a hard-coded English literal as a verbatim string. Every
  user-facing string must resolve through the String Catalog.
- For SwiftUI views that take a `LocalizedStringKey` (`Text`, `Label`,
  `Button`, alert titles, `.searchable` prompts), pass a string **literal** so
  it is auto-collected for translation. Do not pass a `String` variable to
  `Text`, which is treated as verbatim and is never localized.
- For strings built in code (status messages, alert bodies, export progress,
  blocked-action messages), use `String(localized:)` so the assembled value is
  already translated before it reaches the view. Interpolated values become
  format placeholders (for example, `String(localized: "Imported records: \(n)")`
  produces the catalog key `"Imported records: %lld"`).
- Keep interpolation order-independent across languages: when a sentence
  interpolates a noun/verb phrase, that phrase must itself be localized, and the
  surrounding sentence must read naturally in both English and Chinese.
- When you add or change a user-facing string, add its key to
  `Localizable.xcstrings` (or the relevant `Root.strings`) with both an `en` and
  a `zh-Hans` value before the change is considered done.
- New Settings-bundle entries get matching `Root.strings` lines in every
  `*.lproj` under `Settings.bundle`.

## Verifying

- Build once so Xcode can extract any newly added string literals into the
  catalog, then confirm no translatable key is missing a `zh-Hans` value and no
  key is left in the `new` state.
- Run the app in each language (Scheme ▸ Run ▸ Options ▸ App Language, or the
  system language) and spot-check imports, exports, search, deletion, and the
  iCloud/storage banners and alerts.
