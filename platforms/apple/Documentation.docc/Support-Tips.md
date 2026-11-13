# Developer support tips

HistoryLib may offer five voluntary consumable tips through StoreKit 2. The
flow is available from Manage below Help. It explains that the app is open
source, ad-free, and free to use. A tip does not unlock features or change
access.

The current proposed United States base prices are $0.99, $2.99, $5.99, $9.99,
and $19.99. App Store Connect may localize these prices for other storefronts.
The UI uses StoreKit's localized product display price instead of hard-coding a
dollar amount.

The confirmation step appears before StoreKit and asks the user to confirm that
the tip is voluntary and understood. Apple processes the payment and controls
refund decisions. HistoryLib cannot directly issue or guarantee a refund.

All five consumable products must exist in App Store Connect before release.
Product loading failures, cancellation, pending transactions, and verification
failures must leave the app usable and must not claim a successful tip.
