#pragma once

#include "game.h"
#include "localplayer.h"
#include "map.h"
#include "tile.h"

// Explicit, bounded diagnostics. Do not retain tiles/things or invoke Lua: doing
// either can change the lifetime/timing of the state being investigated.
namespace PkaMovementTrace {
inline bool enabled = false;
inline uint32_t packet = 0, opcodeIndex = 0, records = 0;
inline int opcode = -1;
inline std::string_view reason = "packet";
inline const void* session = nullptr;
inline Position lastPosition;
inline bool sampled = false, lastPresent = false;
constexpr uint32_t MaxRecords = 4096;

struct Reason {
    std::string_view previous;
    explicit Reason(std::string_view value) : previous(reason) { reason = value; }
    ~Reason() { reason = previous; }
};

inline void beginPacket(const void* protocol, bool active) {
    enabled = active;
    if (!active) return;
    if (session != protocol) {
        session = protocol;
        packet = opcodeIndex = records = 0;
        sampled = false;
    }
    ++packet;
    reason = "packet";
}

inline void sample(std::string_view phase, bool force = false) {
    if (!enabled || records >= MaxRecords) return;
    const auto& player = g_game.getLocalPlayer();
    if (!player) return;
    const auto position = player->getServerPosition();
    const auto& tile = player->getTile();
    const bool present = tile && tile->hasThing(player);
    if (force || !sampled || position != lastPosition || present != lastPresent) {
        ++records;
        g_logger.info("[pka-membership] packet={} step={} opcode=0x{:04X} phase={} reason={} id={} pos={} center={} inTile={} removed={} pre={} stack={} things={}",
            packet, opcodeIndex, opcode, phase, reason, player->getId(), position,
            g_map.getCentralPosition(), present, player->isRemoved(), player->isPreWalking(),
            player->getStackPos(), tile ? tile->getThings().size() : 0);
    }
    sampled = true;
    lastPosition = position;
    lastPresent = present;
}

inline void mutation(std::string_view action, Tile& tile, const ThingPtr& thing) {
    if (!enabled || records >= MaxRecords || !thing->isLocalPlayer()) return;
    ++records;
    g_logger.info("[pka-membership-mutation] packet={} step={} opcode=0x{:04X} action={} reason={} id={} tile={} serverPos={} stack={}",
        packet, opcodeIndex, opcode, action, reason, thing->getId(), tile.getPosition(),
        thing->getServerPosition(), thing->getStackPos());
}

inline void move(const ThingPtr& thing, const Position& destination) {
    if (!enabled || records >= MaxRecords) return;
    ++records;
    g_logger.info("[pka-membership-move] packet={} step={} mappedId={} creature={} local={} source={} dest={}",
        packet, opcodeIndex, thing ? thing->getId() : 0, thing && thing->isCreature(),
        thing && thing->isLocalPlayer(), thing ? thing->getServerPosition() : Position{}, destination);
}
}
