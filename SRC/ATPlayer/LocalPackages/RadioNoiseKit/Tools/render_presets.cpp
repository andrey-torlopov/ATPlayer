// Original procedural synthesis. No reference audio is loaded or embedded.
// clang++ -std=c++17 -O2 -I Sources/RadioNoiseKit/include \
//   Sources/RadioNoiseKit/RadioNoiseKit.cpp Tools/render_presets.cpp -o /tmp/radio-noise-render
// /tmp/radio-noise-render OUTPUT_DIRECTORY
#include "RadioNoiseKit.h"
#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static void integer(std::ofstream &file, uint32_t value, int bytes) {
    for (int i = 0; i < bytes; ++i) file.put(char((value >> (8 * i)) & 255));
}

static void render(const std::filesystem::path &directory, const std::string &name,
                   RadioNoiseParameters parameters, int rate) {
    auto *generator = RadioNoiseCreate(rate, 1, 20261114);
    if (!generator) throw std::runtime_error("Generator allocation failed");
    parameters.masterLevel = 1; // Unit gain for comparable analysis, not demo volume.
    RadioNoiseSetParameters(generator, parameters);
    const int count = rate * 30;
    std::vector<float> samples(count);
    for (int offset = 0; offset < count; offset += 256)
        RadioNoiseRender(generator, samples.data() + offset, nullptr, uint32_t(std::min(256, count - offset)));
    RadioNoiseDestroy(generator);
    std::ofstream file(directory / (name + "-" + std::to_string(rate) + ".wav"), std::ios::binary);
    if (!file) throw std::runtime_error("Cannot create output");
    file.write("RIFF", 4); integer(file, uint32_t(count * 4 + 36), 4); file.write("WAVEfmt ", 8);
    integer(file, 16, 4); integer(file, 3, 2); integer(file, 1, 2);
    integer(file, rate, 4); integer(file, rate * 4, 4); integer(file, 4, 2); integer(file, 32, 2);
    file.write("data", 4); integer(file, uint32_t(count * 4), 4);
    double square = 0, peak = 0;
    for (float sample : samples) {
        if (!std::isfinite(sample)) throw std::runtime_error("Non-finite sample");
        square += double(sample) * sample; peak = std::max(peak, std::abs(double(sample)));
        file.write(reinterpret_cast<const char *>(&sample), 4);
    }
    std::cout << name << "," << rate << ",RMS=sqrt(" << square << "/" << count << ")="
              << std::sqrt(square / count) << ",peak=" << peak << '\n';
}

int main(int argc, char **argv) {
    if (argc != 2) { std::cerr << "Usage: radio-noise-render OUTPUT_DIRECTORY\n"; return 2; }
    try {
        std::filesystem::path directory(argv[1]);
        std::filesystem::create_directories(directory);
        const char *names[] = {"blended", "retro07", "ringing", "fading", "uniden12", "retro08"};
        for (int preset = 0; preset < 6; ++preset)
            for (int rate : {44100, 48000, 96000})
                render(directory, names[preset], RadioNoiseParametersForPreset(RadioNoisePreset(preset)), rate);
        const char *components[] = {"hiss", "crackle", "resonance", "chatter", "squelch-component"};
        for (int i = 0; i < 5; ++i) {
            RadioNoiseParameters p{1, 0.7f, 0, 0, 0, 0, 0};
            switch (i) {
            case 0: p.hissLevel = 1; break;
            case 1: p.crackleLevel = 1; break;
            case 2: p.resonanceLevel = 1; break;
            case 3: p.chatterLevel = 1; break;
            default: p.squelchLevel = 1;
            }
            render(directory, components[i], p, 48000);
        }
    } catch (const std::exception &error) { std::cerr << error.what() << '\n'; return 1; }
}
