#ifndef ATPLAYER_RADIO_DSP_H
#define ATPLAYER_RADIO_DSP_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RadioDSP RadioDSP;
typedef enum {
    RadioDSPPhaseBypassed = 0,
    RadioDSPPhaseReceiving = 1,
    RadioDSPPhaseInterference = 2
} RadioDSPPhase;

/// Allocation/destruction happen only while the render graph is stopped.
RadioDSP *RadioDSPCreate(double sampleRate, uint32_t channels, uint64_t seed);
void RadioDSPDestroy(RadioDSP *dsp);
uint32_t RadioDSPLatencyFrames(void);
/// Copies mono PCM at the DSP sample rate and calibrates fixed full-clip RMS.
/// Call only during allocation/while stopped; never concurrently with rendering.
/// Failure leaves any previous sample intact. Hosts must handle failure explicitly.
bool RadioDSPSetReferenceSample(RadioDSP *dsp, const float *monoPCM, uint64_t frameCount);
/// Resource lifecycle diagnostic; query only while rendering is stopped.
bool RadioDSPHasReferenceSample(const RadioDSP *dsp);

/// One control-thread writer; render reads bounded atomic snapshots, never waits.
/// Both levels use the 0...10 intensity scale. Background is clamped to main.
void RadioDSPSetSettings(RadioDSP *dsp, int32_t effect, int32_t background);
void RadioDSPSetTransport(RadioDSP *dsp, bool active);
/// Updates the remaining track time without interrupting the current radio event.
/// Stop/seek reset the reception envelope through the transport gate instead.
void RadioDSPResetReception(RadioDSP *dsp, double remainingSeconds);

/// Planar Float32, in place, mono or stereo. No allocation, locking or callbacks.
/// sampleTime is the AU render timestamp in the current graph's sample rate.
/// Returns true exactly when every output sample is zero.
bool RadioDSPProcess(RadioDSP *dsp, float *left, float *right, uint32_t frames, int64_t sampleTime);
int64_t RadioDSPRenderedSampleTime(const RadioDSP *dsp);
RadioDSPPhase RadioDSPCurrentPhase(const RadioDSP *dsp);
uint64_t RadioDSPInterferenceCount(const RadioDSP *dsp);
/// Zero-latency source gate; INT64_MAX means open. Independent of radio settings.
void RadioDSPSetSourceGate(RadioDSP *dsp, int64_t closeFrame);
bool RadioDSPProcessSourceGate(RadioDSP *dsp, float *left, float *right, uint32_t frames, int64_t sampleTime);

#ifdef __cplusplus
}
#endif
#endif
