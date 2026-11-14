// Measures only this generator on the current machine, not a device callback deadline.
// clang++ -std=c++17 -O2 -I Sources/RadioNoiseKit/include \
//   Sources/RadioNoiseKit/RadioNoiseKit.cpp Tools/benchmark_render.cpp -o /tmp/radio-noise-benchmark
#include "RadioNoiseKit.h"
#include <array>
#include <chrono>
#include <iostream>

int main() {
    for (int rate : {44100, 48000, 96000}) {
        auto *generator = RadioNoiseCreate(rate, 2, 20261114);
        if (!generator) return 1;
        RadioNoiseSetParameters(generator, {1, 1, 1, 1, 1, 1, 1});
        std::array<float, 256> left{}, right{};
        for (int block = 0; block < 1000; ++block)
            RadioNoiseRender(generator, left.data(), right.data(), 256);
        constexpr int blocks = 30000;
        auto start = std::chrono::steady_clock::now();
        for (int block = 0; block < blocks; ++block)
            RadioNoiseRender(generator, left.data(), right.data(), 256);
        double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
        std::cout << rate << ',' << blocks * 256 << ',' << elapsed << '\n';
        RadioNoiseDestroy(generator);
    }
}
