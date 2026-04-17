# Latency Measurement Guide

Target: end-to-end < 10 ms from physical key press to acoustic sound onset.

## Method A — Microphone recording (mouth-to-ear)

### Equipment
- Any microphone (built-in works; condenser preferred)
- Audacity (free) or any DAW that shows a waveform

### Steps

1. Open Audacity. Set input to the microphone.
2. Start a new stereo recording: one channel from mic, one channel looped back from system audio (use BlackHole or Soundflower for the loopback channel).
3. Type on your keyboard — a single keypress is enough.
4. Stop recording.
5. Zoom into the waveform. Identify:
   - **T₀**: the transient spike from the physical key click (mic channel)
   - **T₁**: the onset of the synthesized sound (loopback channel)
6. Measure `T₁ − T₀` in samples, then convert:

   ```
   latency_ms = (T₁_sample − T₀_sample) / sample_rate × 1000
   ```

### Expected result

Under 10 ms. A typical result on Apple Silicon at 128-frame buffer and 48 kHz is 4–7 ms.

### Failure modes
- More than 10 ms: check `kAudioDevicePropertyBufferFrameSize` is actually 128; verify no extra AVAudioMixerNode hop is adding latency.
- Noisy floor: use a headphone splitter so the mic doesn't pick up speaker bleed.

---

## Method B — Instruments Audio System Trace

### Steps

1. Open Instruments (`xcode-select --install` if not present; or from Xcode menu Xcode → Open Developer Tool → Instruments).
2. Choose the **Audio System Trace** template.
3. Attach to the **KlinkMac** process.
4. Type at roughly 150 WPM for 30 seconds.
5. Stop the trace.
6. In the timeline, look at the **Audio I/O** track.
   - Each render callback is a colored bar.
   - **Green / within deadline** = good.
   - **Red / overrun** = the callback missed its deadline — audible dropout.
7. Confirm zero red markers.

### Reading the numbers

The I/O buffer duration at 128 frames / 48 kHz:

```
buffer_duration = 128 / 48000 = 2.667 ms
```

The render callback must complete in under 2.667 ms every cycle. CPU time per callback should be well under 1 ms on Apple Silicon.

---

## Method C — Timing within the app (coarse)

Add a `CACurrentMediaTime()` measurement at:
1. `EventQueue.push()` call site (in `KeyEventMonitor` callback)
2. `AudioEngine` render callback, immediately after draining the event that matches

Log the delta via `os.Logger` at `.debug` level. This measures queue-to-render time only (not input driver latency), so will read lower than the microphone method — typically 1–3 ms.

---

## Logging results

Record all measurements in `LATENCY_LOG.md` at the project root.
