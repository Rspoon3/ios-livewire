# Logging

Persistent logging uses [CocoaLumberjack](https://github.com/CocoaLumberjack/CocoaLumberjack)
(`DDFileLogger`). The files exist so a real run on a real bike can be pulled off the phone and read,
which is how the undocumented API gets mapped.

## What is written

On disk, one JSON object per line (JSON Lines), timestamp first:

```json
{"ts":"2026-11-25T16:30:53.762Z","level":"INFO","process":"app","category":"http","msg":"← 200 GET bikes/101/charging/status (143 ms) body={…}","src":"Wire:44"}
```

| Field | Meaning |
|---|---|
| `ts` | UTC, millisecond precision. Fixed width, so files sort chronologically as plain text. |
| `level` | `DEBUG`, `INFO`, `WARN`, `ERROR` |
| `process` | `app` or `widget` |
| `category` | `http` (every request and response), `api`, `auth`, `service`, `store`, `keychain`, `widget`, `runtime`, … |
| `msg` | The message. For `http`, the request line and the full response body. |
| `src` | File and line that logged it. |

Every request is logged as `→ METHOD path?query` and every response as
`← STATUS METHOD path (ms) body=…`. That second line is what shows the real response shapes,
including the ride fields that are not mapped yet.

## Rotation

Per process: a new file every 24 hours or at 5 MB, at most 14 files, at most 50 MB in total.

## What is never written

* Passwords (they are only sent to Gigya, and Gigya's response is not logged at all).
* Any value under a key such as `password`, `jwt`, `token`, `uid`, `authorization`, `apiKey`, `email`
  (see `Redactor.sensitiveKeys`).
* The VIN, the SIM card's ICCID and other cellular identifiers, and anything under a GPS key (`latitude`, `longitude`, `coordinates`, `polyline`, `location`, …).
  The key stays in the log and the value becomes `<redacted>`, so the response shape is still visible.
* The pairing code (`code` in the verify request body).
* Anything shaped like a JWT or `Bearer …`, wherever it appears, including in free text.

Redaction is covered by tests (`LWLoggingTests`) and the file logger test asserts that a JWT never
reaches a file.

## What is still written, and is private

Redaction works on **known key names**. A field the app has never seen, with a name that is not on the
list, is logged as it arrives. Ride responses are the likeliest to hold one, for example a start address.
Responses also hold your bike's name, its battery and charging history, and the model and year.

So: read a log before you publish it, and turn it into a fixture with invented values before it goes
into the repository. Log files made by builds from before the VIN and GPS masking (2026-11-25) still
contain the VIN. Delete them with *Settings → Delete all logs*.

The log files sit in the app's Documents folder with `UIFileSharingEnabled` on, so they show in the Files
app and in Finder while the phone is unlocked and trusted. They are protected until the first unlock
after a restart. To switch the sharing off, remove `UIFileSharingEnabled` and
`LSSupportsOpeningDocumentsInPlace` from `Config/App/Info.plist`; the *Share logs* button keeps working.

## Getting the files

The widget runs in its own process and cannot write to the app's Documents folder, so it logs into the
shared App Group container. The app copies those files next to its own whenever it comes to the
foreground, or when you share.

1. **Share sheet.** One tap on *Share logs*: the button on the sign-in screen, or Settings → *Share logs*. This merges the app and
   widget logs into **one JSON file**, sorted by time (AirDrop it to your Mac or save it to Files). Its
   shape is `{"export": {app, appVersion, build, os, device, exportedAt, format}, "entryCount": 123, "entries": [ … ]}`,
   with one original log object per line inside `entries`, so `grep` still works. A line that is not valid
   JSON is kept as `{"raw": "…"}`. Earlier exports in the temporary folder are deleted when a new one is made.
2. **Files app.** *On My iPhone → ios-livewire → Logs* (`app/` and `widget/`).
3. **Finder.** Select the iPhone, open the *Files* tab, expand the app.
4. **Command line.** `scripts/pull-logs.sh device <device-id>` (uses `devicectl`), or
   `scripts/pull-logs.sh sim` for the simulator. Output goes to `./logs/`, which is git-ignored.

Then give the file, or the relevant lines, to whoever is mapping the API.
