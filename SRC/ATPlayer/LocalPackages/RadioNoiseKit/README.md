# RadioNoiseKit

Radio interference primitives with a portable C++17 C ABI (`RadioNoiseKit`) and a separate Apple-platform resource/decoder product (`RadioNoiseAssets`). The C++ core has no audio-framework dependency; the Swift asset loader uses AVFoundation outside rendering. The package supplies recorded and procedural mono textures, plus synchronized music gain and noise for absorption events. Hosts own transport, mix limiting and track scheduling.

## Recorded reference 12 — current default

ATPlayer and NoiseDemo now use the supplied `12-Uniden-radio-static-bursts.wav` as their default noise texture. The previous synthetic approximation was rejected during listening. The resource is a lossless single-channel copy of the exactly duplicated stereo input, with the original 24-bit samples and speed; see [asset provenance](Documentation/Reference12.md).

`RadioNoiseAssets.loadReference12(sampleRate:balanced:)` decodes and converts PCM before playback. The default `balanced: false` preserves the original PCM. ATPlayer and NoiseDemo use `balanced: true`: actual silent spans are omitted with smooth joins, two offline RMS gain passes level the recording, and an offline peak envelope softens isolated hits. This prepares the same recorded texture without adding synthetic tones; the original bundled WAV remains intact. `RadioSampleCreate(sampleRate, monoPCM, frameCount, seed)` copies this buffer outside render; `RadioSampleNextFrame` supplies it without filters, oscillators, adaptive compression or per-frame allocation. The seeded initial/read restart offset lies in the first quarter of the recording. Playback runs continuously to the end and makes a 50 ms raised-cosine splice whose weights sum to one. This preserves long uninterrupted passages rather than rapidly reshuffling short grains. `RadioSampleReset` belongs to the render owner or a stopped host and requires host muting/fading around a live reset.

For music absorption, call `RadioInterferenceSetNoiseRMS` with `RadioSampleRMS`. This uses fixed calibration `normalizedNoise = PCM / referenceRMS`, preserving the prepared buffer's waveform and remaining dynamics. Global RMS is a scale reference, not a guarantee for each short event. The host's final limiter still controls mix peaks. Missing/undecodable assets are reported as playback errors; ATPlayer does not silently substitute the rejected synthesis. Resource loading is skipped for source-gate-only audio units.

The separate `RadioNoiseAssets` product bundles PCM; use only `RadioNoiseKit` when a host needs the portable procedural/sampler API without an Apple asset decoder. No neural dependency is used.

## Procedural alternatives

The five procedural components are generated from seeded random streams, analytic envelopes and stable filters:

| Control | Generated component |
| --- | --- |
| `hissLevel` | Continuous filtered, middle-band noise |
| `crackleLevel` | Low receiver rumble, sparse large impulses among smaller clicks, damped low modes and smooth random fades |
| `resonanceLevel` | Random packets exciting fixed modes near 2.4, 4.4, 8.7 and 11 kHz, with a broad noise pedestal |
| `chatterLevel` | Irregular clusters of short, fading band-noise packets |
| `squelchLevel` | Persistent band-limited receiver noise, 25–280 ms bursts gathered in 0.8–3.8 s clusters, narrow modes near 2.39 and 4.61 kHz |

`character` changes event density, click decay and the depth/tone of retro fluctuations. Component controls change their independent amplitudes; `masterLevel` changes the final amplitude. All seven controls are clamped to `[0, 1]`, with nonfinite values mapped to zero. Defaults are `masterLevel = 0.2`, `character = 0.7`; the blended component levels are `0.16 / 0.85 / 0.10 / 0.24 / 0.24` in table order. `RadioNoiseParametersForPreset` supplies six parameter sets: blended, retro07, retro08, ringing, fading and uniden12. Presets are parameter values, not recorded sounds.

The refined reference profiles are `RadioNoisePresetRetro07` (alias of the original `RadioNoisePresetRetro`, value1), `RadioNoisePresetRetro08` (value5), and `RadioNoisePresetUniden12` (alias of `RadioNoisePresetSquelch`, value4). Existing enum values remain stable. Retro07 has deep, irregular fades; Retro08 is denser with a shallower envelope. Uniden12 uses the squelch component alone, avoiding unrelated retro rumble and high ringing in that profile. Its active bed remains between short bursts; the separate host interference envelope can then mask music without holes in the noise.

## Host integration

```swift
import RadioNoiseKit

guard let generator = RadioNoiseCreate(48_000, 2, 20261114) else {
    fatalError("Unsupported format or allocation failure")
}
var parameters = RadioNoiseDefaultParameters()
parameters.masterLevel = 0.2
RadioNoiseSetParameters(generator, parameters)

// Allocate before rendering; a live host instead supplies its audio buffers.
var left = [Float](repeating: 0, count: 256)
var right = [Float](repeating: 0, count: 256)
left.withUnsafeMutableBufferPointer { leftBuffer in
    right.withUnsafeMutableBufferPointer { rightBuffer in
        RadioNoiseRender(generator, leftBuffer.baseAddress,
                         rightBuffer.baseAddress, 256)
    }
}

// Control owner: restart the deterministic stream at a subsequent render block.
RadioNoiseReset(generator, 20261114)

// After stopping and detaching the audio callback:
RadioNoiseDestroy(generator)
```

Creation accepts sample rates from 8 to 384 kHz and one or two channels; invalid configurations return null. Mono rendering permits a null right pointer. Stereo rendering requires two distinct valid output buffers. Output replaces their contents. The sound is mono by design: most measured references were duplicated mono, and anti-phase interference is not imposed on a host's stereo music.

For a complete live callback and lifetime implementation, see [NoiseDemo's NoiseEngine](../../../NoiseDemo/NoiseDemo/NoiseEngine.swift).

`RadioNoiseBeginBlock` followed by one `RadioNoiseNextFrame` per sample offers a scalar adapter for another DSP kernel. It has the same stream and control behavior as `RadioNoiseRender`. Do not use both rendering interfaces concurrently. `RadioNoiseFrame.activity` is a bounded, smoothed event-activity value; a host can use it for its own reception model. The package does not prescribe that model.

## Thread and lifetime contract

- One control writer calls `SetParameters` and `Reset`. One render owner calls `Render`, or `BeginBlock` / `NextFrame`. These owners may run concurrently.
- Create and destroy outside the render callback. Finish all control and render calls before destroy. The package does not retain a callback or extend the lifetime of its own pointer.
- `Flush` is **render-owner-only**. It clears scheduler/filter tails without reseeding or changing controls. It cannot race the render API. `Reset` is the control-thread alternative and also restarts the stream and parameter ramps.
- All render state has fixed capacity. Rendering allocates no memory, takes no lock, invokes no callback, and performs no I/O. Control snapshots make one bounded attempt per block, retaining the previous snapshot if a writer overlaps.
- Parameter changes use 50 ms linear ramps. Settled `masterLevel == 0` returns exact zeros and performs no PRNG/filter work; parameter ramps can still settle in silence. The host owns muting and any music-relative noise floor.
- Output is bounded to `[-1, 1]` by `x / (1 + abs(x))` before the master gain. This is a sample bound, **not a reconstructed true-peak limiter**. The host must handle playback volume and final mix headroom.

The mailbox payload consists of atomic words, so even an unsuccessful read has no data race. The writer publishes an odd sequence, then a release fence, then relaxed payload stores, then an even release sequence. The reader loads the sequence with acquire, loads the payload, performs an acquire fence and verifies the sequence. Observing a new payload pairs the fences and makes the preceding odd sequence happen before the final sequence check; observing the final even sequence acquires the completed payload. A mixed concurrent snapshot therefore cannot pass as an unchanged old sequence. Reset uses the same pattern. The one-writer requirement is part of this argument; stress tests are additional evidence, not a substitute for it.

## Determinism and sample rates

With the same sample rate, parameters, seed and control-change frame boundaries, output is independent of render block partitioning on the same build/platform. `Reset(seed)` reproduces creation with that seed. Different sample rates or math-library/compiler implementations need not be bit-identical. Event timing uses seconds converted to frames; filter/noise excitation gains compensate for sample rate. Resonator coefficients are constructed once, never changed on active tails, and limited below Nyquist at low sample rates.

## Historical procedural calibration and limits

The initial model uses measured spectral and temporal classes from six user-supplied WAVs. It does not reproduce their waveforms, precise event sequence, duration or original volume. Those files span very different loudness and stereo behavior. Absolute reference volume and the strong anti-phase component of one reference are intentionally not copied.

The earlier November14 procedural experiment prioritized references07,08 and12; its Uniden12 timbre was subsequently rejected by the user and is no longer the app default. At48kHz, 30-second unit-master renders with seed `20261114` measured centroids of approximately423Hz (Retro07),475Hz (Retro08), and2041Hz (Uniden12); the corresponding references measured436,487 and1906Hz. The10ms RMS-envelope p90−p10 spans were18.44,7.96 and8.27dB, versus20.55,8.88 and7.94dB. Uniden12 has prominent synthesized modes near2391 and4605Hz; energy below300Hz is about0.09% of full-spectrum PSD. These measurements establish the intended spectral/dynamic families, **not a perceptual match**. The pulse sequence is randomized and never copies a source envelope.

Uniden12's30-second unit RMS is approximately0.0942, and its10ms RMS p10 is0.0541 after the startup ramp. Defaults multiply these by0.2. A host applying a music-relative envelope should explicitly select unit master and calibrate its own level. The user-supplied WAV amplitudes are not a playback loudness target. Other reference families remain available; the extreme crest and anti-phase behavior of reference11 are still not copied.

## Verification

```sh
swift test
clang++ -std=c++17 -O2 -I Sources/RadioNoiseKit/include \
  Sources/RadioNoiseKit/RadioNoiseKit.cpp Tools/render_presets.cpp \
  -o /tmp/radio-noise-render
/tmp/radio-noise-render /absolute/output/directory
clang++ -std=c++17 -O1 -g -fsanitize=address,undefined \
  -I Sources/RadioNoiseKit/include Tools/test_control_snapshot.cpp \
  -o /tmp/radio-noise-controls
/tmp/radio-noise-controls
```

The original nine Swift tests cover reset/seed reproducibility, block partitioning, all components, monotonic master gain, exact silence, invalid parameters, scalar/block equality,8–384kHz finite output and resonant presets at8kHz. `ReferenceTextureTests` additionally checks distinct07/08 envelope depth, persistent12 bed with bursts, and reference-profile rate extremes/block independence. The C++ sanitizer check exercises concurrent control/reset/render ownership and coherent snapshots. `Tools/render_presets.cpp` produces original30-second preset/component WAVs at unit master and prints the RMS formula `sqrt(sum(x²) / sampleCount)`. The repository's reference analyzer supplies separate spectral measurements. Passing these checks does not establish physical-device callback timing or listening acceptance.

## Absorption envelope

`RadioInterference.h` is also exported by the umbrella `RadioNoiseKit.h`. This optional render-owner-only API shares the same macro-event and noise-normalization law between ATPlayer and NoiseDemo. Allocate with `RadioInterferenceCreate(sampleRate, seed)`, destroy off the audio thread, and call `RadioInterferenceNextFrame(generator, intensity, backgroundIntensity, allowNewEvent, noise, musicRMS)` once per rendered frame. No concurrency is permitted on an interference context; hosts publish controls to their render owner separately.

The first idle interval is uniformly 3–6 seconds. Each event has a smooth cubic attack of 0.35–0.8 seconds, a full-depth hold of 1–6 seconds, and smooth recovery of 0.6–1.2 seconds. Subsequent intervals at the quiet background level last 8–18 seconds after recovery. Event timing is independent of intensity; `allowNewEvent=false` freezes the idle countdown and permits an active event to finish. `Cancel` immediately clears the event and cached music-RMS tail and chooses a new initial interval without reseeding; hosts use it at stopped transport boundaries. Ordinary ATPlayer track changes preserve the running texture and envelope. `Reset` restores the seeded sequence. Intensity changes ramp for 200 ms; settled zero cancels the old event once, remains exactly clean, and does not advance the schedule until enabled.

| UI level | Music gain during hold | Noise RMS target / pre-duck music RMS |
| --- | ---: | ---: |
| 0 | 1.0000 | 0.0000 |
| 1 | 0.8950 | 0.1400 |
| 2 | 0.8300 | 0.2400 |
| 5 | 0.6875 | 0.4125 |
| 7 | 0.5825 | 0.5175 |
| 8 | 0.5300 | 0.5700 |
| 10 | 0.4250 | 0.6750 |

Both UI levels first map through `effectiveLevel = 7 × uiLevel / 10`, then use the prior curves with breakpoints 0, 1 and 2. New level 10 therefore equals former level 7, including its music gain and noise peak. These are linear gains and source-relative RMS targets, not perceived loudness percentages or percentages whose sum must equal one. Returned `musicGain = 1 - loss × envelope`; `noiseRatio = bedRatio + (targetRatio - bedRatio) × envelope`; mix each input channel as `source × musicGain + noiseSample`. The separate background control uses the same noise mapping as the main control. A host keeps `0 <= backgroundIntensity <= intensity <= 10`: raising the floor above the maximum raises both; lowering the maximum below the floor lowers both. The helper independently ramps both values over 200 ms and remains bounded if a host briefly sends inconsistent controls. Background 0 allows silent intervals; equal levels hold a constant noise ratio while the accepted music-duck envelope remains active. For 10/7, the nominal noise range is 0.5175...0.675; equal 10/10 remains at 0.675. Level 0/0, stopped transport and the host silence gate still suppress noise.

Supply a continuous texture even through intervals between events. For recorded PCM, set a fixed positive reference RMS using `RadioInterferenceSetNoiseRMS`; reset preserves that configuration. This path divides by the calibrated RMS (minimum 0.0001), with only a pathological ±32 bound; it preserves the source crest and does not apply the adaptive ±3 bound below. Zero selects legacy adaptive normalization for procedural textures. A 250 ms EMA of its squared amplitude controls normalization, with RMS floor 0.04 and normalized sample bound ±3. The output `noiseSample` already includes normalization, the background/event balance and supplied unattenuated music RMS; `normalizedNoise` additionally exposes the bounded unit texture for diagnostics or another host's mixing logic. Normalization limits transient peaks, so a particular interval is not guaranteed to hit the RMS target exactly. Music RMS is additionally smoothed over 4 ms so the silence gate does not cut noise in one sample; zero settles to exact silence once this short tail falls below 0.0000001. Nonfinite values map to zero.

The host owns unattenuated source metering, transport gates and the final limiter. ATPlayer and NoiseDemo meter source power over 1 second and freeze the reference during an event. With positive background they retain the last audible reference across musical silence; a conservative RMS reference of 0.02 supplies a silent introduction before music has been measured. New events remain gated by audible source. With background zero, the existing 0.5-second quiet-source guard suppresses noise. Pause/Stop/EOF explicitly stop transport or the engine and silence the background. ATPlayer preserves its existing true-peak protection and 64-frame latency. The generator alone is not an output safety limiter.
