# LiveWire mobile API (unofficial)

Everything here is **unofficial and undocumented**, and can change or stop working at any time. It
describes what this project's iOS client sends and receives, not a contract.

## Where this comes from

| Source | What it gave |
|---|---|
| [py-livewire](https://github.com/hass-livewire/py-livewire) (reverse-engineered from the **Android** app 1.9.0, Apache-2.0) | The endpoint paths, parameters, headers and error codes. Start there if you want a Python client. |
| The **iOS** app 1.9.0's `Info.plist` | Confirms the same backend (`mobileapi.livewire.com`), the same Gigya login provider and data center, and the same app version. |
| This project's own logs from a real bike | Confirms response shapes on an iOS client, 2026-11-25. |

The iOS app's binary is FairPlay-encrypted, so its code could not be read.

**Status legend.** *Confirmed* means this client called it against a real account and bike and the
response is documented below. *py-livewire only* means another project documents it and this one does
not rely on it. Sample values in this file are **invented**; only the shapes are real.

## Requests

Base URL `https://mobileapi.livewire.com/api`. Every request carries:

| Header or parameter | Value |
|---|---|
| `Authorization` | `Bearer <jwt>` (from the session call below) |
| `brand` (query) | `LiveWire` |
| `User-Agent` | `Android` |
| `model` | `Google Pixel 8` |
| `osVersion` | `34` |
| `Accept-Language` | `en-US` |
| `Content-Type` | `application/json` |

These are py-livewire's values. The first version of this client sent iPhone values and an uppercase
device UUID, and its pairing request timed out while py-livewire's worked. After the UUID was lowercased,
pairing succeeded, so the UUID case is the likely cause. Whether the Android headers matter on their own
has not been tested.

## Sign-in (confirmed)

1. `POST https://accounts.us1.gigya.com/accounts.login`, form-encoded: `apiKey`, `loginID`, `password`,
   `include=profile,data`, `format=json`. Returns `UID`. Errors come back with HTTP 200 and an `errorCode`
   (403042 wrong credentials; 206001 and 206002 account not finished).
2. `POST /session?brand=LiveWire`, JSON `{"UID", "deviceUUID", "dataCenter": "us1"}`. Returns
   `{"jwt": "...", "termsAccepted": true}`.
3. Send the JWT as `Authorization: Bearer <jwt>` on every later call.
4. On HTTP 401, repeat step 2 with the stored `UID`. The password is not needed again.

The Gigya API key is the one LiveWire's own apps use for every user. It is built into
`APIConfiguration.defaultGigyaAPIKey` and is also public in py-livewire's `const.py`.

## Device UUID and pairing (confirmed)

Every session is opened for a *device UUID*. The app makes its own (lowercase, for example
`123e4567-e89b-42d3-a456-426614174000`) and keeps it. It is not a secret: it is in every URL.

The charging status is only answered for UUIDs that are **paired** with the bike (otherwise error code
`3000`). Pairing is a cloud flow that needs you at the bike once, with the ignition on, not in
propulsion mode, not charging, and with cellular signal:

| Step | Call |
|---|---|
| Is this UUID paired? | `GET bikes/pairing/status/{bikeId}?deviceUUID=` → `{"pairingStatus": true}` |
| Make the bike show a code | `POST bikes/{bikeId}/pair?deviceUUID=` (no body) |
| Send the code back | `POST bikes/{bikeId}/verify/code?deviceUUID=` body `{"code": "123456"}` |

Responses are `{"command_name", "detail", "pairedUserCount", "start_time", "end_time", "status"}`:

```json
{"command_name":"C_pairing_code","detail":"{\"message\":\"Success\"}","pairedUserCount":0,"status":200}
{"command_name":"validate pairing code","detail":"{\"message\":\"Success\"}","pairedUserCount":3,"status":200}
```

* The pair call takes about 2 seconds when the bike answers. The code then appears on its display.
* If the bike does not answer, the backend waits about a minute and returns HTTP 200 with `status: 402`
  and `detail` `{"reason":"DEVICE_TIMEOUT","message":"Device did not respond in time"}`. So `402` means
  the bike never replied, not necessarily that it has no cellular signal.
* The verify call answers a wrong code with a top-level `code` of 4004, and too many tries with 4003
  (both from py-livewire; not seen here).
* **Several devices can be paired at once.** `pairedUserCount: 3` was the official app, py-livewire and
  this app on one bike. Pairing another device did not unpair the others.

## Endpoints

| Purpose | Call | Status |
|---|---|---|
| Bikes and pairing | `GET getAllbikes/pairingStatus?deviceUUID=` | Confirmed |
| **Battery** | `GET bikes/{id}/charging/status` | Confirmed |
| **Ride totals** | `GET bikes/{id}/ride/analytics?date=<ISO now>` | Confirmed |
| **Charging totals** | `GET bikes/{id}/charging/analytics?date=<ISO now>` | Confirmed |
| Saved rides | `GET rides?type=CUSTOM&includeWeather=metric\|imperial` | Answers; always empty so far |
| One ride | `GET rides/{id}?includeLocationHistory=` | Not seen: there is no saved ride to fetch |
| Location | `GET bike/{id}/location` | py-livewire only (the Diagnostics button calls it) |
| Tire pressure | `GET bikes/{id}/status/tpms?modelCode=` | py-livewire only (Diagnostics button) |
| Charge limit, schedules, maintenance, roadside assistance, dealers, account | | py-livewire only |

### Bikes

```json
{"bikes":[{"id":"123456789","vin":"1HD0XXXXXXXXXXXXX","name":"My Bike","make":"LiveWire",
  "model":"S2 Mulholland","modelCode":"S2MH","modelNumber":"0000","year":2024,"color":"Lunar White / Gray",
  "colorCode":"M37","brandShortName":"LW","primaryBike":true,"pairingStatus":true,
  "createdTime":"2026-01-01 00:00:00+0000","modifiedTime":"2026-01-01 00:00:00+0000"}]}
```

`pairingStatus` is whether **this device UUID** is paired, not whether the bike is paired with anyone.

### Battery

```json
{"bikeChargingData":{"batteryPercentage":64,"chargingStatus":false,"durationElapsed":"3","durationUnit":"minute",
  "maxLimit":80,"odometer":1234.5,"pluggedIn":false,"range":68,"timeToMaxLimit":"0.0"},"trackingStatus":"SAFE"}
```

* `range` and `odometer` are **miles**.
* `durationElapsed` is how old the bike's own report was. `durationUnit` was seen as `seconds` and `minute`
  (singular).
* `durationElapsed` and `timeToMaxLimit` are strings. `timeToMaxLimit` has only been seen as `"0.0"`, so
  its unit is unconfirmed (the app reads it as minutes).
* Error code `-300` is a partial answer that still carries data (from py-livewire).
* Not seen yet: a response while charging.

### Ride and charging totals

Both answer `{"bikeId", "vin", "periods": [...]}`. There are four periods, `WEEK`, `MONTH`, `3M` and `6M`.
Each has a `granularity` (`DAY`, `WEEK` or `MONTH`), a list of `buckets` and one `summary`.

```json
{"type":"MONTH","granularity":"WEEK",
 "buckets":[{"bucketStart":"2026-11-08","rideCount":4,"sumBatteryUsedPercent":40,"totalDistance":30,"totalEfficiencykWhPerKm":0.1}],
 "summary":{"rideCount":4,"totalBatteryUsedPercent":40,"totalDistance":30,"totalDurationSeconds":3600,"totalEfficiencykWhPerKm":0.1}}
```

```json
{"type":"MONTH","granularity":"WEEK",
 "buckets":[{"bucketStart":"2026-11-08","sessionCount":3,"energyAddedKwh":9,"energyLostKwh":2,"sumBatteryAddedPercent":80}],
 "summary":{"sessionCount":3,"energyAddedKwh":9,"energyLostKwh":2,"totalBatteryAddedPercent":80,"totalChargeTime":7200}}
```

* `totalDistance` has **no unit in the response**. It is almost certainly miles: with miles, 100% battery
  works out to about 10.3 kWh of riding and 10.6 kWh of charging (a 10.5 kWh pack), and the 6-month total
  sits just under the odometer. A ride of known length would settle it.
* `totalEfficiencykWhPerKm` is kWh per **kilometre** (the name says so) and is `null` for empty buckets.
* `totalChargeTime` and `totalDurationSeconds` are seconds.
* Most numbers are rounded to whole numbers; efficiency has three or four decimals.
* `bucketStart` is a plain date. Weeks start on Sunday.

### Saved rides

`GET rides?type=CUSTOM` is the app's "my rides" list (saved or planned rides). It returned `{"rides":[]}`
for an account with dozens of recorded rides, so it is **not** the bike's ride history. No endpoint that
lists recorded rides has been found; the totals above are the only ride data this client can read.

## Errors

* Errors mostly arrive as **HTTP 200** with `{"error": {"code": "...", "description": "..."}}`. `code "0"`
  is success. `3000` means this device is not paired, or the bike is unreachable.
* Pairing calls report failure inside the body as `status` instead (see above).
* Numbers and booleans may arrive as strings (`"82"`, `"true"`), so parsing is lenient (`JSONValue`).
* Unknown fields, periods and granularities are kept or ignored, never fatal.
