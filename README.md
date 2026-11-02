# ThinkGear decoder + MindWave serial/TCP/BLE

Reusable native ThinkGear binary framing, Connector JSON decoding and sparse
telemetry with independent contact/attention/meditation freshness. Import
`thinkgearkit`. Scores remain in the headset's 0..100 range; zero on hardware is
unavailable. Gameplay requires connected input, fresh good contact and the
selected fresh nonzero score. The caller provides monotonic seconds.

`ThinkGearState` exposes telemetry and `Usable(nowSeconds,useMeditation=False)`.
`SetSimulated(attentionValue,meditationValue,nowSeconds)` explicitly marks simulated
input. `ThinkGearDecoder(state)` accepts incremental `FeedByte` binary packets or
`FeedJSONByte` CR/LF-delimited Connector JSON. Binary checksums and row boundaries
are checked before any telemetry updates. Extended/unknown rows are skipped.

## Install

From a Buoy consumer project with BPM installed:

```sh
bpm add thinkgearkit --git https://github.com/BuoyBay/thinkgearkit.git --rev refs/heads/main
```

BPM records the resolved commit in its lockfile. Keep that lockfile with the
consumer project for reproducible installs.

## API entrypoints

- `ThinkGearState`
- `Usable(nowSeconds,useMeditation=False)`
- `SetSimulated(attentionValue,meditationValue,nowSeconds)`
- `ThinkGearDecoder(state)`
- `FeedByte`

## Build and API reference

Source is in `modules/`, with native/runtime inputs where required. Use the
[package guide](docs/API.md) for backend-specific build prerequisites, ownership
rules and supported targets. Rebuilding a native backend requires that target's
compiler and SDK; sealing an archive alone does not rebuild the backend.

## Local Buoy setup

On your own machine, install Buoy and run:

```sh
buoy ai init --both
```

## Contributing

[Contributing](CONTRIBUTING.md) · [License](LICENSE)
