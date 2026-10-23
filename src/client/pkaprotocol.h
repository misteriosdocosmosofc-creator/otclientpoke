#pragma once

#include <cstdint>
#include <vector>

// Wire readers shared by ProtocolGame and the small offline replay executable.
// Unknown fields keep their measured types instead of guessing their meaning.
namespace PkaProtocol {
inline constexpr int MapLeft = 15;
inline constexpr int MapTop = 9;
inline constexpr int MapRight = 16;
inline constexpr int MapBottom = 10;
inline constexpr int MapWidth = MapLeft + MapRight + 1;
inline constexpr int MapHeight = MapTop + MapBottom + 1;
inline constexpr int UndergroundRange = 3;

template<class Reader>
void readLoginExtension(Reader& msg)
{
    msg.getU8(); msg.getU8(); msg.getU16(); msg.getString();
    msg.getU16(); msg.getU16(); msg.getU16(); msg.getU64();
    msg.getU16(); msg.getString();
}

template<class Reader>
void readOutfitExtension(Reader& msg)
{
    msg.getU64(); msg.getU64();
    msg.getString(); // Outfit extension bit 42 is active in the captured PKA profile.
}

struct ItemAttributes { uint8_t text = 0; uint8_t metadata = 0; };

struct PlayerStats {
    uint16_t health, maxHealth;
    uint32_t capacity;
    uint64_t experience;
    uint16_t level;
    uint8_t percent;
};

template<class Reader>
void readPlayerMetadata(Reader& msg, uint16_t opcode)
{
    switch (opcode) {
        case 0x05ec:
            msg.getU16(); msg.getU64(); msg.getU64(); msg.getString();
            msg.getU32(); msg.getU64(); msg.getU32(); msg.getU8();
            msg.getString(); msg.getU8(); msg.getU64(); msg.getU16(); msg.getU16();
            break;
        case 0x05ed: msg.getU16(); break;
        case 0x05ee: case 0x05ef: msg.getU64(); break;
        case 0x05f0: msg.getString(); msg.getString(); break;
    }
}

template<class Reader>
void readCustomWindow(Reader& msg)
{
    if (msg.getU8() == 1) {
        msg.getString();
        const auto count = msg.getU8();
        for (unsigned i = 0; i < count; ++i) {
            msg.getString(); msg.getU32(); msg.getU32(); msg.getString(); msg.getU16();
        }
    }
}

template<class Reader>
void readToggleWindow(Reader& msg)
{
    if (msg.getU8() == 1) { msg.getU16(); msg.getString(); msg.getString(); }
}

template<class Reader>
bool readAuxiliary(Reader& msg, uint16_t opcode)
{
    if (opcode == 0x0053) {
        const auto mode = msg.getU8();
        const unsigned count = mode == 1 ? msg.getU16() : 1;
        for (unsigned i = 0; i < count; ++i) { msg.getU16(); msg.getU32(); }
    } else if (opcode == 0x05e7) {
        if (msg.getU8() == 1) {
            const auto count = msg.getU16();
            for (unsigned i = 0; i < count; ++i) {
                msg.getU16(); msg.getU16(); msg.getU8(); msg.getString(); msg.getString();
                const auto children = msg.getU8();
                for (unsigned child = 0; child < children; ++child) { msg.getU16(); msg.getString(); }
            }
        }
    } else if (opcode >= 0x05ec && opcode <= 0x05f0) {
        readPlayerMetadata(msg, opcode);
    } else if (opcode == 0x011a) {
        readToggleWindow(msg);
    } else if (opcode == 0x060a) {
        msg.getU8(); msg.getU32(); msg.getU64(); msg.getU32(); msg.getU32();
    } else if (opcode == 0x060e) {
        msg.getU8();
    } else if (opcode == 0x0631) {
        msg.getU32(); msg.getU32();
    } else if (opcode == 0x0632) {
        const auto count = msg.getU16();
        for (unsigned i = 0; i < count; ++i) {
            msg.getU16(); msg.getU16(); msg.getU8(); msg.getU8(); msg.getString();
        }
    } else if (opcode == 0x0633) {
        if (msg.getU8() != 2) return false;
        const auto count = msg.getU16();
        for (unsigned i = 0; i < count; ++i) {
            msg.getString(); msg.getU16(); msg.getU16(); msg.getU8(); msg.getU16(); msg.getU8();
        }
    } else if (opcode == 0x0606) {
        const auto mode = msg.getU8();
        if (mode == 1) {
            msg.getU32(); msg.getU16(); msg.getString(); msg.getString(); msg.getU8(); msg.getU8();
        } else if (mode == 11) {
            const auto count = msg.getU16();
            for (unsigned i = 0; i < count; ++i) { msg.getU32(); msg.getString(); msg.getU16(); }
        } else return false; // Other guild forms need their own schema.
    } else return false;
    return true;
}

template<class Reader>
PlayerStats readPlayerStats(Reader& msg)
{
    PlayerStats stats;
    stats.health = msg.getU16(); stats.maxHealth = msg.getU16();
    stats.capacity = msg.getU32(); stats.experience = msg.getU64();
    stats.level = msg.getU16(); stats.percent = msg.getU8();
    msg.getU16(); msg.getU8(); msg.getU8(); // Additional PC player state.
    return stats;
}

template<class Reader>
ItemAttributes readItemAttributes(Reader& msg, uint16_t id)
{
    ItemAttributes result;
    result.text = msg.getU8();
    if (result.text == 1) {
        msg.getString(); msg.getString();
        if (id == 0x25a0) msg.getString();
        msg.getU8(); msg.getU16();
    } else if (result.text == 3) {
        msg.getString();
    }
    result.metadata = msg.getU8();
    return result;
}

struct CreatureTail {
    uint16_t speed = 0;
    uint8_t skull = 0, shield = 0, emblem = 0, subtype = 0;
    uint8_t attributeCount = 0, recordCount = 0;
    bool unpass = true;
};

template<class Reader>
std::vector<uint16_t> readEffects(Reader& msg)
{
    std::vector<uint16_t> effects;
    const auto count = msg.getU8();
    effects.reserve(count);
    for (unsigned i = 0; i < count; ++i) effects.push_back(msg.getU16());
    if (msg.getU8() == 1) msg.getU32();
    return effects;
}

// PKA opcode 0x5F is map annotations, not the vanilla Wheel of Destiny packet.
template<class Reader>
bool readMapAnnotations(Reader& msg)
{
    const auto mode = msg.getU8();
    if (mode == 0 || mode == 1) {
        const unsigned groups = mode == 0 ? msg.getU8() : 1;
        for (unsigned group = 0; group < groups; ++group) {
            msg.getU16(); msg.getU16(); msg.getU8();
            const auto count = msg.getU8();
            for (unsigned i = 0; i < count; ++i) { msg.getString(); msg.getU16(); }
        }
    } else if (mode == 2) {
        msg.getU8(); msg.getU16();
    } else if (mode == 3) {
        const auto count = msg.getU8();
        for (unsigned i = 0; i < count; ++i) {
            msg.getU16(); msg.getU8(); msg.getString(); msg.getString(); msg.getU16();
        }
    } else return false;
    return true;
}

template<class Reader>
CreatureTail readCreatureTail(Reader& msg, uint16_t type)
{
    CreatureTail result;
    result.speed = msg.getU16();
    result.skull = msg.getU8();
    result.shield = msg.getU8();
    if (type == 0x61) result.emblem = msg.getU8();
    result.subtype = msg.getU8();
    result.unpass = msg.getU8() == 0;

    // PC callsites 759301..7593FB are ONLY reached for subtype zero.
    if (result.subtype == 0) {
        msg.getString(); msg.getU8(); msg.getU16(); msg.getString();
        msg.getU8(); msg.getU8(); msg.getU8();
    }
    result.attributeCount = msg.getU8();
    for (uint16_t i = 0; i < result.attributeCount; ++i) {
        msg.getString(); msg.getU16(); msg.getU16();
    }

    // PC tests ((subtype - 1) & 0xFD): subtypes 1 AND 3 omit this block.
    if (result.subtype != 1 && result.subtype != 3) {
        if (result.subtype == 4) {
            // Seven direct bytes precede the optional byte in FUN_1407588b0.
            // With gate=0: 7 fixed + 1 subtype field + 1 flag + 1 count = 10.
            uint8_t optional = 0;
            for (int i = 0; i < 7; ++i) optional = msg.getU8();
            if (optional != 0) msg.getU8();
            msg.getU8(); msg.getU8();
        }
        result.recordCount = msg.getU8();
        for (uint16_t i = 0; i < result.recordCount; ++i) {
            msg.getU16(); msg.getU64(); msg.getU16();
            msg.getU8(); msg.getU8(); msg.getU8();
        }
        msg.getString();
        if (result.subtype == 2) msg.getU8();
    }
    return result;
}
}
