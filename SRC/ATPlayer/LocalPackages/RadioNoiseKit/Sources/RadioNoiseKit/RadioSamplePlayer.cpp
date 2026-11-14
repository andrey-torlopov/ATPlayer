#include "RadioSamplePlayer.h"
#include <algorithm>
#include <cmath>
#include <limits>
#include <memory>
#include <new>
#include <utility>

namespace {
constexpr double pi = 3.14159265358979323846;
struct Random {
    uint64_t state;
    uint64_t next() {
        uint64_t value = (state += 0x9e3779b97f4a7c15ULL);
        value = (value ^ (value >> 30)) * 0xbf58476d1ce4e5b9ULL;
        value = (value ^ (value >> 27)) * 0x94d049bb133111ebULL;
        return value ^ (value >> 31);
    }
};
}

struct RadioSamplePlayer {
    const uint64_t count;
    const uint64_t fadeFrames;
    const float rms;
    std::unique_ptr<float[]> samples;
    std::unique_ptr<float[]> fadeWeights;
    Random random;
    uint64_t position = 0;
    uint64_t incoming = 0;

    RadioSamplePlayer(uint64_t frameCount, uint64_t fadeLength, float sourceRMS,
                      std::unique_ptr<float[]> pcm, std::unique_ptr<float[]> weights, uint64_t seed)
        : count(frameCount), fadeFrames(fadeLength), rms(sourceRMS),
          samples(std::move(pcm)), fadeWeights(std::move(weights)), random{seed} {
        reset(seed);
    }

    uint64_t offset() { return random.next() % (count / 4 + 1); }
    void reset(uint64_t seed) {
        random.state = seed;
        position = offset();
        incoming = offset();
    }
    float next() {
        float output = samples[position];
        const uint64_t fadeStart = count - fadeFrames;
        if (position >= fadeStart) {
            const uint64_t fadePosition = position - fadeStart;
            const float weight = fadeWeights[fadePosition];
            output = output * (1 - weight) + samples[incoming + fadePosition] * weight;
        }
        if (++position == count) {
            position = incoming + fadeFrames;
            incoming = offset();
        }
        return output;
    }
};

RadioSamplePlayer *RadioSampleCreate(double sampleRate, const float *monoPCM,
                                    uint64_t frameCount, uint64_t seed) {
    if (!std::isfinite(sampleRate) || sampleRate < 8000 || sampleRate > 384000 || !monoPCM
        || frameCount < 8 || frameCount > std::numeric_limits<size_t>::max() / sizeof(float)) return nullptr;
    auto pcm = std::unique_ptr<float[]>(new (std::nothrow) float[size_t(frameCount)]);
    if (!pcm) return nullptr;
    double power = 0;
    for (uint64_t i = 0; i < frameCount; ++i) {
        const float sample = monoPCM[i];
        if (!std::isfinite(sample) || std::abs(sample) > 1) return nullptr;
        pcm[i] = sample;
        power += double(sample) * double(sample);
    }
    const auto fadeFrames = std::max<uint64_t>(1, std::min<uint64_t>(uint64_t(sampleRate * 0.05), frameCount / 8));
    auto weights = std::unique_ptr<float[]>(new (std::nothrow) float[size_t(fadeFrames)]);
    if (!weights) return nullptr;
    for (uint64_t i = 0; i < fadeFrames; ++i) {
        // For one-frame fixtures choose the incoming frame, so the boundary
        // remains a normal adjacent source step. Production WAV fades span 50 ms.
        weights[i] = fadeFrames == 1 ? 1 : float(0.5 - 0.5 * std::cos(pi * double(i) / double(fadeFrames - 1)));
    }
    return new (std::nothrow) RadioSamplePlayer(frameCount, fadeFrames,
        float(std::sqrt(power / double(frameCount))), std::move(pcm), std::move(weights), seed);
}

void RadioSampleDestroy(RadioSamplePlayer *player) { delete player; }
float RadioSampleRMS(const RadioSamplePlayer *player) { return player ? player->rms : 0; }
float RadioSampleNextFrame(RadioSamplePlayer *player) { return player ? player->next() : 0; }
void RadioSampleRender(RadioSamplePlayer *player, float *mono, uint32_t frames) {
    if (!player || !mono) return;
    for (uint32_t i = 0; i < frames; ++i) mono[i] = player->next();
}
void RadioSampleReset(RadioSamplePlayer *player, uint64_t seed) { if (player) player->reset(seed); }
