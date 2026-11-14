#ifndef RADIO_NOISE_KIT_H
#define RADIO_NOISE_KIT_H
#include <stdbool.h>
#include <stdint.h>
#include "RadioInterference.h"
#include "RadioSamplePlayer.h"
#ifdef __cplusplus
extern "C" {
#endif

typedef struct RadioNoiseGenerator RadioNoiseGenerator;
typedef struct {
    float masterLevel;
    float character;
    float hissLevel;
    float crackleLevel;
    float resonanceLevel;
    float chatterLevel;
    float squelchLevel;
} RadioNoiseParameters;

typedef struct {
    float left;
    float right;
    /// Smoothed event activity in [0,1], independent of an application's music.
    float activity;
} RadioNoiseFrame;

typedef enum {
    RadioNoisePresetBlended = 0,
    RadioNoisePresetRetro = 1,
    RadioNoisePresetRinging = 2,
    RadioNoisePresetFadingBursts = 3,
    RadioNoisePresetSquelch = 4,
    RadioNoisePresetRetro08 = 5,
    /// Reference names are aliases; existing preset values remain stable.
    RadioNoisePresetRetro07 = RadioNoisePresetRetro,
    RadioNoisePresetUniden12 = RadioNoisePresetSquelch
} RadioNoisePreset;

RadioNoiseParameters RadioNoiseDefaultParameters(void);
RadioNoiseParameters RadioNoiseParametersForPreset(RadioNoisePreset preset);

/// Allocate/destroy off the audio thread. 8–384 kHz; one or two channels.
RadioNoiseGenerator *RadioNoiseCreate(double sampleRate, uint32_t channels, uint64_t seed);
void RadioNoiseDestroy(RadioNoiseGenerator *generator);

/// One control-thread writer. Nonfinite values become zero; all controls clamp to [0,1].
/// Parameters are consumed as one bounded atomic snapshot on the next render block.
void RadioNoiseSetParameters(RadioNoiseGenerator *generator, RadioNoiseParameters parameters);
/// Request a deterministic reset; latest request wins. Applied by the render owner.
void RadioNoiseReset(RadioNoiseGenerator *generator, uint64_t seed);

/// Exactly one render owner. No allocation, locks, callbacks, I/O or retained PCM.
/// Writes planar Float32 output, bounded to [-1,1]. Mono permits right == NULL.
/// Control ramps use 50 ms; settled masterLevel == 0 is exact silence and no PRNG work.
void RadioNoiseRender(RadioNoiseGenerator *generator, float *left, float *right, uint32_t frames);

/// Sample-accurate adapter: call BeginBlock once, then NextFrame once per frame.
/// Do not interleave this pair with RadioNoiseRender on another thread.
void RadioNoiseBeginBlock(RadioNoiseGenerator *generator);
RadioNoiseFrame RadioNoiseNextFrame(RadioNoiseGenerator *generator);
/// Render-owner-only: clear tails/schedulers without reseeding; no control-thread call.
void RadioNoiseFlush(RadioNoiseGenerator *generator);

#ifdef __cplusplus
}
#endif
#endif
