# macOS direct RFCOMM backend

`macos.m` implements the MindWave Bluetooth Classic SPP path using the public
IOBluetooth API. It selects an already paired device by exact address/name;
empty, `auto`, and default `MindWave` selectors select the first paired device
whose name begins with MindWave (case insensitive), sorted by address. Pairing remains an OS operation. This code does not use
ThinkGear Connector, a vendor SDK, `/dev/cu.*`, or the sibling Rust application.

Call every entry point from the macOS main thread and poll regularly. Open starts
an asynchronous service query; status/read pump the default run loop, discover
SPP UUID 0x1101, open its advertised RFCOMM channel and consume copied callback
bytes. The byte queue is bounded at 1 MiB; overflow, closed channels, discovery
and open timeouts, and eight seconds of stream silence become explicit failures.
The caller owns reconnection. Close detaches the delegate before releasing the
channel. SDP uses no callback target, allowing close during discovery safely.
No background thread or synchronous wait owns a Bluetooth session.

ABI (64-bit signed handles/results; positive handle or zero on open failure):

- `tg_macos_open_rfcomm(const char *name_or_address)`
- `tg_macos_status(handle)`: 0 failed/invalid, 1 connecting, 2 channel open.
- `tg_macos_read_byte(handle)`: 0–255 byte, -1 pending, -2 failed.
- `tg_macos_close(handle)`: releases this session.
- `tg_macos_error()`: borrowed UTF-8 text; copy before another operation.

Channel open does not establish good electrode contact or fresh EEG. The shared
ThinkGear parser/state must establish those conditions from received packets.
This backend handles Bluetooth Classic; it does not implement CoreBluetooth BLE.

Compile the library with ARC and Foundation, IOBluetooth and CoreFoundation:

```sh
clang -fobjc-arc -Wall -Wextra -Werror -dynamiclib macos.m \
  -framework Foundation -framework IOBluetooth -framework CoreFoundation \
  -o libbuoy_thinkgear.dylib
clang -fobjc-arc -Wall -Wextra -Werror macos_test.m \
  -framework Foundation -framework IOBluetooth -framework CoreFoundation \
  -o macos-test
./macos-test
```

On 2026-10-31 these commands passed natively on the available `m4-vi` lab,
macOS 27.0.1 ARM64, Apple clang 21.0.0. Tests exercise invalid handles, main-thread
rejection, synthetic delegate bytes including NUL/high bytes, partial queue
compaction, connected state, stream timeout, queue overflow, open timeout and
cleanup. Tests make no Bluetooth radio calls. This is native SDK/ABI and synthetic
state evidence; no physical headset streaming or Bluetooth authorization UI was
exercised. The source port draws on `../mind-games/src/macos.rs`; that project's
hardware results do not establish hardware verification for this implementation.
