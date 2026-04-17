# Latency Log

Measurements taken per the procedure in `Tools/latency-measurement.md`.

| Date | Method | Hardware | Buffer (frames) | Sample rate | Measured latency | Notes |
|------|--------|----------|-----------------|-------------|------------------|-------|
| — | — | — | — | — | — | Not yet measured — record first result here |

## Target

< 10 ms end-to-end (key press transient → acoustic onset), verified on Apple Silicon.

## How to add an entry

1. Run KlinkMac in Release configuration.
2. Follow Method A (microphone) or Method B (Instruments) from `Tools/latency-measurement.md`.
3. Add a row to the table above with the date, method, machine model, and measured latency in ms.
4. If latency > 10 ms, open an investigation before shipping Phase 2.
