#include "../../src/client/pkaprotocol.h"
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>

struct Reader {
    std::vector<uint8_t> data;
    size_t pos = 0;
    uint64_t read(size_t size) {
        if (pos > data.size() || size > data.size() - pos) throw std::runtime_error("truncated field");
        uint64_t value = 0;
        for (size_t i = 0; i < size; ++i) value |= uint64_t(data[pos++]) << (8 * i);
        return value;
    }
    uint8_t getU8() { return read(1); }
    uint16_t getU16() { return read(2); }
    uint32_t getU32() { return read(4); }
    uint64_t getU64() { return read(8); }
    void getString() {
        const size_t size = getU16();
        if (pos > data.size() || size > data.size() - pos) throw std::runtime_error("truncated string");
        pos += size;
    }
};

void consume(Reader& msg, uint8_t kind, uint16_t param) {
    switch (kind) {
        case 0: PkaProtocol::readOutfitExtension(msg, param != 0); break;
        case 1: {
            const auto result = PkaProtocol::readCreatureTail(msg, param);
            if (result.speed != 220 || result.skull != 3 || result.shield != 4 ||
                result.emblem != (param == 0x61 ? 5 : 0) || !result.unpass)
                throw std::runtime_error("decoded creature fields differ from fixture");
            break;
        }
        case 2: PkaProtocol::readItemAttributes(msg, param); break;
        case 3: PkaProtocol::readEffects(msg); break;
        case 4:
            if (PkaProtocol::readTileTransformCount(msg) != param)
                throw std::runtime_error("decoded transform count differs from fixture");
            break;
        case 5:
            if (!PkaProtocol::readAuxiliary(msg, param))
                throw std::runtime_error("unsupported auxiliary fixture");
            break;
        default: throw std::runtime_error("unknown fixture kind");
    }
}

int main(int argc, char** argv) {
    if (argc != 2) { std::cerr << "Usage: pka-coverage helper-cases.bin\n"; return 2; }
    std::ifstream file(argv[1], std::ios::binary);
    Reader corpus;
    corpus.data.assign(std::istreambuf_iterator<char>(file), {});
    size_t cases = 0, truncated = 0;
    try {
        if (corpus.getU32() != 0x43414b50) throw std::runtime_error("bad fixture header");
        const auto count = corpus.getU32();
        for (; cases < count; ++cases) {
            const auto kind = corpus.getU8();
            const auto param = corpus.getU16();
            const size_t length = corpus.getU32();
            if (length > corpus.data.size() - corpus.pos) throw std::runtime_error("truncated fixture corpus");
            Reader msg;
            msg.data.assign(corpus.data.begin()+corpus.pos, corpus.data.begin()+corpus.pos+length);
            corpus.pos += length;
            msg.data.insert(msg.data.end(), {0x78, 0x00, 0xa5, 0x5a});
            consume(msg, kind, param);
            if (msg.pos != length || msg.getU16() != 0x78 || msg.getU16() != 0x5aa5)
                throw std::runtime_error("reader crossed the next packet boundary");
            // Every proper prefix must reject; silently accepting one can move
            // the next opcode into the current object's optional fields.
            for (size_t prefix = 0; prefix < length; ++prefix) {
                Reader cut;
                cut.data.assign(msg.data.begin(), msg.data.begin()+prefix);
                bool rejected = false;
                try { consume(cut, kind, param); } catch (const std::exception&) { rejected = true; }
                if (!rejected) throw std::runtime_error("accepted a truncated object");
                ++truncated;
            }
        }
        if (corpus.pos != corpus.data.size()) throw std::runtime_error("trailing fixture data");
        std::cout << "{\"status\":\"passed\",\"validCases\":" << cases << ",\"truncationsRejected\":" << truncated << "}\n";
    } catch (const std::exception& error) {
        std::cerr << "Case " << cases << ": " << error.what() << '\n';
        return 1;
    }
}
