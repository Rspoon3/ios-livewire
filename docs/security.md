# Security and privacy

This is a personal tool for your own account and your own bike. These are the facts about what it keeps,
what it sends and where it is weak.

## Where the app talks

Two hosts, both over HTTPS, nothing else:

* `https://accounts.us1.gigya.com` (sign-in, the identity provider LiveWire uses)
* `https://mobileapi.livewire.com` (the LiveWire backend)

There is no analytics, no crash reporting and no other server. App Transport Security is left at its
default (HTTPS only, no exceptions). The app does **not** pin certificates.

## What is stored, and where

| Item | Where | Notes |
|---|---|---|
| Password | **Nowhere** | Sent to Gigya once and dropped. Gigya's reply is never logged. |
| Gigya UID | Keychain | Long-lived. It can mint new session tokens, so treat it like a credential. |
| Session token (JWT) | Keychain | Replaced when the backend answers 401. |
| Device UUID | Keychain | Not a secret (it is in every URL), but pairing belongs to it, so it is kept. |
| Bikes and last battery state | A file in the App Group container | Includes the **VIN**. Protected until first unlock. Shared with the widget. |
| Logs | `Documents/Logs` and the App Group container | Redacted, see below. |

Keychain items use `afterFirstUnlockThisDeviceOnly` through [Valet](https://github.com/square/Valet): the
widget can read them while the phone is locked (once it has been unlocked since boot), and they are not
backed up or synced to another device.

## The hard-coded Gigya API key

`APIConfiguration.defaultGigyaAPIKey` is the key LiveWire's own app signs in with, the same for every
user. It identifies the *app*, not you, and is public in
[py-livewire](https://github.com/hass-livewire/py-livewire). It is in the repository on purpose. If
LiveWire rotates it, sign-in fails with a Gigya error and the constant is the one place to change.

## Logs

Every request and response is logged so the API can be mapped from real runs. Before anything is written:

* values under keys such as `password`, `jwt`, `token`, `uid`, `authorization`, `apiKey`, `email` are masked;
* so are the **VIN** and GPS fields (`latitude`, `longitude`, `coordinates`, `polyline`, `location`, …);
* so is the pairing code;
* anything shaped like a JWT or `Bearer …` is masked wherever it appears.

Redaction is by key name, so an unfamiliar field is **not** masked. See [logging.md](logging.md) for what
is left in and how to share a log safely. The log files are readable in the Files app and Finder because
file sharing is on; remove the two Info.plist keys named in that document to turn it off.

## What is not in this repository

No account details, tokens, VINs, bike IDs, device UUIDs or location data. Test fixtures use invented
values. `.gitignore` excludes `logs/`, `*.log`, `*.jsonl`, `ios-livewire-*.json` (a saved export), `*.ipa`
and `Payload/`.

The Xcode project does name a development team and a bundle prefix. Change `LW_BUNDLE_PREFIX` and the
signing team to your own to build it.

## Known weak points

* An unofficial client that identifies itself to LiveWire's backend as an Android phone. It may break at
  any time, and using it may be against LiveWire's terms. Use it on your own account only.
* No certificate pinning, so a device that trusts a hostile root certificate could be intercepted.
* The VIN is stored in the shared snapshot file, in clear but protected by iOS file protection.
* Anyone who unlocks the phone and opens the Files app can read the redacted logs.
* Pairing is per device, and this app adds one more paired device to the bike. There is no unpair flow
  in the app yet.

## Dependencies

[CocoaLumberjack](https://github.com/CocoaLumberjack/CocoaLumberjack) (logging) and
[Valet](https://github.com/square/Valet) (Keychain), pinned in `Package.resolved`.
