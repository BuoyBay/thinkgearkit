---
title: "thinkgearkit API contracts"
summary: "Usage and behavioral contracts for thinkgearkit."
category: "Reference"
symbols: ["ThinkGearBLENotification", "ThinkGearRawEvent", "ThinkGearState", "ThinkGearPacket", "ThinkGearTelemetryEvent", "ThinkGearDecoder", "ThinkGearConnection"]
related: ["index.md", "getting-started.md", "typed-api.md"]
---

# ThinkGearKit

Reusable native Buoy ThinkGear binary framing, Connector JSON decoding and sparse
telemetry with independent contact/attention/meditation freshness. Import
`thinkgearkit`. Scores remain in the headset's 0..100 range; zero on hardware is
unavailable. Gameplay requires connected input, fresh good contact and the
selected fresh nonzero score. The caller provides monotonic seconds.

`ThinkGearState` exposes telemetry and `Usable(nowSeconds,useMeditation=False)`.
`SetSimulated(attentionValue,meditationValue,nowSeconds)` explicitly marks simulated
input. `ThinkGearDecoder(state)` accepts incremental `FeedByte` binary packets or
`FeedJSONByte` CR/LF-delimited Connector JSON. Binary checksums and row boundaries
are checked before any telemetry updates. Extended/unknown rows are skipped.

`ThinkGearConnection(state)` owns one native transport. `OpenSerial(entryPath)`
uses a paired OS serial device at 57600 baud; `OpenTCP(host,port=13854)` connects
to a separately running Connector and requests JSON/raw output. `OpenMindWave`
uses the macOS direct IOBluetooth RFCOMM adapter. `OpenBLE(name)` uses the macOS
Mobile 2 CoreBluetooth profile and decodes its notifications as sparse JSON. Call `Poll(nowSeconds)` from the
GUI timer and `Close()` before shutdown or switching input. Poll has a bounded
byte budget and never blocks on data. DNS resolution when opening TCP may block.
Poll retries open/disconnect failures after two seconds and restarts open streams
silent for eight seconds. Set `AutoReconnect=False` to supply another policy.
`Close` cancels retries; no failure substitutes simulated values. Serial Bluetooth pairing/binding is an OS operation.

Maintainers run the private validation suite before release. See the repository README for public build instructions.

Linux and macOS ARM64 passed native PTY/TCP tests; direct macOS RFCOMM/BLE
passed real SDK builds and synthetic delegate fixtures without radio access.
Windows x64 native bridge cross-compiles; Windows execution is unverified.
See `native/transport-validation.json`, `native/MACOS.md` and `native/BLE-README.md`. Hardware radio
streaming remains unverified for this Buoy implementation; do not infer hardware
support from compiler checks or fixture transport tests.

The implementation ports protocol behavior from the sibling Mind Games project;
no Rust process or NeuroSky binary SDK is required.

It emits bounded-duration JSON diagnostics with byte/packet/raw counts, contact,
score freshness usability and transport errors. The last two modes require macOS.

## Original BLE recording

`ThinkGearConnection.DrainBLENotifications()` returns ordered, owned
`ThinkGearBLENotification` snapshots from the original CoreBluetooth callbacks,
before normalization or profile filtering. Every retained notification preserves
its sequence, host monotonic receive time, characteristic UUID, exact bytes as
hex, original byte length, accepted/rejected reason, native error and integrity
metadata. Unknown characteristics/tags, invalid lengths, empty/nil values,
notification errors and callbacks arriving after failure remain observable.
`HadValue` distinguishes nil from empty. `ValueMayBeCached` labels a characteristic
value supplied alongside an NSError; such bytes are recorded but never accepted
as a fresh sample. `JSON` retains the full native event metadata. Long textual
metadata can be truncated or sanitized to valid Unicode; the corresponding flags
are explicit and payload bytes are independent of those text changes.

`Received` maps the native timestamp to the caller's monotonic clock using the
first `Poll` clock offset. `NativeReceived` always retains the native timestamp.
When a connection is closed before its first poll, `ClockMapped=False` and
`Received=-1`; callers should retain native time and label any fallback receipt
time. Error/silence/explicit-close paths drain pending events before releasing the
native handle. Closing does not discard undrained notification events.

The native queue retains at most 4096 events and 4 MiB of encoded metadata;
a callback larger than 2 MiB cannot be retained. Reaching a bound stops the stream
and emits an explicit loss record after the earlier retained events, with dropped
event/byte counts. The Buoy queue retains at most 8192 events and 8 MiB; exceeding
it likewise preserves earlier events, emits a coalesced loss record and cancels
reconnection until explicitly opened again. `DroppedBLENotifications` reports
cumulative original-event losses across native handles and managed queue overflow.
Drain each frame; bounded queues cannot promise lossless recording if their
consumer stops. `Integrity=bluetooth_stack_no_payload_checksum` states that the
profile demonstrates no independent notification payload checksum; shape
acceptance does not establish checksum success.

`DrainTelemetryEvents()` additionally provides each sparse decoded update, its
cached snapshot and changed-field flags. Repeated same-value measurements remain
separate observations. Queues expose `DroppedTelemetryEvents`,
`DroppedPacketEvents`, and state `DroppedRaw` so recording can mark incompleteness.
Raw binary contact snapshots follow row order conservatively: a later contact
row never retroactively marks an earlier raw sample clean. This preserves multiple
raw rows and mixed-contact batches rather than collapsing them to the sibling
Rust parser's single final raw sample per packet. Malformed binary packets retain
complete prefix row metadata but never apply partial telemetry updates.

Maintainers run the private validation suite before release. See the repository README for public build instructions.

Failure and close recording semantics: native BLE failure reports failed status
immediately while previously accepted normalized records remain readable until
exhausted. Explicit `Close` performs a bounded 256 KiB final read and retains
owned raw, telemetry, packet and original-notification events for the caller to
drain after the visible state is reset. It cancels reconnection. Records decoded
by that final read use the latest poll clock; original BLE notifications retain
their own native reception time. `CloseReadBudgetExhaustions` explicitly signals
that this bounded final read may have left native bytes unconsumed; it does not
invent a count for unknown remaining bytes. `DroppedRawEvents` accumulates raw
queue loss across state resets. Drain pending recorder events before closing the
recording files. Binary `0x01` exposes `BatteryRaw`/`BatteryAt` unchanged in the
vendor byte range 0..255; it is not implicitly a percentage. Connector JSON
battery fields are not guessed where the sibling protocol defines none.


[Typed API](typed-api.md) · [Getting started](getting-started.md)
