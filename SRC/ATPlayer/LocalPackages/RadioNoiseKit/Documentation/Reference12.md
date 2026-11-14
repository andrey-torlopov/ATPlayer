# Reference recording 12

The user supplied `Source/Radio/12-Uniden-radio-static-bursts.wav` as the preferred
sound reference and explicitly allowed using it as the basis of the radio effect.
This document records provenance and transformation; it asserts no additional license.

The bundled `Sources/RadioNoiseAssets/Resources/Uniden12.mono.wav` is a lossless
extraction of channel 1. Every 24-bit PCM frame was checked: both original stereo
channels are identical. The complete recording is retained without filtering,
normalization, trimming or sample-rate conversion. The original source is unchanged.

| Property | Value |
| --- | --- |
| Source SHA-256 | `2aae0c3f3e1e2c79357f59cd4cf9643ae4b206b6a217feced57ddd1be77541ee` |
| Bundled SHA-256 | `4c2f92a2d3a2db56e715786cb7fef28a43d45dcab400e62f5238885a2c0dc1ba` |
| Encoding | Mono signed PCM24, 48,000 Hz |
| Frames | 2,706,726 |
| Duration | 56.390125 s |
| Full-recording RMS | 0.03620129838839525 |
| Sample peak | 0.31603574752807617 |

For sample integer `p[i]`, `x[i] = p[i] / 8,388,608` and
`RMS = sqrt(sum(x[i]²) / 2,706,726)`. These values were calculated from all source
frames with a Python script; the same full-clip RMS calculation is performed after
device-rate conversion by `RadioNoiseAssets` and by the sampler when it copies PCM.

`RadioNoiseAssets.loadReference12(sampleRate:, balanced: false)` decodes every frame and converts
to the graph's sample rate with `AVAudioConverter` at maximum quality, off the audio
render thread. At 48 kHz the Float32 samples preserve the original PCM24 values
exactly. At other rates there is only sample-rate conversion, preserving duration
and pitch. The resource bundle also contains machine-readable provenance JSON.

`RadioSamplePlayer` consumes this prepared PCM without filtering or local gain
normalization. `RadioInterferenceSetNoiseRMS` calibrates mixing to the full clip,
preserving the dynamics of the selected preparation. The host separately applies smooth
absorption envelopes and the existing output limiter. ATPlayer fails AU allocation
if the resource cannot be loaded; it does not silently substitute procedural noise.

## Balanced playback preparation

ATPlayer and NoiseDemo request `balanced: true`. This optional offline preparation
uses only samples from the recording. It creates no oscillator or synthesized noise
and leaves the bundled WAV unchanged. The default raw load remains available for
comparison and its exact-PCM provenance tests.

The source contains near-silent spans at 0–0.12 s, 50.57–52.42 s and
55.93–56.390125 s. Amplifying their digital floor would change their sound without
providing useful continuous radio noise. The balanced preparation therefore detects
10 ms windows below RMS 0.005, omits them, keeps a 10 ms guard within audible spans,
and joins the remaining regions with 20 ms cosine crossfades. The result is 53.9 s.

Two gain passes use centered 20 ms RMS windows, bounded gain 0.25–4, and 10 ms
forward/backward smoothing. A 4 ms anticipatory gain envelope controls isolated
peaks around 0.105 without hard clipping. Final fixed normalization sets complete
clip RMS to 0.03 before output-rate conversion. All this occurs outside rendering.

Measured production-loader output at 48 kHz:

| Measurement | Result |
| --- | --- |
| Frames | 2,587,200 |
| RMS | 0.03 |
| Peak | 0.105199322 |
| Crest, `20 × log10(peak / RMS)` | 10.8978 dB |
| Circular 50 ms RMS, quarter-window stride | 0.027136963–0.033161975 |
| Circular 100 ms RMS, quarter-window stride | 0.028771773–0.031666767 |

The raw recording's corresponding all-frame RMS is 0.0362012984 and its peak is
0.316035748. The balance checks include the prepared clip's end/start windows;
sampler splice behavior is separately verified with the actual C++ player.
Across three seeded 120 s sampler runs, the existing smooth splice reaches a
minimum 50 ms RMS of 0.023278759 (22.4% below nominal); the worst within-run
maximum/minimum ratio is 1.4114 at 50 ms and 1.1699 at 100 ms. These values are
not presented as a strict global 20–30% range at 50 ms; the gap is brief and
smooth, with no near-silent recording window remaining.
`Tools/export_reference12.swift` exports the exact loader output for independent
rendering and measurement; it does not reproduce the preparation algorithm.
