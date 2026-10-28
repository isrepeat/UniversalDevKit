#pragma once
#include "../../Stream/StreamHelpers.h"
#include "../../Regex/Regex.h"
#include "../Config.h"

#include <unordered_map>
#include <algorithm>
#include <stdexcept>
#include <iterator>
#include <optional>
#include <cstdint>
#include <fstream>
#include <string>
#include <vector>
#include <array>

namespace universaldevkit::helpers::stdext::extensions {
    enum class UTFByteOrderMark {
        UTF8,
        UTF16_BE,
        UTF16_LE,
        UTF32_BE,
        UTF32_LE
    };

    struct ifstream : public std::ifstream {
        using std::ifstream::basic_ifstream;

        static const inline std::unordered_map<UTFByteOrderMark, std::vector<uint8_t>> KnownUTFByteOrderMarks = {
            {UTFByteOrderMark::UTF8, {0xEF, 0xBB, 0xBF}},
            {UTFByteOrderMark::UTF16_BE, {0xFE, 0xFF}},
            {UTFByteOrderMark::UTF16_LE, {0xFF, 0xFE}},
            {UTFByteOrderMark::UTF32_BE, {0x00, 0x00, 0xFE, 0xFF}},
            {UTFByteOrderMark::UTF32_LE, {0xFF, 0xFE, 0x00, 0x00}},
        };

        struct Data {
            std::vector<char> byteArray;
            std::optional<int> codePage;
        };

        Data ReadData() {
            if (!this->is_open()) {
                throw std::ios_base::failure("ReadData requires an open file");
            }
            universaldevkit::helpers::stream::ThrowIfStreamNotOpened(*this, "ReadData");
            universaldevkit::helpers::stream::ThrowIfStreamFailed(*this, "ReadData");

            auto& ifstreamRef = static_cast<std::ifstream&>(*this);

            this->SkipUTFByteOrderMark();

            Data data;
            data.codePage = this->DetectCodePageInFirstLineOfStream();

            data.byteArray = std::vector<char>{std::istreambuf_iterator<char>(ifstreamRef), std::istreambuf_iterator<char>()};
            return data;
        }

        std::optional<UTFByteOrderMark> DetectUTFByteOrderMark() {
            std::istream::pos_type originalPos = this->tellg();
            if (originalPos != 0) {
                throw std::runtime_error("DetectUTFByteOrderMark must be called at the beginning of the stream");
            }

            // Probe through the buffer so a short file does not set failbit/eofbit
            // or trigger the caller's exception mask. Restore the exact position.
            std::array<char, 4> buffer{};
            std::streamsize readBytes;
            try {
                readBytes = this->rdbuf()->sgetn(buffer.data(), buffer.size());
            }
            catch (...) {
                this->seekg(originalPos);
                throw;
            }
            this->seekg(originalPos);
            universaldevkit::helpers::stream::ThrowIfStreamFailed(*this, "DetectUTFByteOrderMark");

            // UTF-32 LE shares its first two bytes with UTF-16 LE.
            constexpr std::array order{
                UTFByteOrderMark::UTF32_BE,
                UTFByteOrderMark::UTF32_LE,
                UTFByteOrderMark::UTF8,
                UTFByteOrderMark::UTF16_BE,
                UTFByteOrderMark::UTF16_LE
            };
            for (auto bomType : order) {
                const auto& bom = KnownUTFByteOrderMarks.at(bomType);
                if (static_cast<std::size_t>(readBytes) >= bom.size() &&
                    std::equal(bom.begin(), bom.end(), reinterpret_cast<const uint8_t*>(buffer.data()))) {
                    return bomType;
                }
            }

            return std::nullopt;
        }

    private:
        void SkipUTFByteOrderMark() {
            std::istream::pos_type originalPos = this->tellg();
            if (originalPos != 0) {
                throw std::runtime_error("SkipUTFByteOrderMarkInStream must be called at the beginning of the stream (tellg() == 0)");
            }

            auto bomType = this->DetectUTFByteOrderMark();
            if (!bomType) {
                return;
            }

            const auto& bom = KnownUTFByteOrderMarks.at(*bomType);
            this->seekg(static_cast<std::streamoff>(bom.size()), std::ios::beg); // Skip the UTF BOM.
            universaldevkit::helpers::stream::ThrowIfStreamFailed(*this, "SkipUTFByteOrderMark");
        }

        std::optional<int> DetectCodePageInFirstLineOfStream() {
            const auto originalPos = this->tellg();

            // Start after the BOM and leave the stream state untouched on EOF.
            std::string firstLine;
            auto* buffer = this->rdbuf();
            using Traits = std::char_traits<char>;
            try {
                for (auto next = buffer->sbumpc(); !Traits::eq_int_type(next, Traits::eof()); next = buffer->sbumpc()) {
                    const auto character = Traits::to_char_type(next);
                    if (character == '\n') {
                        break;
                    }
                    firstLine.push_back(character);
                }
                auto matches = universaldevkit::helpers::regex::GetRegexMatches<char, std::string>(
                    firstLine,
                    std::regex("CodePage\\s*=\\s*(\\d+)")
                );
                if (!matches.empty() && matches[0].capturedGroups.size() > 1) {
                    return std::stoi(matches[0].capturedGroups[1]);
                }
            }
            catch (...) {
                this->seekg(originalPos);
                throw;
            }

            this->seekg(originalPos);
            universaldevkit::helpers::stream::ThrowIfStreamFailed(*this, "DetectCodePageInFirstLineOfStream");

            return std::nullopt;
        }
    };

    struct ofstream : public std::ofstream {
        using std::ofstream::ofstream;

        void WriteUTFByteOrderMark(UTFByteOrderMark bomType = UTFByteOrderMark::UTF8) {
            const auto& bom = ifstream::KnownUTFByteOrderMarks.at(bomType);
            this->write(reinterpret_cast<const char*>(bom.data()), static_cast<std::streamsize>(bom.size()));
            universaldevkit::helpers::stream::ThrowIfStreamFailed(*this, "WriteUTF8ByteOrderMark");
        }
    };
}