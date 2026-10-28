#pragma once
#include "StreamHelpers.h"

#include <string_view>
#include <filesystem>
#include <algorithm>
#include <stdexcept>
#include <cstdint>
#include <fstream>
#include <utility>
#include <limits>
#include <string>
#include <vector>
#include <span>

namespace universaldevkit::helpers::stream {
    class StreamLineViewer {
    public:
        StreamLineViewer(std::istream& inStream) {
            this->buffer = this->ReadAll(inStream);
            this->lines = this->SplitToLines(this->buffer);
        }

        StreamLineViewer(const std::filesystem::path& filePath) {
            std::ifstream inStream(filePath, std::ios::binary);
            universaldevkit::helpers::stream::ThrowIfStreamNotOpened(inStream);

            this->buffer = this->ReadAll(inStream);
            this->lines = this->SplitToLines(this->buffer);
        }

        StreamLineViewer(const StreamLineViewer&) = delete;
        StreamLineViewer& operator=(const StreamLineViewer&) = delete;

        // Rebase internal views, including when the source string uses SSO.
        // Previously returned views/spans are invalidated by a move.
        StreamLineViewer(StreamLineViewer&& streamLineViewer) noexcept
            : StreamLineViewer(std::move(streamLineViewer), streamLineViewer.buffer.data()) {
        }

        StreamLineViewer& operator=(StreamLineViewer&& streamLineViewer) noexcept {
            if (this != &streamLineViewer) {
                const auto* sourceBase = streamLineViewer.buffer.data();
                this->buffer = std::move(streamLineViewer.buffer);
                this->lines = std::move(streamLineViewer.lines);
                this->RebaseLines(sourceBase);
                streamLineViewer.lines.clear();
                streamLineViewer.buffer.clear();
            }
            return *this;
        }

        std::span<const std::string_view> GetAllLines() const {
            return std::span<const std::string_view>(this->lines.data(), this->lines.size());
        }

        std::string_view GetLine(std::size_t index) const {
            if (index >= this->lines.size()) {
                return std::string_view{};
            }

            return this->lines[index];
        }

        std::span<const std::string_view> GetLinesSpan(std::size_t start, std::size_t end) const {
            if (start > end) {
                end = start;
            }

            if (start > this->lines.size()) {
                start = this->lines.size();
            }

            if (end > this->lines.size()) {
                end = this->lines.size();
            }

            const std::size_t count = end - start;

            return this->GetAllLines().subspan(start, count);
        }

    private:
        StreamLineViewer(StreamLineViewer&& streamLineViewer, const char* sourceBase) noexcept
            : buffer(std::move(streamLineViewer.buffer))
            , lines(std::move(streamLineViewer.lines)) {
            this->RebaseLines(sourceBase);
            streamLineViewer.lines.clear();
            streamLineViewer.buffer.clear();
        }

        void RebaseLines(const char* sourceBase) noexcept {
            for (auto& line : this->lines) {
                const auto offset = static_cast<std::size_t>(line.data() - sourceBase);
                line = std::string_view(this->buffer.data() + offset, line.size());
            }
        }

        // Read the entire seekable stream from the beginning; do not hide I/O failures.
        std::string ReadAll(std::istream& inStream) {
            if (!inStream.good()) {
                throw std::ios_base::failure("StreamLineViewer requires a readable stream");
            }
            inStream.seekg(0, std::ios::end);
            if (!inStream) {
                throw std::ios_base::failure("StreamLineViewer requires a seekable stream");
            }

            const auto endOffset = static_cast<std::streamoff>(inStream.tellg());
            if (!inStream || endOffset < 0) {
                throw std::ios_base::failure("Unable to determine stream length");
            }
            const auto length = static_cast<std::uintmax_t>(endOffset);
            if (length > std::numeric_limits<std::size_t>::max() ||
                length > static_cast<std::uintmax_t>(std::numeric_limits<std::streamsize>::max())) {
                throw std::length_error("Stream is too large");
            }

            std::string outBuffer(static_cast<std::size_t>(length), '\0');
            inStream.seekg(0, std::ios::beg);
            if (!inStream) {
                throw std::ios_base::failure("Unable to seek to stream beginning");
            }
            if (!outBuffer.empty()) {
                const auto expected = static_cast<std::streamsize>(outBuffer.size());
                inStream.read(outBuffer.data(), expected);
                if (!inStream || inStream.gcount() != expected) {
                    throw std::ios_base::failure("Unable to read the complete stream");
                }
            }
            return outBuffer;
        }

        std::vector<std::string_view> SplitToLines(const std::string& buffer) {
            std::vector<std::string_view> outLines;

            const char* const begin = buffer.data();
            const char* const end = begin + buffer.size();

            const char* lineStart = begin;

            for (const char* p = begin; p != end; ++p) {
                if (*p == '\n') {
                    std::string_view sv(lineStart, static_cast<std::size_t>(p - lineStart));

                    this->TrimCarriageReturn(sv);
                    outLines.emplace_back(sv);

                    lineStart = p + 1;
                }
            }

            if (lineStart < end) {
                std::string_view sv(lineStart, static_cast<std::size_t>(end - lineStart));

                this->TrimCarriageReturn(sv);
                outLines.emplace_back(sv);
            }

            return outLines;
        }

        void TrimCarriageReturn(std::string_view& sv) {
            if (!sv.empty()) {
                if (sv.back() == '\r') {
                    sv.remove_suffix(1);
                }
            }
        }

    private:
        std::string buffer;
        std::vector<std::string_view> lines;
    };
}