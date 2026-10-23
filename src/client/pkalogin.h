#pragma once

#include <array>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <string_view>

namespace PkaLogin {
inline void appendU16(std::string& data, const uint16_t value)
{
    data.push_back(static_cast<char>(value));
    data.push_back(static_cast<char>(value >> 8));
}

inline void appendU32(std::string& data, const uint32_t value)
{
    for (int shift = 0; shift < 32; shift += 8)
        data.push_back(static_cast<char>(value >> shift));
}

inline uint32_t readU32(const std::string& data, const size_t offset)
{
    uint32_t result = 0;
    for (int byte = 0; byte < 4; ++byte)
        result |= static_cast<uint32_t>(static_cast<uint8_t>(data[offset + byte])) << (byte * 8);
    return result;
}

inline std::string encryptCredentials(const std::string_view body, const std::array<uint32_t, 4>& key)
{
    if (body.size() > 0xffff - 9)
        throw std::length_error("PKA login credentials exceed the packet limit");
    std::string plain;
    appendU16(plain, static_cast<uint16_t>(body.size()));
    plain.append(body);
    plain.resize((plain.size() + 7) & ~size_t(7), '\0');
    std::string encrypted;
    encrypted.reserve(plain.size());
    for (size_t offset = 0; offset < plain.size(); offset += 8) {
        uint32_t left = readU32(plain, offset), right = readU32(plain, offset + 4);
        uint32_t sum = 0;
        for (int round = 0; round < 32; ++round) {
            left += (((right << 4) ^ (right >> 5)) + right) ^ (sum + key[sum & 3]);
            sum += 0x9e3779b9;
            right += (((left << 4) ^ (left >> 5)) + left) ^ (sum + key[(sum >> 11) & 3]);
        }
        appendU32(encrypted, left);
        appendU32(encrypted, right);
    }
    return encrypted;
}

inline std::string rsaHeader(const std::array<uint32_t, 4>& key, const size_t encryptedSize,
                             const std::string_view digest, const size_t rsaSize)
{
    if (encryptedSize > 0xffff || digest.size() != 64)
        throw std::invalid_argument("Invalid PKA login envelope size or SHA-256 digest");
    std::string header(1, '\0');
    for (const auto word : key)
        appendU32(header, word);
    header.push_back(static_cast<char>(0xff));
    appendU16(header, static_cast<uint16_t>(encryptedSize));
    appendU16(header, static_cast<uint16_t>(digest.size()));
    header.append(digest);
    if (header.size() > rsaSize)
        throw std::length_error("PKA login envelope exceeds the RSA block");
    header.resize(rsaSize, '\0');
    return header;
}
} // namespace PkaLogin
