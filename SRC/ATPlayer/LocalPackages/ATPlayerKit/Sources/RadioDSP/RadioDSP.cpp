#include "RadioDSP.h"
#include "RadioNoiseKit.h"
#include "RadioInterference.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <limits>
#include <new>

namespace {
constexpr double pi = 3.14159265358979323846;
constexpr unsigned latency = 64;
constexpr unsigned detectorTaps = 32;
// Conservative reference for a playing file that begins with digital silence.
// Once music is audible, its last measured RMS owns the background level.
constexpr float silentIntroReferenceRMS = 0.02f;
// External 8x, 64-tap reconstruction tests include near-Nyquist sweeps and
// overloaded square edges. Reserve headroom beyond the internal 4x detector.
constexpr float ceiling = 0.74989421f; // -2.5 dBFS; target reconstructed ceiling -1 dBTP.
static_assert(std::atomic<uint64_t>::is_always_lock_free, "Realtime controls require lock-free atomics");
static_assert(std::atomic<int64_t>::is_always_lock_free, "Realtime timeline requires lock-free atomics");
static_assert(std::atomic<uint32_t>::is_always_lock_free, "Realtime controls require lock-free atomics");

float clean(float x) { return std::isfinite(x) ? x : 0; }

struct Ramp {
    float value = 0, target = 0, step = 0;
    int64_t remaining = 0;
    void to(float next, int64_t frames) {
        if (next == target) return;
        target = next;
        remaining = std::max<int64_t>(1, frames);
        step = (target - value) / float(remaining);
    }
    float tick() {
        if (remaining > 0) { value += step; if (--remaining == 0) value = target; }
        return value;
    }
};

}

struct RadioDSP {
    const double rate;
    const uint32_t channels;
    std::atomic<uint32_t> settings{0}, resetSerial{0};
    // Low bit is active; upper bits are the Stop generation. One coherent read.
    std::atomic<uint64_t> transportCommand{0};
    std::atomic<int64_t> remainingFrames{0}, rendered{0};
    std::atomic<int64_t> sourceGateClose{std::numeric_limits<int64_t>::max()};
    std::atomic<uint32_t> phase{RadioDSPPhaseBypassed};
    std::atomic<uint64_t> eventCount{0};
    uint32_t seenReset = 0;
    uint64_t seenStop = 0;
    bool wasActive = false;
    int64_t activeFrames = 0, trackEnd = 0;
    float requestedEffect = 0, requestedBackground = 0;
    RadioInterferencePhase interferencePhase = RadioInterferencePhaseIdle;
    RadioInterferenceGenerator *interference;
    RadioNoiseGenerator *noiseGenerator;
    RadioSamplePlayer *samplePlayer = nullptr;
    const uint64_t sampleSeed;
    Ramp effect, protection;
    float rmsSquared = 0, inputPower = 0, referenceRMS = 0;
    int64_t quietFrames = 0;
    float noiseEnvelope = 0;
    float delayDry[2][latency]{}, delayWet[2][latency]{}, delayMix[latency]{}, delayProtection[latency]{};
    float detector[2][detectorTaps]{};
    float interpolation[4][detectorTaps]{};
    unsigned cursor = 0, detectorCursor = 0;
    float limiterGain = 1, limiterTarget = 1;
    int limiterHold = 0;
    const float rmsAlpha, inputPowerAlpha, smoothingAlpha, limiterRelease;

    RadioDSP(double sr, uint32_t ch, uint64_t seed)
        : rate(sr), channels(ch), interference(RadioInterferenceCreate(sr, seed)),
          noiseGenerator(RadioNoiseCreate(sr, 1, seed ^ 0xd1b54a32d192ed03ULL)),
          sampleSeed(seed ^ 0x94d049bb133111ebULL),
          rmsAlpha(float(1 - std::exp(-1 / sr))),
          inputPowerAlpha(float(1 - std::exp(-1 / (0.02 * sr)))),
          smoothingAlpha(float(1 - std::exp(-1 / (0.004 * sr)))),
          limiterRelease(float(1 - std::exp(-1 / (0.08 * sr)))) {
        auto parameters = RadioNoiseParametersForPreset(RadioNoisePresetUniden12);
        parameters.masterLevel = 1; // Host noiseEnvelope owns audible level.
        RadioNoiseSetParameters(noiseGenerator, parameters);
        // 4x windowed-sinc reconstruction detector. Its delay fits inside lookahead.
        for (unsigned p = 0; p < 4; ++p) {
            double sum = 0;
            for (unsigned k = 0; k < detectorTaps; ++k) {
                double x = double(k) - 15.0 - double(p) / 4;
                double sinc = std::abs(x) < 1e-12 ? 1 : std::sin(pi * x) / (pi * x);
                double window = 0.42 - 0.5 * std::cos(2 * pi * k / (detectorTaps - 1))
                                       + 0.08 * std::cos(4 * pi * k / (detectorTaps - 1));
                interpolation[p][k] = float(sinc * window); sum += sinc * window;
            }
            for (auto &coefficient : interpolation[p]) coefficient /= float(sum);
        }
    }

    ~RadioDSP() {
        RadioSampleDestroy(samplePlayer);
        RadioNoiseDestroy(noiseGenerator);
        RadioInterferenceDestroy(interference);
    }

    void clearHistory() {
        for (unsigned c = 0; c < 2; ++c) {
            std::fill(std::begin(delayDry[c]), std::end(delayDry[c]), 0);
            std::fill(std::begin(delayWet[c]), std::end(delayWet[c]), 0);
            std::fill(std::begin(detector[c]), std::end(detector[c]), 0);
        }
        std::fill(std::begin(delayMix), std::end(delayMix), 0);
        std::fill(std::begin(delayProtection), std::end(delayProtection), 0);
        limiterGain = limiterTarget = 1; limiterHold = 0; noiseEnvelope = 0;
        rmsSquared = inputPower = referenceRMS = 0; quietFrames = 0;
        effect = {}; protection = {};
        RadioNoiseFlush(noiseGenerator);
        RadioInterferenceCancel(interference);
        interferencePhase = RadioInterferencePhaseIdle;
    }

    void controls() {
        const uint32_t packed = settings.load(std::memory_order_acquire);
        requestedEffect = float(std::min<uint32_t>(10, packed & 255));
        requestedBackground = std::min(requestedEffect, float((packed >> 8) & 255));
        effect.to(requestedEffect / 10, int64_t(0.2 * rate));
        uint32_t reset = resetSerial.load(std::memory_order_acquire);
        if (reset != seenReset) {
            seenReset = reset;
            trackEnd = activeFrames + remainingFrames.load(std::memory_order_relaxed);
        }
    }

    float limit(float left, float right) {
        detector[0][detectorCursor] = left; detector[1][detectorCursor] = right;
        float peak = std::max(std::abs(left), std::abs(right));
        for (unsigned c = 0; c < channels; ++c) {
            for (unsigned p = 0; p < 4; ++p) {
                float reconstructed = 0;
                for (unsigned k = 0; k < detectorTaps; ++k)
                    reconstructed += detector[c][(detectorCursor + detectorTaps - k) % detectorTaps] * interpolation[p][k];
                peak = std::max(peak, std::abs(reconstructed));
            }
        }
        detectorCursor = (detectorCursor + 1) % detectorTaps;
        float desired = peak > ceiling ? ceiling / peak : 1;
        if (desired < limiterTarget) {
            limiterTarget = desired;
            limiterHold = int(latency + detectorTaps);
        } else if (limiterHold > 0) --limiterHold;
        else limiterTarget += limiterRelease * (desired - limiterTarget);
        if (limiterTarget < limiterGain) {
            // Smooth gain changes ahead of the transient. An instantaneous
            // gain jump can itself create reconstruction overshoot at the output.
            limiterGain += 0.2f * (limiterTarget - limiterGain);
        }
        else limiterGain += limiterRelease * (limiterTarget - limiterGain);
        return limiterGain;
    }
};

RadioDSP *RadioDSPCreate(double rate, uint32_t channels, uint64_t seed) {
    if (!std::isfinite(rate) || rate < 8000 || rate > 384000 || channels < 1 || channels > 2) return nullptr;
    auto *dsp = new (std::nothrow) RadioDSP(rate, channels, seed);
    if (dsp && (!dsp->noiseGenerator || !dsp->interference)) { delete dsp; return nullptr; }
    return dsp;
}
void RadioDSPDestroy(RadioDSP *dsp) { delete dsp; }
uint32_t RadioDSPLatencyFrames() { return latency; }
bool RadioDSPSetReferenceSample(RadioDSP *d, const float *pcm, uint64_t frames) {
    if (!d) return false;
    auto *sample = RadioSampleCreate(d->rate, pcm, frames, d->sampleSeed);
    if (!sample) return false;
    const float rms = RadioSampleRMS(sample);
    if (!std::isfinite(rms) || rms <= 0) { RadioSampleDestroy(sample); return false; }
    RadioSampleDestroy(d->samplePlayer);
    d->samplePlayer = sample;
    RadioInterferenceSetNoiseRMS(d->interference, rms);
    return true;
}
bool RadioDSPHasReferenceSample(const RadioDSP *d) { return d && d->samplePlayer; }
void RadioDSPSetSettings(RadioDSP *dsp, int32_t effect, int32_t background) {
    effect = std::clamp(effect, 0, 10);
    background = std::clamp(background, 0, effect);
    if (dsp) dsp->settings.store(uint32_t(effect | (background << 8)), std::memory_order_release);
}
void RadioDSPSetTransport(RadioDSP *dsp, bool active) {
    if (!dsp) return;
    // The epoch preserves Stop even if Play follows before the next callback.
    // There is one control writer. Unsigned wrap is defined; an alias would
    // require 2^63 stops between renders. Play never changes the generation.
    uint64_t command = dsp->transportCommand.load(std::memory_order_relaxed);
    command = active ? command | uint64_t(1) : (command & ~uint64_t(1)) + 2;
    dsp->transportCommand.store(command, std::memory_order_release);
}
void RadioDSPResetReception(RadioDSP *dsp, double remaining) {
    if (!dsp) return;
    double bounded = std::isfinite(remaining) ? std::clamp(remaining, 0.0, 31536000.0) : 0;
    dsp->remainingFrames.store(int64_t(bounded * dsp->rate), std::memory_order_relaxed);
    dsp->resetSerial.fetch_add(1, std::memory_order_release);
}
int64_t RadioDSPRenderedSampleTime(const RadioDSP *dsp) { return dsp ? dsp->rendered.load(std::memory_order_acquire) : 0; }
RadioDSPPhase RadioDSPCurrentPhase(const RadioDSP *dsp) { return dsp ? RadioDSPPhase(dsp->phase.load(std::memory_order_acquire)) : RadioDSPPhaseBypassed; }
uint64_t RadioDSPInterferenceCount(const RadioDSP *dsp) { return dsp ? dsp->eventCount.load(std::memory_order_acquire) : 0; }
void RadioDSPSetSourceGate(RadioDSP *dsp, int64_t closeFrame) {
    if (dsp) dsp->sourceGateClose.store(closeFrame, std::memory_order_release);
}
bool RadioDSPProcessSourceGate(RadioDSP *dsp, float *left, float *right, uint32_t frames, int64_t sampleTime) {
    if (!dsp || !left) return true;
    int64_t boundary = dsp->sourceGateClose.load(std::memory_order_acquire);
    bool silent = true;
    for (uint32_t i = 0; i < frames; ++i) {
        if (sampleTime + i >= boundary) { left[i] = 0; if (right) right[i] = 0; }
        silent = silent && left[i] == 0 && (!right || right[i] == 0);
    }
    return silent;
}

bool RadioDSPProcess(RadioDSP *d, float *left, float *right, uint32_t frames, int64_t sampleTime) {
    if (!d || !left || (d->channels == 2 && !right)) return true;
    uint64_t transport = d->transportCommand.load(std::memory_order_acquire);
    uint64_t stop = transport >> 1;
    if (stop != d->seenStop) {
        d->seenStop = stop;
        d->clearHistory();
        d->wasActive = false;
    }
    d->controls();
    bool active = (transport & 1) != 0;
    if (!active) {
        std::fill(left, left + frames, 0);
        if (right) std::fill(right, right + frames, 0);
        if (d->wasActive) d->clearHistory();
        d->wasActive = false;
        d->phase.store(RadioDSPPhaseBypassed, std::memory_order_release);
        d->rendered.store(sampleTime + frames, std::memory_order_release);
        return true;
    }
    if (!d->wasActive) {
        RadioInterferenceCancel(d->interference);
        d->interferencePhase = RadioInterferencePhaseIdle;
        d->wasActive = true;
    }
    bool silent = true;
    RadioDSPPhase phase = RadioDSPPhaseBypassed;
    if (!d->samplePlayer) RadioNoiseBeginBlock(d->noiseGenerator);
    for (uint32_t i = 0; i < frames; ++i) {
        float e = d->effect.tick();
        float in[2] = {clean(left[i]), d->channels == 2 ? clean(right[i]) : clean(left[i])};
        // Stable dry transport is exactly its declared delay, without filtering,
        // metering, generated noise or limiting.
        if (e == 0 && d->noiseEnvelope < 0.0000001f) {
            for (unsigned c = 0; c < d->channels; ++c) {
                float dry = d->delayDry[c][d->cursor];
                float wet = d->delayWet[c][d->cursor] * (1 + d->delayProtection[d->cursor] * (d->limiterGain - 1));
                float out = d->delayMix[d->cursor] > 0 ? wet : dry;
                d->delayDry[c][d->cursor] = in[c]; d->delayWet[c][d->cursor] = in[c];
                if (c == 0) left[i] = out; else right[i] = out;
                silent = silent && out == 0;
            }
            d->delayMix[d->cursor] = 0; d->delayProtection[d->cursor] = 0;
            d->cursor = (d->cursor + 1) % latency;
            d->noiseEnvelope = 0; d->protection = {};
            if (d->interferencePhase != RadioInterferencePhaseIdle) {
                RadioInterferenceCancel(d->interference);
                d->interferencePhase = RadioInterferencePhaseIdle;
            }
            phase = RadioDSPPhaseBypassed;
            ++d->activeFrames;
            continue;
        }
        float working[2] = {std::clamp(in[0], -16.0f, 16.0f), std::clamp(in[1], -16.0f, 16.0f)};
        float power = (working[0] * working[0] + working[1] * working[1]) * 0.5f;
        d->rmsSquared += d->rmsAlpha * (std::min(power, 16.0f) - d->rmsSquared);
        d->inputPower += d->inputPowerAlpha * (std::min(power, 16.0f) - d->inputPower);
        if (d->inputPower < 0.000001f) ++d->quietFrames; else d->quietFrames = 0;
        if (d->interferencePhase == RadioInterferencePhaseIdle && d->inputPower >= 0.000001f
            && d->rmsSquared >= 0.000001f)
            d->referenceRMS = std::sqrt(d->rmsSquared);
        bool sourceAudible = d->quietFrames < int64_t(d->rate * 0.5);
        bool mayStart = sourceAudible
            && (d->trackEnd <= 0 || d->trackEnd - d->activeFrames > int64_t(2 * d->rate));
        // Run the texture continuously: the quiet bed remains between events,
        // and seed/timing do not depend on callback size.
        float texture = d->samplePlayer ? RadioSampleNextFrame(d->samplePlayer)
                                       : RadioNoiseNextFrame(d->noiseGenerator).left;
        const float noiseReference = d->requestedBackground > 0
            ? (d->referenceRMS > 0 ? d->referenceRMS : silentIntroReferenceRMS)
            : (sourceAudible ? d->referenceRMS : 0);
        auto absorption = RadioInterferenceNextFrame(d->interference, d->requestedEffect, d->requestedBackground,
            mayStart, texture, noiseReference);
        d->interferencePhase = absorption.phase;
        if (absorption.eventStarted) d->eventCount.fetch_add(1, std::memory_order_relaxed);
        float noise = absorption.noiseRatio * noiseReference;
        phase = e > 0 ? (absorption.phase != RadioInterferencePhaseIdle ? RadioDSPPhaseInterference : RadioDSPPhaseReceiving)
                      : RadioDSPPhaseBypassed;
        d->noiseEnvelope += d->smoothingAlpha * (noise - d->noiseEnvelope);
        float mix = e > 0 ? 1.0f : 0.0f;
        float wet[2] = {in[0], in[1]};
        if (mix > 0 || d->noiseEnvelope > 0.0000001f) {
            for (unsigned c = 0; c < d->channels; ++c) {
                wet[c] = working[c] * absorption.musicGain + absorption.noiseSample;
            }
        }
        // The detector sees the entire correlated dry/wet mixture. Limiting only
        // the wet branch would let low intensities exceed the peak ceiling.
        for (unsigned c = 0; c < d->channels; ++c) wet[c] = working[c] + mix * (wet[c] - working[c]);
        d->protection.to(d->effect.target > 0 ? 1.0f : 0.0f, int64_t(0.2 * d->rate));
        float engagement = d->protection.tick();
        float gain = d->limit(wet[0], d->channels == 2 ? wet[1] : wet[0]);
        float delayedMix = d->delayMix[d->cursor];
        for (unsigned c = 0; c < d->channels; ++c) {
            float dry = d->delayDry[c][d->cursor];
            float processed = d->delayWet[c][d->cursor] * (1 + d->delayProtection[d->cursor] * (gain - 1));
            float out = delayedMix > 0 ? processed : dry;
            d->delayDry[c][d->cursor] = in[c]; d->delayWet[c][d->cursor] = wet[c];
            if (c == 0) left[i] = out; else right[i] = out;
            silent = silent && out == 0;
        }
        d->delayMix[d->cursor] = mix;
        d->delayProtection[d->cursor] = engagement;
        d->cursor = (d->cursor + 1) % latency;
        ++d->activeFrames;
    }
    d->phase.store(phase, std::memory_order_release);
    d->rendered.store(sampleTime + frames, std::memory_order_release);
    return silent;
}
