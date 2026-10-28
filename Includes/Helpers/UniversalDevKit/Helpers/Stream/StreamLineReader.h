#pragma once
#include <optional>
#include <istream>
#include <utility>
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
            , historyCapacityLimit(historyCapacity > 0 ? historyCapacity : 1) {
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

        // Consume a line and return its history index through outIndex.
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

            // The index is the history size before this line is added.
            outIndex = this->historyDeque.size();

            this->historyDeque.push_back(line);
            this->EnforceCapacity();
            return line;
        }

        // Read history: offset 0 is the last consumed line, 1 is the preceding line.
        std::optional<std::string> LookAhead(int offset) const {
            if (offset >= this->historyDeque.size()) {
                return std::nullopt;
            }
            int indexFromStart = this->historyDeque.size() - 1 - offset;
            return this->historyDeque[indexFromStart];
        }

    private:
        bool LoadNextLine(std::string& outLine) {
            if (!std::getline(this->inStream, outLine)) {
                return false;
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