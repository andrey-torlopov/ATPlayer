#ifndef RADIO_INTERFERENCE_H
#define RADIO_INTERFERENCE_H
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct RadioInterferenceGenerator RadioInterferenceGenerator;
typedef enum {
    RadioInterferencePhaseIdle = 0,
    RadioInterferencePhaseAttack = 1,
    RadioInterferencePhaseHold = 2,
    RadioInterferencePhaseRelease = 3
} RadioInterferencePhase;
typedef struct {
    float musicGain;
    float noiseRatio;
    float noiseSample;
    float normalizedNoise;
    float envelope;
    RadioInterferencePhase phase;
    bool eventStarted;
} RadioInterferenceFrame;

/// Allocation/destruction are off the render thread. Supports 8–384 kHz.
RadioInterferenceGenerator *RadioInterferenceCreate(double sampleRate, uint64_t seed);
void RadioInterferenceDestroy(RadioInterferenceGenerator *generator);
/// All functions below belong exclusively to one render owner; no concurrent controls.
/// Reset restores a reproducible sequence. Cancel clears the event and cached
/// source RMS, retaining PRNG/control-ramp state; a stopped source has no tail.
void RadioInterferenceReset(RadioInterferenceGenerator *generator, uint64_t seed);
void RadioInterferenceCancel(RadioInterferenceGenerator *generator);
/// A positive full-recording RMS preserves the source's burst/gap dynamics with
/// fixed gain. Zero/invalid restores the default adaptive procedural normalizer.
/// Configure while stopped, or exclusively from the render owner. Reset retains it.
void RadioInterferenceSetNoiseRMS(RadioInterferenceGenerator *generator, float fullRecordingRMS);
/// intensity and backgroundIntensity are 0–10, each ramping over 200 ms.
/// allowNewEvent freezes the idle countdown
/// when false, but lets an active event finish. Initial wait 3–6 s, later gaps 8–18 s;
/// attack 0.35–0.8 s, full-depth hold 1–6 s, recovery 0.6–1.2 s, independent of intensity.
/// Both smoothed controls map to effectiveLevel = 0.7 * UI level before the
/// original noise/music curves. UI 10 now matches original level 7 exactly:
/// peak noiseRatio 0.675 and minimum musicGain 0.425. Event timing is unchanged.
/// Between events musicGain stays 1. The original noise-ratio curve has points
/// 0 = 0, 1 = 0.2, 2 = 0.3, 10 = 0.9, linearly between them.
/// backgroundIntensity sets the bed; max(intensity, backgroundIntensity) sets
/// event peaks, never below the bed even for temporarily incoherent controls.
/// Equal levels give constant noise ratio. Both 0 ramp to exact clean;
/// source/transport silence still wins. The host should link background <= main.
/// Supply continuously generated unit-master noise, including between events, and
/// unattenuated source RMS (host freezes its reference during an event).
/// Music RMS changes use 4 ms smoothing, including the host silence gate.
/// The shared normalizer returns mono noiseSample already multiplied by
/// musicRMS and noiseRatio. Mix each source channel * musicGain + noiseSample.
/// The host still owns output limiting, silence/transport gates and source RMS.
/// No allocation, locks, callbacks, I/O or unbounded loops.
RadioInterferenceFrame RadioInterferenceNextFrame(RadioInterferenceGenerator *generator,
    float intensity, float backgroundIntensity, bool allowNewEvent, float unitNoise, float musicRMS);

#ifdef __cplusplus
}
#endif
#endif
