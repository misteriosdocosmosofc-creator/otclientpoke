#include "../../src/client/pkanpctrade.h"
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>

struct Buffer {
    std::vector<uint8_t> data;
    size_t pos = 0;
    uint64_t read(size_t size) {
        if (size > data.size() - pos) throw std::runtime_error("truncated field");
        uint64_t value = 0;
        for (size_t i = 0; i < size; ++i) value |= uint64_t(data[pos++]) << (8 * i);
        return value;
    }
    uint8_t getU8() { return read(1); }
    uint16_t getU16() { return read(2); }
    uint32_t getU32() { return read(4); }
    uint64_t getU64() { return read(8); }
    std::string getString() {
        const auto size = getU16();
        if (size > data.size() - pos) throw std::runtime_error("truncated string");
        std::string text(data.begin() + pos, data.begin() + pos + size);
        pos += size;
        return text;
    }
    void add(uint64_t value, unsigned size) {
        for (unsigned i = 0; i < size; ++i) data.push_back(value >> (8 * i));
    }
    void addU16(uint16_t value) { add(value, 2); }
    void text(const std::string& value) {
        addU16(value.size());
        data.insert(data.end(), value.begin(), value.end());
    }
};

void check(bool passed) { if (!passed) throw std::runtime_error("NPC trade assertion failed"); }

template<class Read>
size_t rejectPrefixes(const Buffer& full, Read read) {
    for (size_t n = 0; n < full.data.size(); ++n) {
        Buffer cut{{full.data.begin(), full.data.begin() + n}};
        bool rejected = false;
        try { read(cut); } catch (const std::runtime_error&) { rejected = true; }
        check(rejected);
    }
    return full.data.size();
}

int main(int argc, char** argv) {
    try {
        size_t rejected = 0;
        Buffer offers;
        offers.addU16(2);
        for (const auto price : {uint64_t(0x100000001), UINT64_MAX}) {
            offers.addU16(3156); offers.addU16(0x1234); offers.text("Revive");
            offers.add(0xABCDEF01, 4); offers.add(price, 8); offers.add(UINT64_MAX, 8);
        }
        const auto entries = PkaNpcTrade::readOffers(offers);
        check(entries.size() == 2 && entries[0].subtype == 0x1234 && entries[0].name == "Revive");
        check(entries[0].weight == 0xABCDEF01 && entries[0].buyPrice == 0x100000001);
        check(entries[0].sellPrice == 0 && entries[1].buyPrice == 0 && offers.pos == offers.data.size());
        rejected += rejectPrefixes(offers, [](auto& b) { PkaNpcTrade::readOffers(b); });

        Buffer goods;
        goods.addU16(300);
        for (unsigned i = 0; i < 300; ++i) { goods.addU16(3156); goods.add(0x12345678 + i, 4); }
        goods.addU16(0x1e); // Sentinel: the following opcode must remain unread.
        const auto owned = PkaNpcTrade::readGoods(goods);
        check(owned.size() == 300 && owned.back().amount == 0x12345678 + 299 && goods.getU16() == 0x1e);
        goods.data.resize(goods.data.size() - 2);
        rejected += rejectPrefixes(goods, [](auto& b) { PkaNpcTrade::readGoods(b); });
        Buffer empty{{0, 0}};
        check(PkaNpcTrade::readOffers(empty).empty()); empty.pos = 0;
        check(PkaNpcTrade::readGoods(empty).empty());

        Buffer sent;
        PkaNpcTrade::writeTransaction(sent, 3156, 0x1234, 1000);
        check(sent.data == std::vector<uint8_t>({0x54, 0x0c, 0x34, 0x12, 0xe8, 0x03}));

        if (argc == 2) {
            // Private fixture: reconstructed U16 list header followed by all
            // complete records and the exact goods packet from the error log.
            std::ifstream file(argv[1], std::ios::binary);
            check(file.good());
            Buffer real;
            real.data.assign(std::istreambuf_iterator<char>(file), {});
            check(real.getU16() == 0x7a);
            const auto products = PkaNpcTrade::readOffers(real);
            check(products.size() == 335 && products.front().name == "Wonka Bar");
            check(products.back().name == "Infernape Topknot" && products.back().sellPrice == 245);
            check(real.getU16() == 0x7b && real.getU32() == 467553);
            const auto stock = PkaNpcTrade::readGoods(real);
            check(stock.size() == 9 && stock[1].id == 3156 && stock[1].amount == 642);
            check(real.pos == real.data.size());
            std::cout << "Private real-record regression passed: 335 offers, 9 goods, exact end.\n";
        }
        std::cout << "NPC trade helpers passed; truncated prefixes rejected: " << rejected << '\n';
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
