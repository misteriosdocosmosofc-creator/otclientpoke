// Compare the production login serializer to an independently authenticated PC
// capture. All input files are private; never commit credential/key fixtures.
#include "../src/client/pkalogin.h"

#include <fstream>
#include <iostream>
#include <iterator>

static std::string readFile(const std::string& path)
{
    std::ifstream stream(path, std::ios::binary);
    if (!stream) throw std::runtime_error("Cannot open private fixture file");
    return {std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
}

int main(int argc, char** argv)
{
    try {
        if (argc != 2) throw std::invalid_argument("Usage: pka-login-check PRIVATE_FIXTURE_DIRECTORY");
        const auto path = std::string(argv[1]) + "/";
        const auto rawKey = readFile(path + "key.bin");
        if (rawKey.size() != 16) throw std::runtime_error("Invalid key length");
        std::array<uint32_t, 4> key{};
        for (size_t n = 0; n < key.size(); ++n)
            key[n] = PkaLogin::readU32(rawKey, n * 4);
        const auto encrypted = PkaLogin::encryptCredentials(readFile(path + "credential-body.bin"), key);
        if (encrypted != readFile(path + "encrypted.bin"))
            throw std::runtime_error("Production XTEA envelope differs from the PC capture");
        const auto header = PkaLogin::rsaHeader(key, encrypted.size(), readFile(path + "sha256.txt"), 128);
        if (header != readFile(path + "rsa-header.bin"))
            throw std::runtime_error("Production RSA plaintext differs from the authenticated PC header");
        std::cout << "MATCH: production serializer reproduces " << encrypted.size()
                  << " XTEA bytes and " << header.size() << " RSA header bytes exactly.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
