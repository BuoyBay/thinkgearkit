# MindWave Mobile 2 BLE

`ble.m` directly uses Apple's CoreBluetooth framework. It is a newly written
Objective-C implementation of the MindWave Mobile 2 BLE profile.
It links no NeuroSky SDK and starts no helper process.

The full service UUID is `039afff0-2c94-11e3-9e06-0002a5d5c51b`.
The eSense, raw EEG and command characteristic UUIDs replace `fff0` with `fff8`,
`fff4`, and `ffa0`. Stream commands are 20 bytes: `77 01 17` for eSense and
`77 01 15` for raw, zero padding through byte 18, and a one's complement sum
of bytes 1–18 in byte 19. Both subscriptions and both acknowledged writes must
succeed before transport status becomes open.

Calling open initiates an explicit scan for a device whose advertised name
contains MindWave; the target can select a UUID or exact name, or `auto`. The default `MindWave`
selector matches names starting with MindWave, ignoring case.
All lifecycle/poll/close calls belong on the macOS main thread. The main queue
receives delegates. The ABI status/read call services the default run loop
without waiting. It times out discovery/connection/configuration and rejects a
stream with no valid measurement for five seconds. Reopening/retry scheduling
belongs to the caller. The app bundle needs `NSBluetoothAlwaysUsageDescription`;
the user's OS authorization must permit Bluetooth.

`tg_ble_read_byte` returns normalized UTF-8 NDJSON bytes. These are decoded
measurements, **not original transport frames** and not serial AA/AA packets:

- Raw notifications must contain exactly ten signed big-endian 16-bit values.
  Each becomes a `rawEeg` record.
- EA notifications update `poorSignalLevel` and both eSense scores; scores above
  100 reject the notification.
- EB and EC notifications must contain exactly 20 bytes. Each updates only its
  own four `eegPower` fields, preserving sparse freshness in the Buoy parser.
  The eighth field is normalized as `highGamma`, matching the JSON parser.
- Other notifications are ignored. Battery notifications are not subscribed.

The bounded 256 KiB receive queue fails explicitly on overflow. Malformed
notifications do not produce measurement values or refresh the stream timeout.
When a stream fails, `tg_status` reports failure immediately, while normalized
records accepted before that failure remain readable. `tg_read_byte` drains those
bytes before returning -2. This preserves already received raw/telemetry data for
recording; the application must gate gameplay on connection/freshness separately.
Late notifications after failure are recorded as rejected originals and do not
produce new normalized measurements. Explicit close releases both native queues.

A separate original-notification queue preserves each characteristic callback
before decoding. Drain `tg_drain_ble_event(handle)` before close, including after
a failed status/read. Empty drain returns NULL. A returned UTF-8 JSON pointer is
borrowed until the next drain on that handle (including an empty drain) or close;
copy it before either operation. Draining does not pump the run loop. Close frees
the native queue, so the Buoy owner must first copy pending events into its queue.

Normal records contain `seq`, `monotonic_seconds`, `protocol`, `uuid`, `length`,
`bytes_hex`, `had_value`, `accepted`, `reason`, `integrity` and `error`.
`bytes_hex` preserves exact bytes, including malformed and unknown values;
`had_value` distinguishes nil NSData from present empty NSData. Error callbacks
preserve their available characteristic value and error domain/code/message;
`value_may_be_cached` is true because CoreBluetooth can expose its cached value
when a callback reports an error. Such values are never decoded. In-flight
callbacks after failure are retained with `accepted:false,reason:stream_failed`.
`integrity:bluetooth_stack_no_payload_checksum` explicitly makes no application
payload checksum claim. Shape acceptance is separate from link integrity.

`tg_monotonic_seconds()` uses the same `mach_continuous_time` epoch as event
receipt timestamps. Receipt is captured in the notification callback, before
encoding or decoding. Timeouts use this monotonic clock too. Buoy callers can
map that epoch into their own clock using the age relative to native now.

The original queue is bounded to 4096 records and 4 MiB of encoded JSON.
A callback payload above 2 MiB cannot fit as hex and is rejected before allocating
a hex copy. Overflow permanently stops recording/decoding and preserves the
previous queue; every subsequently received callback increments explicit lost
record/byte counters instead of silently resuming. Drain retained events first,
then a synthetic `event_type:overflow` record with `dropped_count`, `dropped_bytes`,
`first_dropped_monotonic_seconds`, and `reason:recording_queue_overflow`.
Its `seq` is the latest received sequence, not an additional original notification.
A later drain returns another summary only if the lost count increased.
`tg_ble_events_dropped(handle)` exposes the cumulative count directly.
The summary has `integrity:recording_incomplete` and does not invent missing bytes.
Error domain/message metadata is limited to 4096 characters each, and UUID to
128; `metadata_truncated` and original lengths explicitly describe truncation.
Truncation preserves Unicode scalar boundaries; malformed native UTF-16 metadata
is sanitized to U+FFFD with `metadata_sanitized:true`, preserving payload evidence.
The exact payload byte field itself is never truncated.

This bridge currently does not expose battery, scan-list UI, auto reconnection,
or platform backends beyond macOS.

Native SDK compilation and synthetic callback handling have been exercised on
macOS ARM64. Physical headset streaming, Bluetooth authorization UI, radio loss
and other architectures remain unverified for this implementation.
