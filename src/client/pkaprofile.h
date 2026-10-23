#pragma once

#include <cstdint>

namespace PkaProtocol {
inline constexpr int MapLeft = 15;
inline constexpr int MapTop = 9;
inline constexpr int MapRight = 16;
inline constexpr int MapBottom = 10;
inline constexpr int MapWidth = MapLeft + MapRight + 1;
inline constexpr int MapHeight = MapTop + MapBottom + 1;
inline constexpr int UndergroundRange = 3;

struct ItemAttributes { uint8_t text = 0; uint8_t metadata = 0; };
}
