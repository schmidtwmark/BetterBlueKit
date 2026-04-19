# Adding a New Brand / Region Client

This guide walks through implementing a new `APIClientProtocol` conformer for a brand+region combination that BetterBlueKit doesn't support yet. It covers reference implementations to crib from, how to capture live traffic from the official app when those references aren't enough, and the `bbcli` loop you'll use to iterate.

## What You're Building

A conforming type of [`APIClientProtocol`](../Sources/BetterBlueKit/API/APIClient.swift) that handles one `(Brand, Region)` pair. The protocol requires:

- `login() async throws -> AuthToken`
- `fetchVehicles(authToken:) async throws -> [Vehicle]`
- `fetchVehicleStatus(for:authToken:cached:) async throws -> VehicleStatus`
- `sendCommand(for:command:authToken:) async throws`
- Optional: `fetchEVTripDetails(for:authToken:)`, MFA hooks (`supportsMFA`, `sendMFACode`, `verifyMFACode`, `completeMFALogin`)

Subclass `APIClientBase` so you inherit logging, redaction, and the HTTP helpers (`performRequest`, `performJSONRequest`). See the existing clients for the shape:

- **[`HyundaiUSAAPIClient.swift`](../Sources/BetterBlueKit/API/HyundaiUSA/HyundaiUSAAPIClient.swift)** — simplest: header-based auth, single status endpoint, no MFA.
- **[`HyundaiCanadaAPIClient.swift`](../Sources/BetterBlueKit/API/HyundaiCanadaAPI/HyundaiCanadaAPIClient.swift)** — Cloudflare cookie handshake, cached vs. real-time split, per-command PIN auth.
- **[`HyundaiEuropeAPIClient.swift`](../Sources/BetterBlueKit/API/HyundaiEurope/HyundaiEuropeAPIClient.swift)** — OAuth flow, CCS2 payloads.
- **[`KiaUSAAPIClient.swift`](../Sources/BetterBlueKit/API/KiaUSA/KiaUSAAPIClient.swift)** — MFA-required login, separate real-time refresh endpoint.

Keep commands split into a `+Commands.swift` extension and parsing in a `+Parsing.swift` extension — every existing client follows this layout.

## Where to Find Protocol Specs

Don't reverse-engineer unless you have to. Several mature open-source clients already map these APIs:

- **[bluelinky](https://github.com/Hacksore/bluelinky)** (TypeScript) — covers US/CA/EU for both brands, actively maintained.
- **[hyundai_kia_connect_api](https://github.com/Hyundai-Kia-Connect/hyundai_kia_connect_api)** (Python) — used by Home Assistant, broadest region coverage including AU.
- **[egmp-bluelink-scriptable](https://github.com/andyfase/egmp-bluelink-scriptable)** (TypeScript/Scriptable) — iOS-only E-GMP client with US/CA/EU coverage; handy second opinion when bluelinky and hyundai_kia_connect_api disagree, and the Scriptable sandbox means every API call is self-contained and easy to read.

Search those repositories for the region-specific base URL or a distinctive header name, then map endpoint-by-endpoint. Variable names and field shapes will be similar even across languages.

## Capturing Proxy Logs Yourself

When no reference exists, or a reference disagrees with what you see in practice, capture the official app's traffic:

1. **Install a proxy** on your Mac — [Proxyman](https://proxyman.com/) is my favorite; [mitmproxy](https://mitmproxy.org/) should also work
2. **Trust the proxy's CA on your phone.** In iOS: Settings → General → VPN & Device Management → install the profile, then Settings → General → About → Certificate Trust Settings → enable full trust.
3. **Route phone traffic through the proxy.** Wi-Fi settings → configure manual HTTP proxy pointing at your Mac's IP + proxy port.
4. **Disable ATS pinning if needed.** Hyundai/Kia apps occasionally use certificate pinning; Proxyman's "SSL Proxying" tab lets you add the app's bundle ID to bypass it. If the app refuses to talk, pinning is the likely cause.
5. **Drive the app.** Log in, list vehicles, open a vehicle, tap lock/unlock, start climate, etc. Each tap generates a request you'll need to replicate.
6. **Export each session.** Proxyman → File → Save Session. Attach the `.proxymansession` or equivalent to your issue / PR.

Treat the captured `authorization` / `accessToken` / cookies as secrets — don't paste raw captures into the repo. Scrub or use Proxyman's "Redact Sensitive Data" feature.

## Registering Your Client

Two call-sites in [`APIClientFactory.swift`](../Sources/BetterBlueKit/API/APIClientFactory.swift):

1. Add your region to the `switch configuration.region` inside `createHyundaiClient` / `createKiaClient`, instantiating your new class.
2. Add the region to `supportedRegions(for:)` (and `betaRegions(for:)` if the client is still rough).

That's all the wiring the app needs — `BBAccount` / `APIClientFactory` in the main app build on this factory.

## Testing with bbcli

`bbcli` is a command-line driver that exercises the same `APIClientProtocol` methods the app uses. It lives in the `BetterBlueKit` Swift package and is the fastest iteration loop for a new client.

### Build & run

```bash
cd BetterBlueKit
swift run bbcli --help
```

### Interactive mode

```bash
swift run bbcli -b hyundai -r EU -u you@example.com -p 'yourpassword' --pin 1234
```

Flags:
- `-b / --brand` — `hyundai` or `kia`
- `-r / --region` — `USA`, `Canada`, `Europe` (your new region lands here)
- `-u / --username`, `-p / --password`, `--pin` — credentials
- `--no-redaction` — print full HTTP logs (tokens, cookies). Use only when iterating locally.

Once logged in you get a menu — fetch vehicles, fetch status, lock/unlock, start/stop climate, start/stop charge, set charge limits, fetch trip details. Each command prints the request/response; on a 4xx/5xx you'll see exactly which header or body field the server rejected.

### Parse-only mode

When you're iterating on the response parser specifically, dump a real response to a file and re-parse without making a network call:

```bash
# Full status response
swift run bbcli parse -b hyundai -r EU -t vehicleStatus --electric ./response.json

# Vehicles list
swift run bbcli parse -b hyundai -r EU -t vehicles ./vehicles.json
```

`bbcli parse` unwraps a top-level `"responseBody"` automatically, so you can paste in an HTTPLog debug export straight from Settings → Export Debug Data without trimming.

### Typical iteration loop

1. Write the stub — `login()`, `fetchVehicles()`, everything else throwing `regionNotSupported`.
2. Run `bbcli ... ` → fix login errors.
3. Implement `fetchVehicles` → run → diff the parsed struct against the reference implementation's mapping.
4. Implement `fetchVehicleStatus` → use `bbcli parse` on captured responses to iterate on parsing without burning rate limits.
5. Implement commands one at a time — lock is always the simplest starting point.
6. Only once lock/unlock work, tackle climate and charging.

## Common Pitfalls

- **Stable device IDs.** Some regions (notably Kia USA) bind sessions to the `deviceid` header and invalidate sessions if it changes. Generate once per account and persist via `APIClientConfiguration.deviceId`.
- **Cloudflare / bot challenges.** Canada's mybluelink.ca sets a Cloudflare cookie on first request; subsequent requests must replay it. See `ensureCloudFlareCookie()` in `HyundaiCanadaAPIClient.swift`.
- **Refresh vs. cached.** The `cached: Bool` parameter on `fetchVehicleStatus` signals whether the caller wants a real-time vehicle modem poll (slow, rate-limited) or a cached server snapshot. Degrade gracefully — never return stale data silently if the caller asked for real-time.
- **HTTP log population.** Pass `vin: vehicle.vin` to `performJSONRequest` on every per-vehicle call so debug exports can filter by VIN.
- **Temperatures.** Regions encode cabin/target temperature differently. Canada's Gen3 payload uses a hex ladder (`"00H"` → 14°C); Europe sends Celsius doubles. Use [`Temperature(units:value:)`](../Sources/BetterBlueKit/Models/Measurements.swift) when you have a clean number, otherwise write a small helper and add a bbcli parse test.

## When You're Done

- Add at least one captured response fixture under your region folder so future maintainers have something to re-parse.
- Remove `betaRegions(for:)` membership once the client passes every menu action in `bbcli`.
- Update the troubleshooting supported-regions table in [`Troubleshooting.md`](../Sources/BetterBlueKit/Resources/Troubleshooting.md).
- Open the PR with the proxy session attached (or a note that a reference implementation covered it). Include the `bbcli` runs you used to verify.
