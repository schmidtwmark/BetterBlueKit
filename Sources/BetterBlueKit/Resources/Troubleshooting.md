# BetterBlue Troubleshooting

If none of the below fixes your issue, [open a GitHub issue](https://github.com/schmidtwmark/BetterBlue/issues).

## Resolving Login Issues

- Verify the credentials work in the official MyHyundai or Kia app.
- Make sure the region matches where your vehicle is registered.
- Hyundai commands need your 4-digit BlueLink PIN.
- Kia may prompt for an MFA code — tap the red error banner to retry.
- An active BlueLink or Kia Connect subscription is required.

## Apple Watch Syncing

- Add accounts on the iPhone first — the Watch reads iCloud data, it can't sign in.
- Both devices must be signed into the same iCloud account.
- Initial sync can take a few minutes. Keep the phone nearby.
- Tap **Sync Info** on the Watch's empty state for a diagnostic dump.

## Widget Issues

- Widgets refresh on an interval you set in Settings; iOS caps how often they can update.
- Configure the widget (long-press → Edit Widget) to pick the vehicle and preset.
- Enable Live Activities in Settings if you want them during long-running commands.
- After adding or removing a vehicle, re-add the widget to pick it up.

## Supported Regions

| Brand / Region | Status |
|----------------|--------|
| Hyundai — USA | ✅ |
| Hyundai — Canada | ✅ |
| Hyundai — Europe | ✅ |
| Hyundai — Australia | ❌ |
| Kia — USA | ✅ |
| Kia — Canada | ❌ |
| Kia — Europe | ❌ |
| Kia — Australia | ❌ |
| China / India | ❌ |

Unsupported regions are open for contributions on [BetterBlueKit](https://github.com/schmidtwmark/BetterBlueKit).
