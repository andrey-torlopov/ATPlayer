// Original synthesized music; optional user-supplied recording for radio texture.
// Build explicitly when authorized:
// clang++ -std=c++17 -O2 -I Sources/RadioDSP/include \
//   -I ../RadioNoiseKit/Sources/RadioNoiseKit/include Sources/RadioDSP/RadioDSP.cpp \
//   ../RadioNoiseKit/Sources/RadioNoiseKit/RadioNoiseKit.cpp \
//   ../RadioNoiseKit/Sources/RadioNoiseKit/RadioInterference.cpp \
//   ../RadioNoiseKit/Sources/RadioNoiseKit/RadioSamplePlayer.cpp Tools/render_radio_prototype.cpp \
//   -o /tmp/atplayer-radio-render
// Run: /tmp/atplayer-radio-render /absolute/output/directory --reference-pcm /path/to/mono-48k.f32
#include "RadioDSP.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr int rate = 48000;
constexpr int frames = 60 * rate;
constexpr double pi = 3.14159265358979323846;

std::vector<float> readReference(const std::filesystem::path &path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) throw std::runtime_error("Cannot open mono Float32 48 kHz reference");
    const auto bytes = file.tellg();
    if (bytes <= 0 || bytes > std::streamoff(rate * 600 * sizeof(float)) ||
        bytes % std::streamoff(sizeof(float)) != 0)
        throw std::runtime_error("Invalid reference length (maximum 10 minutes)");
    std::vector<float> pcm(size_t(bytes) / sizeof(float));
    file.seekg(0);
    if (!file.read(reinterpret_cast<char *>(pcm.data()), bytes))
        throw std::runtime_error("Incomplete reference read");
    for (float sample : pcm)
        if (!std::isfinite(sample)) throw std::runtime_error("Non-finite reference PCM");
    return pcm;
}

RadioDSP *createDSP(uint64_t seed, const std::vector<float> &reference) {
    RadioDSP *dsp = RadioDSPCreate(rate, 2, seed);
    if (!dsp) throw std::runtime_error("DSP allocation failed");
    if (!reference.empty() && !RadioDSPSetReferenceSample(dsp, reference.data(), reference.size())) {
        RadioDSPDestroy(dsp);
        throw std::runtime_error("Reference sample setup failed");
    }
    return dsp;
}

void integer(std::ofstream &file, uint32_t value, int bytes) {
    for (int i = 0; i < bytes; ++i) file.put(char((value >> (8 * i)) & 255));
}

void writeWAV(const std::filesystem::path &path, const std::vector<float> &left, const std::vector<float> &right) {
    std::ofstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("Cannot open render output");
    uint32_t size = uint32_t(left.size() * 2 * sizeof(float));
    file.write("RIFF", 4); integer(file, size + 36, 4); file.write("WAVEfmt ", 8);
    integer(file, 16, 4); integer(file, 3, 2); integer(file, 2, 2);
    integer(file, rate, 4); integer(file, rate * 8, 4); integer(file, 8, 2); integer(file, 32, 2);
    file.write("data", 4); integer(file, size, 4);
    for (size_t i = 0; i < left.size(); ++i) {
        file.write(reinterpret_cast<const char *>(&left[i]), sizeof(float));
        file.write(reinterpret_cast<const char *>(&right[i]), sizeof(float));
    }
}

std::array<float, 2> music(int frame) {
    double t = double(frame) / rate;
    // A self-contained tone study with a quiet introduction, transient-rich plucks,
    // stereo fundamentals and a long fade; not a listening substitute for real music.
    double envelope = std::min(1.0, t / 3) * std::clamp((60 - t) / 8, 0.0, 1.0);
    double noteAge = std::fmod(t, 0.75);
    double pluck = std::exp(-noteAge * 5);
    double fundamental = 110 * std::pow(2.0, double(int(t / 3) % 5) / 12);
    double mono = 0.18 * std::sin(2 * pi * fundamental * t)
                + pluck * 0.1 * std::sin(2 * pi * 3 * fundamental * t)
                + pluck * 0.04 * std::sin(2 * pi * 9 * fundamental * t);
    return {float(envelope * (mono + 0.06 * std::sin(2 * pi * 1.5 * fundamental * t))),
            float(envelope * (mono + 0.06 * std::sin(2 * pi * 2.5 * fundamental * t)))};
}

void render(const std::filesystem::path &directory, const std::string &name, int effect, int background, bool overlay,
            const std::vector<float> &reference) {
    RadioDSP *dsp = createDSP(20261114, reference);
    RadioDSPSetSettings(dsp, effect, background);
    RadioDSPSetTransport(dsp, true);
    RadioDSPResetReception(dsp, 60);
    std::vector<float> left(frames), right(frames);
    uint64_t random = 31;
    for (int i = 0; i < frames; ++i) {
        auto input = music(i);
        left[i] = input[0]; right[i] = input[1];
        if (overlay) {
            random = random * 6364136223846793005ULL + 1;
            float noise = (float(uint32_t(random >> 32)) / 4294967296.0f - 0.5f) * 0.012f;
            left[i] += noise; right[i] += noise;
        }
    }
    for (int start = 0; start < frames; start += 256) {
        uint32_t count = uint32_t(std::min(256, frames - start));
        RadioDSPProcess(dsp, left.data() + start, right.data() + start, count, start);
    }
    double squared = 0;
    float peak = 0;
    for (int i = 0; i < frames; ++i) {
        if (!std::isfinite(left[i]) || !std::isfinite(right[i])) throw std::runtime_error("Non-finite output");
        squared += double(left[i]) * left[i] + double(right[i]) * right[i];
        peak = std::max({peak, std::abs(left[i]), std::abs(right[i])});
    }
    writeWAV(directory / (name + ".wav"), left, right);
    std::cout << name << ": samplePeak=" << peak << "; RMS=sqrt(" << squared << " / " << frames * 2
              << ")=" << std::sqrt(squared / (frames * 2)) << "; events=" << RadioDSPInterferenceCount(dsp) << '\n';
    RadioDSPDestroy(dsp);
}

void renderStress(const std::filesystem::path &directory, int level, int background, const std::vector<float> &reference) {
    RadioDSP *dsp = createDSP(31, reference);
    RadioDSPSetSettings(dsp, level, background);
    RadioDSPSetTransport(dsp, true);
    RadioDSPResetReception(dsp, 12);
    std::vector<float> left(12 * rate), right(12 * rate);
    for (int i = rate / 2; i < int(left.size()); ++i) {
        double t = double(i) / rate;
        float value;
        if (t < 3) value = float(1.8 * std::sin(2 * pi * (100 * t + 3800 * t * t)));
        else if (t < 5) value = float(1.8 * std::sin(2 * pi * 12000 * t + pi / 4));
        else if (t < 7) value = (i % 193 < 96 ? 1.8f : -1.8f);
        else if (t < 10) value = float(1.8 * std::sin(2 * pi * 997 * t));
        else value = i % 31 == 0 ? 3.0f : 0;
        left[i] = value; right[i] = -value;
    }
    for (int start = 0; start < int(left.size()); start += 127) {
        uint32_t count = uint32_t(std::min(127, int(left.size()) - start));
        RadioDSPProcess(dsp, left.data() + start, right.data() + start, count, start);
    }
    for (size_t i = 0; i < left.size(); ++i)
        if (!std::isfinite(left[i]) || !std::isfinite(right[i])) throw std::runtime_error("Non-finite stress output");
    writeWAV(directory / ("stress-" + std::to_string(level) + ".wav"), left, right);
    RadioDSPDestroy(dsp);
}

void renderIsolatedTexture(const std::filesystem::path &directory, int level, int background, const std::vector<float> &reference) {
    auto *dsp = createDSP(20261114, reference);
    RadioDSPSetSettings(dsp, level, background);
    RadioDSPSetTransport(dsp, true);
    RadioDSPResetReception(dsp, 120);
    std::vector<float> left(12 * rate), right(12 * rate);
    for (int i = 0; i < int(left.size()); ++i) {
        left[i] = float(0.2 * std::sin(2 * pi * 997 * i / rate)); right[i] = -left[i];
    }
    for (int start = 0; start < int(left.size()); start += 256)
        RadioDSPProcess(dsp, left.data() + start, right.data() + start,
                        uint32_t(std::min(256, int(left.size()) - start)), start);
    std::ofstream csv(directory / ("balance-" + std::to_string(level) + "-bg" + std::to_string(background) + ".csv"));
    csv << "timeSeconds,musicGain,noiseRMS,musicRMS,sourceRMS\n";
    const int delay = int(RadioDSPLatencyFrames());
    for (int start = rate; start + rate / 10 < int(left.size()); start += rate / 10) {
        double sourceEnergy = 0, musicEnergy = 0, noiseEnergy = 0, cross = 0;
        for (int i = start; i < start + rate / 10; ++i) {
            double source = 0.2 * std::sin(2 * pi * 997 * (i - delay) / rate);
            double music = (left[i] - right[i]) * 0.5;
            double noise = (left[i] + right[i]) * 0.5;
            sourceEnergy += source * source; musicEnergy += music * music;
            noiseEnergy += noise * noise; cross += music * source;
        }
        csv << double(start) / rate << ',' << cross / sourceEnergy << ','
            << std::sqrt(noiseEnergy / (rate / 10)) << ',' << std::sqrt(musicEnergy / (rate / 10))
            << ',' << std::sqrt(sourceEnergy / (rate / 10)) << '\n';
    }
    for (int i = 0; i < int(left.size()); ++i) {
        float noise = (left[i] + right[i]) * 0.5f;
        left[i] = right[i] = noise;
    }
    writeWAV(directory / ("texture-" + std::to_string(level) + "-bg" + std::to_string(background) + ".wav"), left, right);
    RadioDSPDestroy(dsp);
}
}

int main(int argc, char **argv) {
    if (argc < 2) {
        std::cerr << "Usage: atplayer-radio-render OUTPUT_DIRECTORY [--stress-only] [--reference-pcm MONO_48K_FLOAT32] [--background 0..10]\n"; return 2;
    }
    try {
        bool stressOnly = false;
        int background = 7;
        std::vector<float> reference;
        for (int argument = 2; argument < argc; ++argument) {
            const std::string option(argv[argument]);
            if (option == "--stress-only") stressOnly = true;
            else if (option == "--reference-pcm" && argument + 1 < argc)
                reference = readReference(argv[++argument]);
            else if (option == "--background" && argument + 1 < argc) {
                size_t consumed = 0;
                const std::string value(argv[++argument]);
                background = std::stoi(value, &consumed);
                if (consumed != value.size() || background < 0 || background > 10)
                    throw std::runtime_error("Background must be an integer in 0...10");
            } else throw std::runtime_error("Unknown or incomplete argument: " + option);
        }
        std::cout << "texture=" << (reference.empty() ? "procedural" : "recording")
                  << "; referenceFrames=" << reference.size() << '\n';
        std::filesystem::path directory(argv[1]);
        std::filesystem::create_directories(directory);
        if (!stressOnly) {
            render(directory, "dry", 0, 0, false, reference);
            render(directory, "noise-overlay", 0, 0, true, reference);
            for (int level : {1, 2, 5, 7, 8, 9, 10}) {
                const int bed = std::min(level, background);
                render(directory, "radio-" + std::to_string(level) + "-bg" + std::to_string(bed),
                       level, bed, false, reference);
                renderIsolatedTexture(directory, level, bed, reference);
            }
            if (background != 10) {
                render(directory, "radio-10-bg10", 10, 10, false, reference);
                renderIsolatedTexture(directory, 10, 10, reference);
            }
        }
        for (int level : {1, 2, 5, 7, 8, 9, 10}) renderStress(directory, level, std::min(level, background), reference);
    } catch (const std::exception &error) { std::cerr << error.what() << '\n'; return 1; }
}
