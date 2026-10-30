#pragma once
#include <stdexcept>
#include <optional>
#include <istream>
#include <utility>
#include <limits>
#include <string>
#include <deque>

namespace universaldevkit::helpers::stream {
    class StreamLineReader {
    public:
        explicit StreamLineReader(
            std::istream& inStream,
            std::size_t historyCapacity = 8)
            : inStream(inStream)
            , historyDeque()
            , peekBuffer(std::nullopt)
            , historyCapacityLimit(ValidateHistoryCapacity(historyCapacity)) {
        }

        // Return the next line without consuming it from this reader.
        std::optional<std::string> PeekLine() {
            if (!this->peekBuffer.has_value()) {
                std::string line;
                if (!this->LoadNextLine(line)) {
                    return std::nullopt;
                }
                this->peekBuffer = std::move(line);
            }
            return this->peekBuffer;
        }

        // Consume the next line.
        std::optional<std::string> ReadLine() {
            int dummyIndex = 0;
            return this->ReadLine(dummyIndex);
        }

        // Return the zero-based index within the retained history, after eviction.
        std::optional<std::string> ReadLine(int& outIndex) {
            std::string line;

            if (this->peekBuffer.has_value()) {
                line = std::move(*this->peekBuffer);
                this->peekBuffer.reset();
            }
            else {
                if (!this->LoadNextLine(line)) {
                    return std::nullopt;
                }
            }

            this->historyDeque.push_back(line);
            this->EnforceCapacity();
            outIndex = static_cast<int>(this->historyDeque.size() - 1);
            return line;
        }

        // Read history: offset 0 is the last consumed line, 1 is the preceding line.
        std::optional<std::string> GetHistoryLine(int offset) const {
            if (offset < 0 || static_cast<std::size_t>(offset) >= this->historyDeque.size()) {
                return std::nullopt;
            }
            const auto indexFromStart = this->historyDeque.size() - 1 - static_cast<std::size_t>(offset);
            return this->historyDeque[indexFromStart];
        }

        [[deprecated("Use GetHistoryLine; this method reads history, not future lines.")]]
        std::optional<std::string> LookAhead(int offset) const {
            return this->GetHistoryLine(offset);
        }

    private:
        static std::size_t ValidateHistoryCapacity(std::size_t capacity) {
            if (capacity > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
                throw std::invalid_argument("History capacity exceeds the supported index range");
            }
            return capacity > 0 ? capacity : 1;
        }

        bool LoadNextLine(std::string& outLine) {
            outLine.clear();
            try {
                if (!std::getline(this->inStream, outLine)) {
                    if (this->inStream.bad() || !this->inStream.eof()) {
                        throw std::ios_base::failure("Unable to read a line");
                    }
                    return false;
                }
            }
            catch (const std::ios_base::failure&) {
                // EOF is normal, including for the final line without a newline.
                if (this->inStream.bad() || !this->inStream.eof()) {
                    throw;
                }
                if (outLine.empty()) {
                    return false;
                }
            }
            this->TrimCarriageReturn(outLine);
            return true;
        }

        void TrimCarriageReturn(std::string& lineString) {
            if (!lineString.empty() && lineString.back() == '\r') {
                lineString.pop_back();
            }
        }

        void EnforceCapacity() {
            while (this->historyDeque.size() > this->historyCapacityLimit) {
                this->historyDeque.pop_front();
            }
        }

    private:
        std::istream& inStream;
        std::deque<std::string> historyDeque;  // History of consumed lines.
        std::optional<std::string> peekBuffer; // Line buffered by PeekLine().
        std::size_t historyCapacityLimit;
    };
}