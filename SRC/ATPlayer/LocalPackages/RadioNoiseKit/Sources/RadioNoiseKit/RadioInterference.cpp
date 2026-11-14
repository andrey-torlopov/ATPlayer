#include "RadioInterference.h"
#include <algorithm>
#include <cmath>
#include <new>

namespace {
float finite(float x) { return std::isfinite(x) ? x : 0; }
float smooth(float x) { x = std::clamp(x, 0.0f, 1.0f); return x * x * (3 - 2 * x); }
float noiseRatioForLevel(float level) {
    if (level <= 1) return 0.20f * level;
    if (level <= 2) return 0.20f + 0.10f * (level - 1);
    return 0.30f + 0.075f * (level - 2);
}
struct Random {
    uint64_t state;
    double unit() {
        uint64_t z = (state += 0x9e3779b97f4a7c15ULL);
        z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
        z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
        z ^= z >> 31;
        return (double(uint32_t(z >> 32)) + 0.5) / 4294967296.0;
    }
};
}

struct RadioInterferenceGenerator {
    const double rate;
    const float normalizationAlpha, referenceAlpha;
    Random random;
    RadioInterferencePhase phase = RadioInterferencePhaseIdle;
    int64_t remaining = 0, length = 1, hold = 1, release = 1;
    float intensity = 0, target = 0, intensityStep = 0;
    int64_t rampRemaining = 0;
    float background = 0, backgroundTarget = 0, backgroundStep = 0;
    int64_t backgroundRampRemaining = 0;
    // Seed a conservative RMS floor; continuous idle metering settles before
    // the first event. The floor prevents silence from acquiring unbounded gain.
    float noisePower = 0.0016f;
    float fixedNoiseRMS = 0;
    float musicReference = 0;
    bool zeroSettled = true;

    RadioInterferenceGenerator(double sr, uint64_t seed)
        : rate(sr), normalizationAlpha(float(1 - std::exp(-1 / (0.25 * sr)))),
          referenceAlpha(float(1 - std::exp(-1 / (0.004 * sr)))), random{seed} { cancel(); }
    int64_t duration(double low, double high) { return std::max<int64_t>(1, int64_t(rate * (low + (high - low) * random.unit()))); }
    void cancel() {
        phase = RadioInterferencePhaseIdle;
        remaining = duration(3, 6); length = 1;
    }
    RadioInterferenceFrame next(float requested, float requestedBackground, bool allow, float noise, float musicRMS) {
        requested = std::clamp(finite(requested), 0.0f, 10.0f);
        requestedBackground = std::clamp(finite(requestedBackground), 0.0f, 10.0f);
        if (requested != target) {
            target = requested;
            rampRemaining = std::max<int64_t>(1, int64_t(rate * 0.2));
            intensityStep = (target - intensity) / float(rampRemaining);
        }
        if (rampRemaining > 0) {
            intensity += intensityStep;
            if (--rampRemaining == 0) intensity = target;
        }
        if (requestedBackground != backgroundTarget) {
            backgroundTarget = requestedBackground;
            backgroundRampRemaining = std::max<int64_t>(1, int64_t(rate * 0.2));
            backgroundStep = (backgroundTarget - background) / float(backgroundRampRemaining);
        }
        if (backgroundRampRemaining > 0) {
            background += backgroundStep;
            if (--backgroundRampRemaining == 0) background = backgroundTarget;
        }
        if (target > 0 || backgroundTarget > 0) zeroSettled = false;
        else if (intensity == 0 && background == 0 && !zeroSettled) { cancel(); zeroSettled = true; }
        noise = std::clamp(finite(noise), -1.0f, 1.0f);
        noisePower += normalizationAlpha * (noise * noise - noisePower);
        bool started = false;
        if (phase == RadioInterferencePhaseIdle && allow && target > 0 && --remaining <= 0) {
            phase = RadioInterferencePhaseAttack;
            remaining = length = duration(0.35, 0.8);
            hold = duration(1, 6); release = duration(0.6, 1.2);
            started = true;
        }
        float envelope = 0;
        RadioInterferencePhase outputPhase = phase;
        if (phase == RadioInterferencePhaseAttack) envelope = smooth(float(length - remaining) / float(length));
        else if (phase == RadioInterferencePhaseHold) envelope = 1;
        else if (phase == RadioInterferencePhaseRelease) envelope = smooth(float(remaining) / float(length));
        if (phase != RadioInterferencePhaseIdle && --remaining <= 0) {
            if (phase == RadioInterferencePhaseAttack) { phase = RadioInterferencePhaseHold; remaining = length = hold; }
            else if (phase == RadioInterferencePhaseHold) { phase = RadioInterferencePhaseRelease; remaining = length = release; }
            else { phase = RadioInterferencePhaseIdle; remaining = duration(8, 18); }
        }
        // The full UI range now ends at the previously accepted level 7.
        const float effectiveIntensity = 0.7f * intensity;
        const float effectiveBackground = 0.7f * background;
        float loss;
        if (effectiveIntensity <= 1) loss = 0.15f * effectiveIntensity;
        else if (effectiveIntensity <= 2) loss = 0.15f + 0.05f * (effectiveIntensity - 1);
        else loss = 0.20f + 0.075f * (effectiveIntensity - 2);
        // Recorded bursts retain their crest factor and quiet gaps. The adaptive
        // procedural path intentionally keeps its previous ±3 safety bound.
        float normalized = fixedNoiseRMS > 0
            ? std::clamp(noise / fixedNoiseRMS, -32.0f, 32.0f)
            : std::clamp(noise / std::sqrt(std::max(0.0016f, noisePower)), -3.0f, 3.0f);
        // UI links the controls, but the render core also handles an incoherent
        // update without dropping event peaks below the selected background.
        const float bed = noiseRatioForLevel(effectiveBackground);
        const float peak = noiseRatioForLevel(std::max(effectiveIntensity, effectiveBackground));
        const float ratio = bed + (peak - bed) * envelope;
        float reference = std::clamp(finite(musicRMS), 0.0f, 4.0f);
        musicReference += referenceAlpha * (reference - musicReference);
        if (reference == 0 && musicReference < 0.0000001f) musicReference = 0;
        return {1 - loss * envelope, ratio, normalized * musicReference * ratio, normalized, envelope, outputPhase, started};
    }
};

RadioInterferenceGenerator *RadioInterferenceCreate(double rate, uint64_t seed) {
    if (!std::isfinite(rate) || rate < 8000 || rate > 384000) return nullptr;
    return new (std::nothrow) RadioInterferenceGenerator(rate, seed);
}
void RadioInterferenceDestroy(RadioInterferenceGenerator *g) { delete g; }
void RadioInterferenceReset(RadioInterferenceGenerator *g, uint64_t seed) {
    if (!g) return;
    g->random.state = seed;
    g->intensity = g->target = g->intensityStep = 0; g->rampRemaining = 0;
    g->background = g->backgroundTarget = g->backgroundStep = 0; g->backgroundRampRemaining = 0;
    g->noisePower = 0.0016f; g->musicReference = 0; g->zeroSettled = true; g->cancel();
}
void RadioInterferenceCancel(RadioInterferenceGenerator *g) {
    if (!g) return;
    g->cancel();
    // Transport stop/start must not replay the previous source's 4 ms tail.
    g->musicReference = 0;
}
void RadioInterferenceSetNoiseRMS(RadioInterferenceGenerator *g, float rms) {
    if (g) g->fixedNoiseRMS = std::isfinite(rms) && rms > 0 ? std::clamp(rms, 0.0001f, 1.0f) : 0;
}
RadioInterferenceFrame RadioInterferenceNextFrame(RadioInterferenceGenerator *g, float intensity, float backgroundIntensity,
                                                  bool allow, float noise, float musicRMS) {
    return g ? g->next(intensity, backgroundIntensity, allow, noise, musicRMS)
             : RadioInterferenceFrame{1, 0, 0, 0, 0, RadioInterferencePhaseIdle, false};
}
