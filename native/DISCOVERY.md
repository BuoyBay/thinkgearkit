# Read-only known headset inventory

`tg_discover_headsets()` returns a borrowed UTF-8 JSON snapshot until the next
call. All bridge calls belong to one owning thread; macOS requires the main
thread. No platform scans, pairs, connects, or opens a serial device to discover
headsets.

The object contains Boolean `supported` and `complete`, string `error`, and an
array `devices`. Each device has string `id`, `name`, `endpoint`, `transport`,
and Boolean `pairing_known` and `paired`. At most 64 entries and 256 KiB of JSON
are returned. A bound, invalid candidate metadata, or OS inventory error sets
`complete:false` with a diagnostic. A successful empty inventory has
`complete:true`, an empty array, and an empty error.

On macOS the public IOBluetooth `pairedDevices` snapshot is filtered by names
containing MindWave, case insensitively, following the sibling driver's
`devices`/`paired_ids`. Its address becomes `bluetooth:ADDRESS` in both `id` and
`endpoint`; transport is `rfcomm`. Pairing is known and true. BLE devices are
not discoverable through this paired Classic inventory; manual BLE selection
remains available. No SDP operation occurs during inventory.

On Windows SetupAPI enumerates present Ports-class devices, reads their
`SPDRP_FRIENDLYNAME`, and filters names containing MindWave. `PortName` from
the device's registry key must be `COM` followed by digits. Id and endpoint are
`serial:COMn`, transport is `serial`. This uses the actual OS name where the
sibling's pathname-only filter cannot identify a COM port. The snapshot proves
only an existing named serial interface: `pairing_known` and `paired` are false.

On Linux only `/dev` and optional `/dev/serial/by-id` entries whose basename
contains MindWave are inspected. The resolved node must be a character device;
`stat`/`realpath` do not open it. Canonical path identity deduplicates symlinks,
and the lexically first matching endpoint alias is retained. Both identity and
endpoint carry `serial:` prefixes. An unnamed `/dev/rfcomm0` cannot establish
that the headset is a MindWave and is omitted. Serial pairing flags are false.
Generic device names, unexposed OS metadata, and two different serial endpoints
for the same physical headset cannot be resolved by this snapshot. Use manual
selection when names are unavailable or candidates are ambiguous.

Serial enumeration inspects at most 16384 entries per inventory directory on
Linux or present Ports inventory on Windows. macOS inspects at most 4096 paired
objects. Linux/macOS fixture injection exists only in tests; the production
entry point takes no arbitrary filesystem input. Platform compiler checks do
not establish Bluetooth hardware behavior.

Verification commands:

```sh
python3 build_native.py
python3 build_native.py --target x86_64-windows --cc x86_64-w64-mingw32-gcc
```

`discovery_macos_test.m` runs synthetic snapshots and a real paired inventory on
macOS without a radio operation. `discovery_inventory.c` calls the public ABI
for native platform inventory checks. Linux, macOS ARM64, and Windows x64 each
executed a successful empty real inventory in this workspace. Named physical
MindWave devices and multi-radio inventories remain unverified.

Test suites and fixtures are maintainer-local and are not part of this public repository.
