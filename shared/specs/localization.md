# Localization Contract

HistoryLib ships all six United Nations official languages as equal, complete
product languages:

- American English: `en-US`, the source/development copy.
- Simplified Chinese: `zh-Hans`.
- Arabic: `ar`.
- French: `fr`.
- Russian: `ru`.
- Spanish: `es`.

Every user-visible string, including dynamic progress, errors, destructive
confirmations, settings descriptions, empty states, and accessibility labels,
must be available in every product language. Shipping a string in only a
subset of these languages is a release-blocking bug.

## Platform-native resources

Each client uses its native localization system:

- Apple: String Catalogs and localized Settings bundle resources.
- Android: `strings.xml` resource sets and locale-aware formatting.
- Windows: RESW resources and Windows localization APIs.

Shared keys or source copy may be maintained under `shared/localization`, but
generated or native platform resources remain inside each platform project.
`shared/localization/validate_localizations.py` enforces key and placeholder
parity across the checked-in resources.

## Rules

- Do not embed user-visible literals in business logic.
- Interpolated values use locale-aware placeholders and number/date formatting.
- Sentences must allow natural word order in both languages.
- Product terms, format names, and destructive-action wording retain equivalent
  meaning across platforms.
- Arabic interfaces support right-to-left layout; embedded file extensions,
  URLs, dates, and product names retain their natural direction.
- Dates display in the user's locale and time zone; persisted timestamps remain
  UTC Unix microseconds.
- A feature is incomplete until all six language resources and accessibility
  labels are present.
