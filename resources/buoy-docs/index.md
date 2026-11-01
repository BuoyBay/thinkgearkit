---
summary: "ThinkGear state, explicit headset transports, simulation, and telemetry processing."
related: ["api.md", "getting-started.md", "typed-api.md"]
---

# ThinkGearKit

See the package README for explicit transport ownership and platform limits.

```buoy
Import thinkgearkit

Sub Main()
    Dim state As New ThinkGearState()
    state.SetSimulated(60, 50, 0.0)
    Print state.Usable(0.0)
End Sub
```

Public API:

- `ThinkGearState`: sparse integer attention, meditation, poor signal, delta, raw
  and blink fields; independent timestamp fields in monotonic seconds; eight band
  values plus `BandAt` timestamps. Unknown scores/contact are `-1`.
- `ThinkGearConnection(state)`: explicit `OpenSerial`, `OpenTCP`, `OpenMindWave`
  (macOS RFCOMM), `OpenBLE` (macOS Mobile 2), bounded `Poll`, and `Close`.
- `ThinkGearDecoder(state)`: independent incremental binary/JSON parsing, checksum
  and malformed-payload statistics. Decoding does not itself establish transport
  connectivity; the connection owns that state.
- `DrainRawEvents`: ordered `ThinkGearRawEvent` values (`Raw`, `Received`,
  `PoorSignal`, `SignalAt`). It shares ownership with the legacy `DrainRaw` API;
  choose one drain per frame. Records preserve raw samples during poor contact.
- `DrainPacketEvents`: ordered `ThinkGearPacket` values with `PayloadHex`, JSON
  row descriptors, `Received`, `Malformed` and `Protocol`.
- `DrainTransportHex`: received ABI bytes. BLE values are normalized JSON;
  serial/RFCOMM and Connector TCP values are their received wire bytes.

All objects and native handles belong to one owner thread. macOS radio lifecycle
must run on the main event-loop thread. Close each connection explicitly. No
Bluetooth pairing, permissions or physical hardware success is inferred from
opening a transport. See the package README and native validation reports.

Original BLE callback recording uses `DrainBLENotifications()`, returning
`ThinkGearBLENotification` with Sequence, NativeReceived, Received, ClockMapped,
CharacteristicUUID, PayloadHex, PayloadLength, Accepted, HadValue, Reason,
Integrity, ErrorDomain/ErrorCode/ErrorMessage, MetadataTruncated,
MetadataSanitized, ValueMayBeCached, IsOverflow and DroppedCount/DroppedBytes.
`JSON` preserves the complete native metadata. Rejected/unknown/error values are
retained; BLE normalized JSON is a separate derived stream. Drain each frame and
record explicit overflow counters; see the package README for native/managed
bounds and timestamp mapping before using the values in exported recordings.

`DrainTelemetryEvents()` returns copied sparse update snapshots and changed-field
flags. `Packets`, `ChecksumErrors`, `MalformedPayloads`, `DroppedPacketEvents`
and `DroppedTelemetryEvents` on a connection are cumulative across reconnections.

`DiscoverThinkGearHeadsets() As ThinkGearHeadsetInventory` reads existing OS
paired/named serial inventory without radio discovery or opening devices.
Inventory fields: Supported, Complete, Error, Devices. Each
`ThinkGearKnownHeadset` has Id, Name, Endpoint, Transport, PairingKnown and Paired.
macOS returns paired `bluetooth:ADDRESS` endpoints; Linux/Windows return known
MindWave-named `serial:PATH` sources without asserting pairing. An empty complete
inventory is a successful result; incomplete/error inventory remains explicit.
Generic serial names and BLE devices require manual source selection. All
macOS lifecycle/inventory calls require the main thread.
