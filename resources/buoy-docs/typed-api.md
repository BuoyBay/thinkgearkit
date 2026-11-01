---
title: "thinkgearkit typed API"
summary: "Source-derived public signatures, properties, parameters, defaults, and return values."
category: "Reference"
order: 21
types: ["ThinkGearBLENotification", "ThinkGearConnection", "ThinkGearDecoder", "ThinkGearHeadsetInventory", "ThinkGearKnownHeadset", "ThinkGearPacket", "ThinkGearRawEvent", "ThinkGearState", "ThinkGearTelemetryEvent"]
dependencies: []
symbols: ["ThinkGearBLENotification", "ThinkGearConnection", "ThinkGearDecoder", "ThinkGearHeadsetInventory", "ThinkGearKnownHeadset", "ThinkGearPacket", "ThinkGearRawEvent", "ThinkGearState", "ThinkGearTelemetryEvent"]
related: ["api.md", "getting-started.md", "index.md"]
---

# thinkgearkit typed API

Generated from the package source declarations. Platform guards are shown where present; inherited members are documented on the base type. See the [API contracts](api.md) for behavior and limitations.

## ThinkGearKnownHeadset

`Public Class ThinkGearKnownHeadset`

Known OS inventory entry; enumeration neither opens nor pairs a device.

### Properties

| Name | Type | Read-Only | Shared | Default | Description |
| --- | --- | --- | --- | --- | --- |
| `Id` | `String` | No | No | `""` | — |
| `Name` | `String` | No | No | `""` | — |
| `Endpoint` | `String` | No | No | `""` | — |
| `Transport` | `String` | No | No | `""` | — |
| `PairingKnown` | `Boolean` | No | No | `False` | — |
| `Paired` | `Boolean` | No | No | `False` | — |

## ThinkGearHeadsetInventory

`Public Class ThinkGearHeadsetInventory`

### Properties

| Name | Type | Read-Only | Shared | Default | Description |
| --- | --- | --- | --- | --- | --- |
| `Supported` | `Boolean` | No | No | `False` | — |
| `Complete` | `Boolean` | No | No | `False` | — |
| `Error` | `String` | No | No | `""` | — |
| `Devices` | `Array Of ThinkGearKnownHeadset` | No | No | `[]` | — |

## ThinkGearKit functions

### DiscoverThinkGearHeadsets

`Public Function DiscoverThinkGearHeadsets() As ThinkGearHeadsetInventory`

Read existing paired macOS devices or named serial inventory, without radio discovery.

No parameters.

#### Returns

| Type |
| --- |
| `ThinkGearHeadsetInventory` |

## ThinkGearBLENotification

`Public Class ThinkGearBLENotification`

Original characteristic notifications, including rejected/unknown values.

### Properties

| Name | Type | Read-Only | Shared | Default | Description |
| --- | --- | --- | --- | --- | --- |
| `Sequence` | `Integer` | No | No | — | — |
| `Received` | `Double` | No | No | — | — |
| `NativeReceived` | `Double` | No | No | — | — |
| `ClockMapped` | `Boolean` | No | No | `False` | — |
| `CharacteristicUUID` | `String` | No | No | `""` | — |
| `PayloadHex` | `String` | No | No | `""` | — |
| `PayloadLength` | `Integer` | No | No | `0` | — |
| `Accepted` | `Boolean` | No | No | `False` | — |
| `HadValue` | `Boolean` | No | No | `False` | — |
| `MetadataTruncated` | `Boolean` | No | No | `False` | — |
| `MetadataSanitized` | `Boolean` | No | No | `False` | — |
| `ValueMayBeCached` | `Boolean` | No | No | `False` | — |
| `Reason` | `String` | No | No | `""` | — |
| `Integrity` | `String` | No | No | `"bluetooth_stack_no_payload_checksum"` | — |
| `ErrorDomain` | `String` | No | No | `""` | — |
| `ErrorCode` | `Integer` | No | No | `0` | — |
| `ErrorMessage` | `String` | No | No | `""` | — |
| `IsOverflow` | `Boolean` | No | No | `False` | — |
| `DroppedCount` | `Integer` | No | No | `0` | — |
| `DroppedBytes` | `Integer` | No | No | `0` | — |
| `JSON` | `String` | No | No | `""` | — |

## ThinkGearRawEvent

`Public Class ThinkGearRawEvent`

### Properties

| Name | Type | Read-Only | Shared | Default | Description |
| --- | --- | --- | --- | --- | --- |
| `Raw` | `Integer` | No | No | — | — |
| `Received` | `Double` | No | No | — | — |
| `PoorSignal` | `Integer` | No | No | — | — |
| `SignalAt` | `Double` | No | No | — | — |

## ThinkGearState

`Public Class ThinkGearState`

Sparse telemetry; caller supplies a monotonic clock in seconds.

### Properties

| Name | Type | Read-Only | Shared | Default | Description |
| --- | --- | --- | --- | --- | --- |
| `Attention` | `Integer` | No | No | `-1` | — |
| `Meditation` | `Integer` | No | No | `-1` | — |
| `BatteryRaw` | `Integer` | No | No | `-1` | — |
| `BatteryAt` | `Double` | No | No | `-1.0` | — |
| `PoorSignal` | `Integer` | No | No | `-1` | — |
| `Delta` | `Integer` | No | No | `-1` | — |
| `Raw` | `Integer` | No | No | `0` | — |
| `BlinkStrength` | `Integer` | No | No | `0` | — |
| `BlinkCount` | `Integer` | No | No | `0` | — |
| `RawCount` | `Integer` | No | No | `0` | — |
| `AttentionAt` | `Double` | No | No | `-1.0` | — |
| `MeditationAt` | `Double` | No | No | `-1.0` | — |
| `SignalAt` | `Double` | No | No | `-1.0` | — |
| `DeltaAt` | `Double` | No | No | `-1.0` | — |
| `RawAt` | `Double` | No | No | `-1.0` | — |
| `BlinkAt` | `Double` | No | No | `-1.0` | — |
| `Simulated` | `Boolean` | No | No | `False` | — |
| `Connected` | `Boolean` | No | No | `False` | — |
| `BandAt` | `Array Of Double` | No | No | — | — |
| `DroppedRaw` | `Integer` | No | No | `0` | — |
| `Bands` | `Array Of Integer` | No | No | — | — |

### Constructor

`Public Sub Constructor()`

No parameters.

Returns: no value.

### Reset

`Public Sub Reset()`

No parameters.

Returns: no value.

### PushRaw

`Public Sub PushRaw(value As Integer, nowSeconds As Double)`

#### Parameters

| Name | Type | Passing | Default |
| --- | --- | --- | --- |
| `value` | `Integer` | `ByVal` | Required |
| `nowSeconds` | `Double` | `ByVal` | Required |

Returns: no value.

### DrainRaw

`Public Function DrainRaw() As Array Of Integer`

No parameters.

#### Returns

| Type |
| --- |
| `Array Of Integer` |

### DrainRawEvents

`Public Function DrainRawEvents() As Array Of ThinkGearRawEvent`

No parameters.

#### Returns

| Type |
| --- |
| `Array Of ThinkGearRawEvent` |

### Usable

`Public Function Usable(nowSeconds As Double, useMeditation As Boolean = False, freshness As Double = 3.0) As Boolean`

#### Parameters

| Name | Type | Passing | Default |
| --- | --- | --- | --- |
| `nowSeconds` | `Double` | `ByVal` | Required |
| `useMeditation` | `Boolean` | `ByVal` | `False` |
| `freshness` | `Double` | `ByVal` | `3.0` |

#### Returns

| Type |
| --- |
| `Boolean` |

### SetSimulated

`Public Sub SetSimulated(attentionValue As Integer, meditationValue As Integer, nowSeconds As Double)`

#### Parameters

| Name | Type | Passing | Default |
| --- | --- | --- | --- |
| `attentionValue` | `Integer` | `ByVal` | Required |
| `meditationValue` | `Integer` | `ByVal` | Required |
| `nowSeconds` | `Double` | `ByVal` | Required |

Returns: no value.

## ThinkGearPacket

`Public Class ThinkGearPacket`

### Properties

| Name | Type | Read-Only | Shared | Default | Description |
| --- | --- | --- | --- | --- | --- |
| `Received` | `Double` | No | No | — | — |
| `PayloadHex` | `String` | No | No | `""` | — |
| `Rows` | `String` | No | No | `""` | — |
| `Malformed` | `Boolean` | No | No | `False` | — |
| `Protocol` | `String` | No | No | `"thinkgear"` | — |

## ThinkGearTelemetryEvent

`Public Class ThinkGearTelemetryEvent`

One decoded sparse update with an owned cached snapshot and presence flags.

### Properties

| Name | Type | Read-Only | Shared | Default | Description |
| --- | --- | --- | --- | --- | --- |
| `Received` | `Double` | No | No | — | — |
| `Attention` | `Integer` | No | No | `-1` | — |
| `Meditation` | `Integer` | No | No | `-1` | — |
| `BatteryRaw` | `Integer` | No | No | `-1` | — |
| `BatteryAt` | `Double` | No | No | `-1.0` | — |
| `ChangedBattery` | `Boolean` | No | No | `False` | — |
| `PoorSignal` | `Integer` | No | No | `-1` | — |
| `AttentionAt` | `Double` | No | No | `-1.0` | — |
| `MeditationAt` | `Double` | No | No | `-1.0` | — |
| `SignalAt` | `Double` | No | No | `-1.0` | — |
| `Bands` | `Array Of Integer` | No | No | `[]` | — |
| `ChangedBands` | `Array Of Boolean` | No | No | `[]` | — |
| `ChangedAttention` | `Boolean` | No | No | `False` | — |
| `ChangedMeditation` | `Boolean` | No | No | `False` | — |
| `ChangedSignal` | `Boolean` | No | No | `False` | — |
| `Raw` | `Integer` | No | No | `0` | — |
| `HasRaw` | `Boolean` | No | No | `False` | — |
| `BlinkStrength` | `Integer` | No | No | `0` | — |
| `ChangedBlink` | `Boolean` | No | No | `False` | — |

### Constructor

`Public Sub Constructor()`

No parameters.

Returns: no value.

## ThinkGearDecoder

`Public Class ThinkGearDecoder`

Incremental ThinkGear binary framing and bounded Connector JSON lines.

### Properties

| Name | Type | Read-Only | Shared | Default | Description |
| --- | --- | --- | --- | --- | --- |
| `Packets` | `Integer` | No | No | `0` | — |
| `ChecksumErrors` | `Integer` | No | No | `0` | — |
| `MalformedPayloads` | `Integer` | No | No | `0` | — |
| `DroppedPacketEvents` | `Integer` | No | No | `0` | — |
| `DroppedTelemetryEvents` | `Integer` | No | No | `0` | — |

### DrainTelemetryEvents

`Public Function DrainTelemetryEvents() As Array Of ThinkGearTelemetryEvent`

No parameters.

#### Returns

| Type |
| --- |
| `Array Of ThinkGearTelemetryEvent` |

### DrainPacketEvents

`Public Function DrainPacketEvents() As Array Of ThinkGearPacket`

No parameters.

#### Returns

| Type |
| --- |
| `Array Of ThinkGearPacket` |

### DrainPackets

`Public Function DrainPackets() As Array Of String`

No parameters.

#### Returns

| Type |
| --- |
| `Array Of String` |

### Constructor

`Public Sub Constructor(state As ThinkGearState)`

#### Parameters

| Name | Type | Passing | Default |
| --- | --- | --- | --- |
| `state` | `ThinkGearState` | `ByVal` | Required |

Returns: no value.

### FeedByte

`Public Sub FeedByte(value As Integer, nowSeconds As Double)`

#### Parameters

| Name | Type | Passing | Default |
| --- | --- | --- | --- |
| `value` | `Integer` | `ByVal` | Required |
| `nowSeconds` | `Double` | `ByVal` | Required |

Returns: no value.

### FeedJSONByte

`Public Sub FeedJSONByte(value As Integer, nowSeconds As Double)`

#### Parameters

| Name | Type | Passing | Default |
| --- | --- | --- | --- |
| `value` | `Integer` | `ByVal` | Required |
| `nowSeconds` | `Double` | `ByVal` | Required |

Returns: no value.

### FeedJSON

`Public Sub FeedJSON(line As String, nowSeconds As Double)`

#### Parameters

| Name | Type | Passing | Default |
| --- | --- | --- | --- |
| `line` | `String` | `ByVal` | Required |
| `nowSeconds` | `Double` | `ByVal` | Required |

Returns: no value.

## ThinkGearConnection

`Public Class ThinkGearConnection`

Explicit single-owner transport; poll from a GUI timer, close before replacing.

### Properties

| Name | Type | Read-Only | Shared | Default | Description |
| --- | --- | --- | --- | --- | --- |
| `LastError` | `String` | No | No | `""` | — |
| `AutoReconnect` | `Boolean` | No | No | `True` | — |
| `DesiredConnection` | `Boolean` | No | No | `False` | — |
| `Reconnects` | `Integer` | No | No | `0` | — |
| `LastByteAt` | `Double` | No | No | `-1.0` | — |
| `CloseReadBudgetExhaustions` | `Integer` | No | No | `0` | — |
| `DroppedRawEvents` | `Integer` | Yes | No | — | — |
| `Packets` | `Integer` | Yes | No | — | — |
| `ChecksumErrors` | `Integer` | Yes | No | — | — |
| `MalformedPayloads` | `Integer` | Yes | No | — | — |
| `DroppedTelemetryEvents` | `Integer` | Yes | No | — | — |
| `DroppedPacketEvents` | `Integer` | Yes | No | — | — |
| `DroppedBLENotifications` | `Integer` | No | No | `0` | — |
| `IsOpen` | `Boolean` | Yes | No | — | — |

### DrainTelemetryEvents

`Public Function DrainTelemetryEvents() As Array Of ThinkGearTelemetryEvent`

No parameters.

#### Returns

| Type |
| --- |
| `Array Of ThinkGearTelemetryEvent` |

### DrainBLENotifications

`Public Function DrainBLENotifications() As Array Of ThinkGearBLENotification`

No parameters.

#### Returns

| Type |
| --- |
| `Array Of ThinkGearBLENotification` |

### Constructor

`Public Sub Constructor(state As ThinkGearState)`

#### Parameters

| Name | Type | Passing | Default |
| --- | --- | --- | --- |
| `state` | `ThinkGearState` | `ByVal` | Required |

Returns: no value.

### OpenSerial

`Public Function OpenSerial(entryPath As String) As Boolean`

#### Parameters

| Name | Type | Passing | Default |
| --- | --- | --- | --- |
| `entryPath` | `String` | `ByVal` | Required |

#### Returns

| Type |
| --- |
| `Boolean` |

### OpenTCP

`Public Function OpenTCP(host As String, port As Integer = 13854) As Boolean`

#### Parameters

| Name | Type | Passing | Default |
| --- | --- | --- | --- |
| `host` | `String` | `ByVal` | Required |
| `port` | `Integer` | `ByVal` | `13854` |

#### Returns

| Type |
| --- |
| `Boolean` |

### OpenMindWave

`Public Function OpenMindWave(name As String = "MindWave") As Boolean`

#### Parameters

| Name | Type | Passing | Default |
| --- | --- | --- | --- |
| `name` | `String` | `ByVal` | `"MindWave"` |

#### Returns

| Type |
| --- |
| `Boolean` |

### OpenBLE

`Public Function OpenBLE(name As String = "MindWave") As Boolean`

#### Parameters

| Name | Type | Passing | Default |
| --- | --- | --- | --- |
| `name` | `String` | `ByVal` | `"MindWave"` |

#### Returns

| Type |
| --- |
| `Boolean` |

### DrainRaw

`Public Function DrainRaw() As Array Of Integer`

No parameters.

#### Returns

| Type |
| --- |
| `Array Of Integer` |

### DrainRawEvents

`Public Function DrainRawEvents() As Array Of ThinkGearRawEvent`

No parameters.

#### Returns

| Type |
| --- |
| `Array Of ThinkGearRawEvent` |

### DrainPackets

`Public Function DrainPackets() As Array Of String`

No parameters.

#### Returns

| Type |
| --- |
| `Array Of String` |

### DrainPacketEvents

`Public Function DrainPacketEvents() As Array Of ThinkGearPacket`

No parameters.

#### Returns

| Type |
| --- |
| `Array Of ThinkGearPacket` |

### DrainTransportHex

`Public Function DrainTransportHex() As String`

No parameters.

#### Returns

| Type |
| --- |
| `String` |

### Poll

`Public Function Poll(nowSeconds As Double, maxBytes As Integer = 16384) As Integer`

#### Parameters

| Name | Type | Passing | Default |
| --- | --- | --- | --- |
| `nowSeconds` | `Double` | `ByVal` | Required |
| `maxBytes` | `Integer` | `ByVal` | `16384` |

#### Returns

| Type |
| --- |
| `Integer` |

### Close

`Public Sub Close()`

No parameters.

Returns: no value.
