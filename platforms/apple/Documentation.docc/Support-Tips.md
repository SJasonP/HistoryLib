# Developer support tips

HistoryLib offers five voluntary consumable tips through StoreKit 2. The
flow is available from Manage below Help. It explains that the app is open
source, ad-free, and free to use. A tip does not unlock features or change
access.

The current United States base prices are $0.99, $2.99, $5.99, $9.99, and
$19.99. App Store Connect may localize these prices for other storefronts.
The UI uses StoreKit's localized product display price instead of hard-coding a
dollar amount.

The confirmation step appears before StoreKit and asks the user to confirm that
the tip is voluntary and understood. Apple processes the payment. Payment
questions should be directed to Apple because HistoryLib cannot process App
Store payments.

All five consumable products must exist in App Store Connect before release.
Product loading failures, cancellation, pending transactions, and verification
failures must leave the app usable and must not claim a successful tip.

The page retries missing products every five seconds while visible. App-wide
StoreKit transaction updates and unfinished transactions handle delayed or
interrupted payments without a developer server. Verified tip transactions are
finished once per session; new completions show thanks only while Support Us
is visible. Sandbox acceptance must also cover leaving the page during loading,
partial product responses, delayed approval, and relaunch after payment.
