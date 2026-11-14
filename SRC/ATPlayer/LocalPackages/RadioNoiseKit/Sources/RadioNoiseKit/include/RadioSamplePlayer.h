#ifndef RADIO_SAMPLE_PLAYER_H
#define RADIO_SAMPLE_PLAYER_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct RadioSamplePlayer RadioSamplePlayer;

/// Copies mono Float32 PCM already converted to sampleRate (8–384 kHz).
/// Allocate/destroy only outside render. Returns NULL for invalid, nonfinite or
/// out-of-range PCM (samples must be within [-1,1]), or allocation failure.
/// At least eight frames are required. Source samples remain unmodified.
RadioSamplePlayer *RadioSampleCreate(double sampleRate, const float *monoPCM,
                                    uint64_t frameCount, uint64_t seed);
void RadioSampleDestroy(RadioSamplePlayer *player);

/// Immutable global RMS of the copied PCM, measured before splice crossfades.
/// Hosts can use this for fixed calibration without flattening the source envelope.
float RadioSampleRMS(const RadioSamplePlayer *player);

/// Exactly one render owner; no concurrent calls, allocation, locks or I/O.
/// The first read and each splice choose a seeded offset in the first quarter of
/// the recording, then play it continuously at original speed until its end.
/// Only the final 50 ms (at most 1/8 of short fixtures) crossfade to the next offset.
/// Crossfade weights sum to one; no filter, limiter or amplitude normalization.
float RadioSampleNextFrame(RadioSamplePlayer *player);
void RadioSampleRender(RadioSamplePlayer *player, float *mono, uint32_t frames);

/// Render-owner or stopped-host only. Repeats the seeded sequence exactly.
/// Reset is discontinuous by design; the host must mute/fade around a live reset.
void RadioSampleReset(RadioSamplePlayer *player, uint64_t seed);

#ifdef __cplusplus
}
#endif
#endif
