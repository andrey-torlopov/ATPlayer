// Optional sanitizer stress; the fence argument in README is the ordering proof.
// clang++ -std=c++17 -O1 -g -fsanitize=address,undefined \
//   -I Sources/RadioNoiseKit/include Tools/test_control_snapshot.cpp -o /tmp/radio-noise-controls
#include "../Sources/RadioNoiseKit/RadioNoiseKit.cpp"
#include <cassert>
#include <iostream>
#include <thread>

int main() {
    ParameterMailbox mailbox;
    std::atomic<bool> done{false};
    std::thread writer([&] {
        for (int i = 0; i < 100000; ++i) {
            float value = (i & 1) ? 0.25f : 0.75f;
            mailbox.write({value, value, value, value, value, value, value});
        }
        done.store(true, std::memory_order_release);
    });
    uint64_t serial = 0;
    std::array<float, parameterCount> values{};
    do {
        if (mailbox.read(values, serial)) for (float value : values) assert(value == values[0]);
    } while (!done.load(std::memory_order_acquire));
    writer.join();
    RadioNoiseGenerator generator(48000, 2, 42);
    done.store(false);
    std::thread controls([&] {
        for (int i = 0; i < 10000; ++i) {
            auto p = RadioNoiseParametersForPreset(RadioNoisePreset(i % 5));
            p.masterLevel = (i & 1) ? 0.1f : 1;
            RadioNoiseSetParameters(&generator, p);
            if (i % 23 == 0) RadioNoiseReset(&generator, uint64_t(i));
        }
        done.store(true, std::memory_order_release);
    });
    std::array<float, 256> left{}, right{};
    do {
        RadioNoiseRender(&generator, left.data(), right.data(), uint32_t(left.size()));
        for (size_t i = 0; i < left.size(); ++i)
            assert(std::isfinite(left[i]) && std::abs(left[i]) <= 1 && left[i] == right[i]);
    } while (!done.load(std::memory_order_acquire));
    controls.join();
    std::cout << "PASS: coherent control snapshots; concurrent render/parameters/reset remain finite and bounded\n";
}
