#include "../../src/client/pkaprotocol.h"
#include <algorithm>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>

struct Reader {
    std::vector<unsigned char> data;
    size_t pos = 0;
    uint64_t read(size_t count) {
        if (count > data.size() - std::min(pos, data.size()))
            throw std::runtime_error("unexpected end at " + std::to_string(pos));
        uint64_t value = 0;
        for (size_t i = 0; i < count; ++i) value |= uint64_t(data[pos++]) << (8 * i);
        return value;
    }
    uint8_t getU8() { return read(1); }
    uint16_t getU16() { return read(2); }
    uint32_t getU32() { return read(4); }
    uint64_t getU64() { return read(8); }
    void getString() { const auto count = getU16(); if (pos + count > data.size()) throw std::runtime_error("string out of bounds at " + std::to_string(pos)); pos += count; }
    uint16_t peekU16() { const auto saved = pos; const auto value = getU16(); pos = saved; return value; }
};

int main(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "Usage: pka-replay PAYLOAD.bin ITEM_FLAGS.txt [WIDTH HEIGHT] [TRACE.jsonl] [--tail|--packet]\nPayload starts with position U16,U16,U8.\n";
        return 2;
    }
    Reader msg;
    std::ifstream input(argv[1], std::ios::binary);
    if (!input) { std::cerr << "Cannot open payload\n"; return 2; }
    msg.data.assign(std::istreambuf_iterator<char>(input), {});
    std::vector<int> properties(65536, -1);
    std::ifstream flags(argv[2]);
    unsigned id, value;
    while (flags >> id >> value) properties.at(id) = value;
    const int width = argc >= 5 ? std::stoi(argv[3]) : PkaProtocol::MapWidth;
    const int height = argc >= 5 ? std::stoi(argv[4]) : PkaProtocol::MapHeight;
    const bool packetMode = argc >= 7 && std::string(argv[6]) == "--packet";
    std::ofstream trace;
    if (argc >= 6) trace.open(argv[5]);
    auto span = [&](const char* kind, size_t start, unsigned object) {
        if (trace) trace << "{\"kind\":\"" << kind << "\",\"start\":" << start << ",\"end\":" << msg.pos << ",\"id\":" << object << "}\n";
    };
    auto readItem = [&]() {
        const auto itemId = msg.getU16();
        const auto attrs = properties[itemId];
        if (attrs < 0) throw std::runtime_error("invalid item " + std::to_string(itemId));
        if (attrs & 7) msg.getU16();
        PkaProtocol::readItemAttributes(msg, itemId);
    };
    size_t tiles = 0, skips = 0, items = 0, creatures = 0;
    int x = 0, y = 0, z = 0, stack = 0;
    try {
        if (!packetMode) {
        const auto cx = msg.getU16(); const auto cy = msg.getU16(); const auto cz = msg.getU8();
        const int first = cz <= 7 ? 7 : cz - 3;
        const int last = cz <= 7 ? 0 : std::min<int>(15, cz + 3);
        const int step = cz <= 7 ? -1 : 1;
        int skip = 0;
        for (z = first; z != last + step; z += step) {
            for (int nx = 0; nx < width; ++nx) for (int ny = 0; ny < height; ++ny) {
                x = cx - (width / 2 - 1) + nx + cz - z;
                y = cy - (height / 2 - 1) + ny + cz - z;
                if (skip) { --skip; ++skips; continue; }
                const auto tileStart = msg.pos;
                ++tiles;
                if (msg.peekU16() < 0xff00) { msg.getU16(); msg.getU8(); }
                for (stack = 0; stack < 256; ++stack) {
                    const auto start = msg.pos;
                    const auto thingId = msg.getU16();
                    if (thingId >= 0xff00) { skip = thingId & 255; break; }
                    if (thingId == 0) throw std::runtime_error("zero thing id at " + std::to_string(start));
                    if (thingId == 0x60) {
                        msg.getU8(); msg.getString(); msg.getString();
                    } else if (thingId == 0x61 || thingId == 0x62) {
                        if (thingId == 0x61) { msg.getU32(); msg.getU32(); msg.getString(); }
                        else msg.getU32();
                        msg.getU8(); msg.getU8();
                        const auto look = msg.getU16();
                        if (look) {
                            for (int i = 0; i < 5; ++i) msg.getU8();
                        } else msg.getU16();
                        PkaProtocol::readOutfitExtension(msg, look != 0);
                        const auto tail = PkaProtocol::readCreatureTail(msg, thingId);
                        ++creatures;
                        span("creature", start, tail.subtype);
                    } else if (thingId == 0x63) {
                        msg.getU32(); msg.getU8();
                        ++creatures;
                    } else {
                        const auto attrs = properties[thingId];
                        if (attrs < 0) throw std::runtime_error("invalid item " + std::to_string(thingId) + " at " + std::to_string(start));
                        if (attrs & 7) msg.getU16();
                        PkaProtocol::readItemAttributes(msg, thingId);
                        ++items;
                        span("item", start, thingId);
                    }
                }
                if (stack == 256) throw std::runtime_error("tile exceeded 256 things");
                span("tile", tileStart, 0);
            }
        }
        std::cout << "{\"status\":\"ok\",\"width\":" << width << ",\"height\":" << height << ",\"end\":" << msg.pos << ",\"remaining\":" << msg.data.size() - msg.pos << ",\"tiles\":" << tiles << ",\"skipped\":" << skips << ",\"items\":" << items << ",\"creatures\":" << creatures << "}\n";
        }
        if (packetMode || (argc >= 7 && std::string(argv[6]) == "--tail")) {
            while (msg.pos < msg.data.size()) {
                const auto start = msg.pos;
                const auto opcode = msg.getU16();
                switch (opcode) {
                    case 0x6b: {
                        const auto count = PkaProtocol::readTileTransformCount(msg);
                        for (unsigned i = 0; i < count; ++i) {
                            if (msg.getU16() == 0xffff) msg.getU32();
                            else { msg.getU16(); msg.getU8(); msg.getU8(); }
                            if (msg.peekU16() == 0x63) {
                                msg.getU16(); msg.getU32(); msg.getU8();
                            } else readItem();
                        }
                        break;
                    }
                    case 0x83:
                        msg.getU16(); msg.getU16(); msg.getU8();
                        PkaProtocol::readEffects(msg);
                        break;
                    case 0x78: {
                        msg.getU8();
                        readItem();
                        break;
                    }
                    case 0x6e: {
                        msg.getU8(); readItem(); msg.getString();
                        msg.getU8(); msg.getU8(); msg.getString();
                        const auto count = msg.getU16();
                        for (unsigned i = 0; i < count; ++i) readItem();
                        break;
                    }
                    case 0x79: msg.getU8(); break;
                    case 0x82: msg.getU8(); msg.getU8(); msg.getU32(); break;
                    case 0x8b: msg.getU32(); msg.getU32(); msg.getU8(); msg.getU8(); break;
                    case 0x5f:
                        if (!PkaProtocol::readMapAnnotations(msg)) throw std::runtime_error("unknown annotation mode");
                        break;
                    case 0x1d: case 0x1e: break;
                    case 0xa0: PkaProtocol::readPlayerStats(msg); break;
                    case 0xa1: for (int i=0; i<7; ++i) { msg.getU8(); msg.getU8(); } break;
                    case 0xa2: msg.getU16(); break;
                    case 0x8d: msg.getU32(); msg.getU8(); msg.getU8(); break;
                    case 0x8c: msg.getU32(); msg.getU8(); break;
                    case 0x8f: msg.getU32(); msg.getU16(); break;
                    case 0x90: case 0x91: case 0x92: msg.getU32(); msg.getU8(); break;
                    case 0xd2: msg.getU32(); msg.getString(); msg.getU8(); msg.getU32(); break;
                    case 0x5c: PkaProtocol::readCustomWindow(msg); break;
                    case 0x11a: PkaProtocol::readToggleWindow(msg); break;
                    case 0x8e: {
                        msg.getU32();
                        const auto look = msg.getU16();
                        if (look) {
                            for (int i=0;i<5;++i) msg.getU8();
                        } else msg.getU16();
                        PkaProtocol::readOutfitExtension(msg, look != 0);
                        break;
                    }
                    case 0xb4: {
                        const auto mode = msg.getU8();
                        if (mode != 0x18) throw std::runtime_error("unmapped text message mode " + std::to_string(mode));
                        msg.getString(); break;
                    }
                    case 0x00ba: case 0x00c1: case 0x00c5: case 0x0105: case 0x0108: case 0x005d: case 0x005e: case 0x0053: case 0x05f7: case 0x0616: case 0x05e7: case 0x05ec: case 0x05ed: case 0x05ee: case 0x05ef: case 0x05f0:
                    case 0x0606: case 0x060a: case 0x060e: case 0x0631: case 0x0632: case 0x0633:
                        if (!PkaProtocol::readAuxiliary(msg, opcode)) throw std::runtime_error("unsupported auxiliary form");
                        break;
                    default:
                        std::cerr << "Unmapped tail opcode=0x" << std::hex << opcode << std::dec << " at=" << start << " remaining=" << msg.data.size()-start << '\n';
                        return 3;
                }
                std::cout << "tail opcode=0x" << std::hex << opcode << std::dec << " start=" << start << " end=" << msg.pos << '\n';
            }
        }
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Failure: " << error.what() << "; cursor=" << msg.pos << " tile=" << x << ',' << y << ',' << z << " stack=" << stack << " items=" << items << " creatures=" << creatures << '\n';
        return 1;
    }
}
