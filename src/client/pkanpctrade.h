#pragma once

#include <cstdint>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace PkaNpcTrade {
// DX 140779f10 (0x7a): U16 list size/subtype and U64 prices.
struct Offer {
    uint16_t id, subtype;
    std::string name;
    uint32_t weight;
    uint64_t buyPrice, sellPrice;
};

template<class Reader>
std::vector<Offer> readOffers(Reader& msg)
{
    const auto count = msg.getU16();
    std::vector<Offer> offers;
    offers.reserve(count);
    for (unsigned i = 0; i < count; ++i) {
        Offer offer;
        offer.id = msg.getU16();
        offer.subtype = msg.getU16();
        offer.name = msg.getString();
        offer.weight = msg.getU32();
        offer.buyPrice = msg.getU64();
        offer.sellPrice = msg.getU64();
        // The original's signed -1 means this trade direction is unavailable.
        if (offer.buyPrice == std::numeric_limits<uint64_t>::max()) offer.buyPrice = 0;
        if (offer.sellPrice == std::numeric_limits<uint64_t>::max()) offer.sellPrice = 0;
        offers.push_back(std::move(offer));
    }
    return offers;
}

struct Goods {
    uint16_t id;
    uint32_t amount;
};

template<class Reader>
std::vector<Goods> readGoods(Reader& msg)
{
    // DX 14077a450 (0x7b), after the feature-selected money field.
    const auto count = msg.getU16();
    std::vector<Goods> goods;
    goods.reserve(count);
    for (unsigned i = 0; i < count; ++i) {
        const auto id = msg.getU16();
        const auto amount = msg.getU32();
        goods.push_back({id, amount});
    }
    return goods;
}

template<class Writer>
void writeTransaction(Writer& msg, uint16_t id, uint16_t subtype, uint16_t amount)
{
    // Buy: DX 1405a0290; sell: DX 140726050. Flags follow these three U16s.
    msg.addU16(id);
    msg.addU16(subtype);
    msg.addU16(amount);
}
}
