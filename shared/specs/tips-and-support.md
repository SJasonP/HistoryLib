# Developer Support Tips

Status: Apple implementation planned for v1.4. The feature is a voluntary
developer-support flow and does not unlock content or functionality.

## Product model

Apple clients may offer five consumable In-App Purchase products. The proposed
United States base prices are:

| Product ID | Base price | Display label |
| --- | ---: | --- |
| `com.SJasonP.HistoryLib.Tips.Level1` | $0.99 | Small tip |
| `com.SJasonP.HistoryLib.Tips.Level2` | $2.99 | Standard tip |
| `com.SJasonP.HistoryLib.Tips.Level3` | $5.99 | Generous tip |
| `com.SJasonP.HistoryLib.Tips.Level4` | $9.99 | Big tip |
| `com.SJasonP.HistoryLib.Tips.Level5` | $19.99 | Extra generous tip |

These are App Store Connect base prices. StoreKit must display the localized
`Product.displayPrice` for the current storefront. The values are common Apple
price points, not a promise that every storefront displays dollars.

The products are consumable because a user may purchase the same tip tier more
than once. A completed transaction is finished after StoreKit verifies it. The
app does not maintain a tip balance, unlock a feature, or treat a tip as a
license.

## Placement and copy

Manage places a `Support Us` action below `Help`. The support page explains
that HistoryLib is open source, ad-free, and free to use. It says that a tip is
optional developer support, has no effect on access, and unlocks nothing.

The purchase confirmation must state that the tip is voluntary, does not affect
app access, and is processed by Apple. It must state that refunds are decided
and processed by Apple and that HistoryLib cannot directly issue or guarantee a
refund. The user must choose Yes or No before StoreKit is called.

The app must not describe this flow as a charitable donation or require a tip
for access, ratings, reviews, sharing, or any other action.

## App Store Connect prerequisites

Before release, create all five consumable products in App Store Connect,
accept the Paid Apps Agreement, set the tax category, provide localized product
metadata, and submit the products with an app version. Sandbox testing must
cover product loading, unavailable products, cancellation, pending purchases,
verified transactions, failed verification, and repeated purchases.

The UI must remain usable when App Store Connect products are unavailable. It
must not invent a successful purchase or imply that a missing product was
charged.
