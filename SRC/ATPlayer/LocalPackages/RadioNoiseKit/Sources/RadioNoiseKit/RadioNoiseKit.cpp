#include "RadioNoiseKit.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstring>
#include <new>

namespace {
constexpr double pi = 3.14159265358979323846;
constexpr size_t parameterCount = 7;
static_assert(std::atomic<uint64_t>::is_always_lock_free, "Realtime snapshots require lock-free atomics");
static_assert(std::atomic<uint32_t>::is_always_lock_free, "Realtime snapshots require lock-free atomics");
float bounded(float x) { return std::isfinite(x) ? std::clamp(x, 0.0f, 1.0f) : 0; }
float smooth(float x) { x = std::clamp(x, 0.0f, 1.0f); return x * x * (3 - 2 * x); }
uint32_t bits(float x) { uint32_t value; std::memcpy(&value, &x, sizeof(value)); return value; }
float number(uint32_t x) { float value; std::memcpy(&value, &x, sizeof(value)); return value; }

struct Random {
    uint64_t state = 0;
    uint64_t next() {
        uint64_t z = (state += 0x9e3779b97f4a7c15ULL);
        z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
        z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
        return z ^ (z >> 31);
    }
    double unit() { return (double(uint32_t(next() >> 32)) + 0.5) / 4294967296.0; }
    float bipolar() { return float(unit() * 2 - 1); }
    double between(double a, double b) { return a + (b - a) * unit(); }
};

struct Ramp {
    float value = 0, target = 0, step = 0;
    uint32_t remaining = 0;
    void set(float next, uint32_t frames) {
        if (next == target) return;
        target = next; remaining = std::max<uint32_t>(1, frames);
        step = (target - value) / float(remaining);
    }
    float tick() {
        if (remaining && --remaining == 0) value = target;
        else if (remaining) value += step;
        return value;
    }
};

struct LowPass {
    float value = 0;
    float tick(float input, float coefficient) { value += coefficient * (input - value); return value; }
};

// Stable damped second-order modes; coefficients are fixed while a mode rings.
struct Resonator {
    float z1 = 0, z2 = 0, a1 = 0, a2 = 0, inputScale = 1;
    void configure(double rate, double frequency, double decaySeconds, bool noiseExcitation = false) {
        double r = std::exp(-1 / (std::max(0.001, decaySeconds) * rate));
        double w = 2 * pi * std::clamp(frequency, 20.0, rate * 0.43) / rate;
        a1 = float(2 * r * std::cos(w)); a2 = float(-r * r);
        double referenceR = std::exp(-1 / (std::max(0.001, decaySeconds) * 48000));
        double referenceA1 = 2 * referenceR * std::cos(2 * pi * frequency / 48000);
        // Preserve either the white-noise variance or low-frequency excitation
        // gain when the host sample rate changes. These are computed off render.
        auto variance = [](double radius, double coefficient) {
            double square = radius * radius;
            return (1 + square) / ((1 - square) * ((1 + square) * (1 + square) - coefficient * coefficient));
        };
        inputScale = noiseExcitation
            ? float(std::sqrt(variance(referenceR, referenceA1) / variance(r, 2 * r * std::cos(w))))
            : float((1 - 2 * r * std::cos(w) + r * r) / (1 - referenceA1 + referenceR * referenceR));
    }
    float tick(float input) {
        float output = input * inputScale + a1 * z1 + a2 * z2;
        z2 = z1; z1 = std::abs(output) < 1e-20f ? 0 : output;
        return z1;
    }
    void clear() { z1 = z2 = 0; }
};

struct Click {
    float attack = 0, decay = 0, attackStep = 0, decayStep = 0, amplitude = 0;
    void start(double rate, Random &random, float character) {
        attack = decay = 1;
        amplitude = random.bipolar() * float(random.between(0.3, 1.0));
        // Sparse large impulses create the crest of old receiver crackle;
        // most clicks remain small. No recorded transient is replayed.
        amplitude *= random.unit() < 0.08 ? 3.5f : 0.75f;
        attackStep = float(std::exp(-1 / (rate * random.between(0.00012, 0.0007))));
        decayStep = float(std::exp(-1 / (rate * random.between(0.002, 0.012 + character * 0.01))));
    }
    float tick() {
        if (decay < 0.00001f) return 0;
        attack *= attackStep; decay *= decayStep;
        return amplitude * (decay - attack);
    }
};

struct Packet {
    int64_t length = 0, age = 0, attack = 1;
    float amplitude = 0;
    void start(double rate, Random &random, double minimum, double maximum, double attackSeconds) {
        length = std::max<int64_t>(2, int64_t(rate * random.between(minimum, maximum)));
        age = 0; attack = std::max<int64_t>(1, std::min(length / 3, int64_t(rate * attackSeconds)));
        amplitude = float(random.between(0.4, 1.0));
    }
    float tick() {
        if (age >= length) return 0;
        float entry = smooth(float(age) / float(attack));
        float tail = 1 - smooth(float(std::max<int64_t>(0, age - attack)) / float(std::max<int64_t>(1, length - attack)));
        ++age;
        return amplitude * entry * tail;
    }
    void clear() { length = age = 0; }
};

// Random control points with a smooth connection, not a replayed envelope.
// The same seeded curve can be made shallow or deep by the character control.
struct Wander {
    int64_t age = 0, length = 0;
    float start = 0.5f, target = 0.5f;
    float tick(double rate, Random &random, double minimum, double maximum) {
        if (age >= length) {
            start = target;
            target = float(random.unit());
            length = std::max<int64_t>(1, int64_t(rate * random.between(minimum, maximum)));
            age = 0;
        }
        return start + (target - start) * smooth(float(age++) / float(length));
    }
};

struct ParameterMailbox {
    std::atomic<uint64_t> sequence{0};
    std::array<std::atomic<uint32_t>, parameterCount> values{};
    void write(RadioNoiseParameters p) {
        const float next[parameterCount] = {p.masterLevel, p.character, p.hissLevel, p.crackleLevel,
                                            p.resonanceLevel, p.chatterLevel, p.squelchLevel};
        sequence.fetch_add(1, std::memory_order_acq_rel);
        std::atomic_thread_fence(std::memory_order_release);
        for (size_t i = 0; i < parameterCount; ++i) values[i].store(bits(bounded(next[i])), std::memory_order_relaxed);
        sequence.fetch_add(1, std::memory_order_release);
    }
    bool read(std::array<float, parameterCount> &out, uint64_t &last) const {
        uint64_t before = sequence.load(std::memory_order_acquire);
        if (before == last || (before & 1)) return false;
        std::array<float, parameterCount> next;
        for (size_t i = 0; i < parameterCount; ++i) next[i] = number(values[i].load(std::memory_order_relaxed));
        std::atomic_thread_fence(std::memory_order_acquire);
        if (before != sequence.load(std::memory_order_acquire)) return false;
        out = next; last = before; return true;
    }
};
}

struct RadioNoiseGenerator {
    const double rate;
    const uint32_t channels, rampFrames;
    ParameterMailbox parameters;
    std::atomic<uint64_t> resetSequence{0}, resetSeed{0};
    uint64_t parameterSerial = 0, resetSerial = 0;
    std::array<float, parameterCount> desired{};
    std::array<Ramp, parameterCount> ramps{};
    Random bedRandom, crackleRandom, ringingRandom, chatterRandom, squelchRandom, textureRandom;
    std::array<Click, 8> clicks{};
    std::array<Resonator, 3> retroModes{}, squelchModes{};
    std::array<Resonator, 4> ringingModes{};
    Packet ringingPacket, chatterPacket, squelchPacket, squelchCluster;
    Wander retroWander, squelchWander;
    LowPass lowRetro1, lowRetro2, retroDC, retroOutputDC, retroOutputDC2, hissLow1, hissLow2, hissDC;
    LowPass ringingLow1, ringingLow2, ringingDC;
    LowPass chatterLow, chatterLow2, chatterDC, squelchLow, squelchLow2, squelchDC, squelchDC2, activityFilter;
    std::array<LowPass, 4> squelchHighPass{};
    std::array<LowPass, 2> squelchBandLimit{};
    int64_t frame = 0, nextCrackle = 0, crackleClusterEnd = 0;
    int64_t nextRing = 0, nextChatter = 0, chatterClusterEnd = 0, nextSquelch = 0, nextSquelchCluster = 0;
    float lastActivity = 0;
    const float noiseRateScale, retroAlpha, retroDCAlpha, retroOutputDCAlpha, hissAlpha, hissDCAlpha;
    const float chatterAlpha, chatterDCAlpha, squelchAlpha, squelchDCAlpha, activityAlpha;
    const float ringingAlpha, ringingDCAlpha;
    const float squelchHighPassAlpha, squelchBandLimitAlpha;

    float coefficient(double hz) const { return float(1 - std::exp(-2 * pi * std::min(hz, rate * 0.43) / rate)); }
    int64_t frames(double seconds) const { return std::max<int64_t>(1, int64_t(rate * seconds)); }
    RadioNoiseGenerator(double sr, uint32_t ch, uint64_t seed)
        : rate(sr), channels(ch), rampFrames(uint32_t(std::max(1.0, sr * 0.05))),
          noiseRateScale(float(std::sqrt(sr / 48000))),
          retroAlpha(coefficient(350)), retroDCAlpha(coefficient(45)), retroOutputDCAlpha(coefficient(90)),
          hissAlpha(coefficient(2600)), hissDCAlpha(coefficient(450)),
          chatterAlpha(coefficient(2700)), chatterDCAlpha(coefficient(220)),
          squelchAlpha(coefficient(2200)), squelchDCAlpha(coefficient(450)), activityAlpha(coefficient(40)),
          ringingAlpha(coefficient(10000)), ringingDCAlpha(coefficient(3000)),
          squelchHighPassAlpha(coefficient(350)), squelchBandLimitAlpha(coefficient(5500)) {
        const double retroFrequencies[3] = {100, 200, 300};
        const double ringFrequencies[4] = {2400, 4400, 8700, 11000};
        const double squelchFrequencies[3] = {700, 2390, 4610};
        for (size_t i = 0; i < 3; ++i) {
            retroModes[i].configure(rate, retroFrequencies[i], 0.018);
            const double squelchDecays[3] = {0.002, 0.008, 0.014};
            squelchModes[i].configure(rate, squelchFrequencies[i], squelchDecays[i], true);
        }
        for (size_t i = 0; i < 4; ++i) ringingModes[i].configure(rate, ringFrequencies[i], 0.025, true);
        parameters.write(RadioNoiseDefaultParameters());
        reseed(seed);
    }

    void reseed(uint64_t seed) {
        bedRandom.state = seed ^ 0x243f6a8885a308d3ULL;
        crackleRandom.state = seed ^ 0x13198a2e03707344ULL;
        ringingRandom.state = seed ^ 0xa4093822299f31d0ULL;
        chatterRandom.state = seed ^ 0x082efa98ec4e6c89ULL;
        squelchRandom.state = seed ^ 0x452821e638d01377ULL;
        textureRandom.state = seed ^ 0xbe5466cf34e90c6cULL;
        flush();
        for (auto &ramp : ramps) ramp = {};
        parameterSerial = 0;
    }

    void flush() {
        frame = nextCrackle = nextRing = nextChatter = nextSquelch = nextSquelchCluster = 0;
        crackleClusterEnd = chatterClusterEnd = 0;
        clicks = {};
        lowRetro1 = {}; lowRetro2 = {}; retroDC = {}; retroOutputDC = {}; retroOutputDC2 = {};
        hissLow1 = {}; hissLow2 = {}; hissDC = {};
        ringingLow1 = {}; ringingLow2 = {}; ringingDC = {};
        chatterLow = {}; chatterLow2 = {}; chatterDC = {}; squelchLow = {}; squelchLow2 = {}; squelchDC = {}; squelchDC2 = {}; activityFilter = {};
        squelchHighPass = {}; squelchBandLimit = {};
        ringingPacket.clear(); chatterPacket.clear(); squelchPacket.clear(); squelchCluster.clear();
        retroWander = {}; squelchWander = {}; lastActivity = 0;
        for (auto &mode : retroModes) mode.clear();
        for (auto &mode : ringingModes) mode.clear();
        for (auto &mode : squelchModes) mode.clear();
    }

    void beginBlock() {
        uint64_t before = resetSequence.load(std::memory_order_acquire);
        if (!(before & 1) && before != resetSerial) {
            uint64_t seed = resetSeed.load(std::memory_order_relaxed);
            std::atomic_thread_fence(std::memory_order_acquire);
            if (before == resetSequence.load(std::memory_order_acquire)) { reseed(seed); resetSerial = before; }
        }
        if (parameters.read(desired, parameterSerial))
            for (size_t i = 0; i < parameterCount; ++i) ramps[i].set(desired[i], rampFrames);
    }

    RadioNoiseFrame next() {
        std::array<float, parameterCount> p;
        for (size_t i = 0; i < parameterCount; ++i) p[i] = ramps[i].tick();
        if (p[0] == 0) return {};
        float character = p[1];
        float white = bedRandom.bipolar() * noiseRateScale;
        float hiss = hissLow2.tick(hissLow1.tick(white, hissAlpha), hissAlpha);
        hiss -= hissDC.tick(hiss, hissDCAlpha);
        float rumble = lowRetro2.tick(lowRetro1.tick(white, retroAlpha), retroAlpha);
        rumble -= retroDC.tick(rumble, retroDCAlpha);

        if (frame >= nextCrackle) {
            if (frame >= crackleClusterEnd) crackleClusterEnd = frame + frames(crackleRandom.between(0.06, 0.65));
            auto quietest = clicks.begin();
            for (auto it = clicks.begin(); it != clicks.end(); ++it)
                if (std::abs(it->amplitude * it->decay) < std::abs(quietest->amplitude * quietest->decay)) quietest = it;
            quietest->start(rate, crackleRandom, character);
            double interval = crackleRandom.between(0.008, 0.05) / (0.6 + character);
            if (frame + frames(interval) >= crackleClusterEnd)
                interval += crackleRandom.between(0.07, 0.7) / (0.5 + character);
            nextCrackle = frame + frames(interval);
        }
        float crackle = 0;
        for (auto &click : clicks) crackle += click.tick();
        float retro = rumble * 2.5f;
        float excitation = (crackle + white * 0.015f) * 0.0012f;
        for (auto &mode : retroModes) retro += mode.tick(excitation) * 0.06f;
        retro += crackle * 0.25f;
        retro -= retroOutputDC.tick(retro, retroOutputDCAlpha);
        retro -= retroOutputDC2.tick(retro, retroOutputDCAlpha) * (0.2f + 0.8f * character);
        retro += hiss * 0.18f;
        float retroMotion = retroWander.tick(rate, textureRandom, 0.25, 1.8);
        float retroFloor = 0.48f - 0.46f * character;
        // 07 has deep irregular fades; 08 remains a denser continuous texture.
        float retroEnvelope = retroFloor + (1 - retroFloor) * retroMotion * retroMotion;
        retro *= retroEnvelope;

        if (frame >= nextRing) {
            ringingPacket.start(rate, ringingRandom, 0.015, 0.16, 0.0008);
            // Modes retain their coefficients until flush. Excitation varies,
            // but no active resonator is retuned or cleared between packets.
            nextRing = frame + ringingPacket.length + frames(ringingRandom.between(0.015, 0.18) / (0.5 + character));
        }
        float ringEnvelope = ringingPacket.tick();
        float ringNoise = ringingRandom.bipolar() * ringEnvelope;
        float ringing = 0;
        const float ringingDrive[4] = {0.004f, 0.006f, 0.014f, 0.014f};
        for (size_t i = 0; i < 4; ++i) ringing += ringingModes[i].tick(ringNoise * ringingDrive[i]);
        float ringingBed = ringingLow2.tick(ringingLow1.tick(ringNoise * noiseRateScale, ringingAlpha), ringingAlpha);
        ringing += (ringingBed - ringingDC.tick(ringingBed, ringingDCAlpha)) * 0.25f;

        if (frame >= nextChatter) {
            if (frame >= chatterClusterEnd) chatterClusterEnd = frame + frames(chatterRandom.between(0.12, 1.1));
            chatterPacket.start(rate, chatterRandom, 0.008, 0.035, 0.0007);
            double interval = chatterRandom.between(0.025, 0.063);
            if (frame + frames(interval) >= chatterClusterEnd) interval += chatterRandom.between(0.1, 1.2);
            nextChatter = frame + std::max(chatterPacket.length, frames(interval / (0.8 + 0.4 * character)));
        }
        float chatterEnvelope = chatterPacket.tick();
        float chatter = chatterLow2.tick(chatterLow.tick(chatterRandom.bipolar() * noiseRateScale, chatterAlpha), chatterAlpha);
        chatter = (chatter - chatterDC.tick(chatter, chatterDCAlpha)) * chatterEnvelope * 1.8f;

        if (frame >= nextSquelchCluster) {
            squelchCluster.start(rate, squelchRandom, 0.8, 3.8, 0.018);
            nextSquelchCluster = frame + squelchCluster.length + frames(squelchRandom.between(3.0, 12.0));
        }
        float squelchGroup = squelchCluster.tick();
        if (frame >= nextSquelch) {
            squelchPacket.start(rate, squelchRandom, 0.025, 0.28, 0.0012);
            double interval = squelchGroup > 0.05f ? squelchRandom.between(0.015, 0.12) : squelchRandom.between(0.3, 1.9);
            nextSquelch = frame + squelchPacket.length + frames(interval / (0.6 + character));
        }
        float squelchMotion = squelchWander.tick(rate, textureRandom, 0.3, 1.2);
        // Reference12 contains a persistent narrow-band bed, with short bursts
        // gathered into longer active regions. Avoid isolated hiss puffs.
        float squelchEnvelope = 0.18f + 0.12f * squelchMotion + 0.45f * squelchGroup
                                + squelchPacket.tick() * (0.18f + 0.9f * squelchGroup);
        float squelchWhite = squelchRandom.bipolar();
        float squelch = squelchLow2.tick(squelchLow.tick(squelchWhite * noiseRateScale, squelchAlpha), squelchAlpha);
        squelch -= squelchDC.tick(squelch, squelchDCAlpha);
        squelch -= squelchDC2.tick(squelch, squelchDCAlpha);
        squelch *= squelchEnvelope * 0.8f;
        const float squelchDrive[3] = {0.0145f, 0.00925f, 0.0208f};
        for (size_t i = 0; i < 3; ++i) squelch += squelchModes[i].tick(squelchWhite * squelchEnvelope * squelchDrive[i]);
        // Remove receiver-external sub-bass and ultrasonic skirts before mixing.
        for (auto &filter : squelchHighPass) squelch -= filter.tick(squelch, squelchHighPassAlpha);
        for (auto &filter : squelchBandLimit) squelch = filter.tick(squelch, squelchBandLimitAlpha);

        float mixed = p[2] * hiss * 1.6f + p[3] * retro + p[4] * ringing + p[5] * chatter + p[6] * squelch;
        float output = mixed / (1 + std::abs(mixed));
        float activity = std::clamp(p[3] * std::abs(crackle) + p[4] * ringEnvelope
                                    + p[5] * chatterEnvelope + p[6] * squelchEnvelope, 0.0f, 1.0f);
        lastActivity = activityFilter.tick(activity, activityAlpha);
        ++frame;
        // References are predominantly mono. Music's stereo image belongs to the host.
        float sample = p[0] * output;
        return {sample, sample, lastActivity * p[0]};
    }
};

RadioNoiseParameters RadioNoiseDefaultParameters() { return RadioNoiseParametersForPreset(RadioNoisePresetBlended); }
RadioNoiseParameters RadioNoiseParametersForPreset(RadioNoisePreset preset) {
    switch (preset) {
    case RadioNoisePresetRetro: return {0.2f, 0.95f, 0.005f, 1, 0, 0.01f, 0};
    case RadioNoisePresetRetro08: return {0.2f, 0.35f, 0.02f, 1, 0, 0.025f, 0};
    case RadioNoisePresetRinging: return {0.2f, 0.7f, 0.02f, 0, 1, 0, 0};
    case RadioNoisePresetFadingBursts: return {0.2f, 0.7f, 0.03f, 0.08f, 0, 1, 0.15f};
    case RadioNoisePresetSquelch: return {0.2f, 0.7f, 0, 0, 0, 0, 1};
    default: return {0.2f, 0.7f, 0.16f, 0.85f, 0.10f, 0.24f, 0.24f};
    }
}
RadioNoiseGenerator *RadioNoiseCreate(double rate, uint32_t channels, uint64_t seed) {
    if (!std::isfinite(rate) || rate < 8000 || rate > 384000 || channels < 1 || channels > 2) return nullptr;
    return new (std::nothrow) RadioNoiseGenerator(rate, channels, seed);
}
void RadioNoiseDestroy(RadioNoiseGenerator *g) { delete g; }
void RadioNoiseSetParameters(RadioNoiseGenerator *g, RadioNoiseParameters p) { if (g) g->parameters.write(p); }
void RadioNoiseReset(RadioNoiseGenerator *g, uint64_t seed) {
    if (!g) return;
    g->resetSequence.fetch_add(1, std::memory_order_acq_rel);
    std::atomic_thread_fence(std::memory_order_release);
    g->resetSeed.store(seed, std::memory_order_relaxed);
    g->resetSequence.fetch_add(1, std::memory_order_release);
}
void RadioNoiseBeginBlock(RadioNoiseGenerator *g) { if (g) g->beginBlock(); }
RadioNoiseFrame RadioNoiseNextFrame(RadioNoiseGenerator *g) { return g ? g->next() : RadioNoiseFrame{}; }
void RadioNoiseFlush(RadioNoiseGenerator *g) { if (g) g->flush(); }
void RadioNoiseRender(RadioNoiseGenerator *g, float *left, float *right, uint32_t frames) {
    if (!g || !left || (g->channels == 2 && !right)) return;
    g->beginBlock();
    for (uint32_t i = 0; i < frames; ++i) {
        auto sample = g->next();
        left[i] = sample.left;
        if (right) right[i] = sample.right;
    }
}
