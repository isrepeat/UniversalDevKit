#include <UniversalDevKit/DiagnosticTest/Logging.h>

#include <string_view>
#include <algorithm>
#include <streambuf>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace {
    class StreamRestore {
    public:
        StreamRestore() : buffer(std::clog.rdbuf()), state(std::clog.rdstate()), mask(std::clog.exceptions()) {}

        ~StreamRestore() {
            // Возвращаем исходный поток даже при раннем выходе из проверки.
            std::clog.exceptions(std::ios::goodbit);
            std::clog.rdbuf(buffer);
            std::clog.clear(state);
            try { std::clog.exceptions(mask); } catch (...) {}
        }

    private:
        std::streambuf* buffer;
        std::ios::iostate state;
        std::ios::iostate mask;
    };

    class FailingBuffer : public std::streambuf {
    protected:
        std::streamsize xsputn(const char*, std::streamsize) override { return 0; }
        int_type overflow(int_type) override { return traits_type::eof(); }
    };
}

int main() {
    using universaldevkit::diagnostictest::Log;
    using universaldevkit::diagnostictest::TryLog;
    static_assert(noexcept(Log(std::string_view{})));
    static_assert(noexcept(TryLog(std::string_view{})));

    // 1. Проверяем пустой буфер, временную строку, CR/LF и текст с нулевым байтом.
    std::stringbuf capture;
    FailingBuffer failingBuffer;
    StreamRestore streamRestore;
    std::clog.exceptions(std::ios::goodbit);
    std::clog.rdbuf(&capture);
    if (!TryLog({}) || !TryLog(std::string("temporary")) || !TryLog("line\n") || !TryLog("cr\r")) {
        return 1;
    }
    const std::string binary("a\0b", 3);
    if (!TryLog(binary)) { return 2; }
    std::string expected = "\ntemporary\nline\ncr\r";
    expected += binary + '\n';
    if (capture.str() != expected) { return 3; }

    // 2. Несколько потоков пишут через один DiagnosticTest; строки не должны смешиваться.
    capture.str("");
    std::vector<std::thread> threads;
    std::vector<std::string> expectedLines;
    for (int worker = 0; worker < 4; ++worker) {
        for (int index = 0; index < 100; ++index) {
            expectedLines.push_back(std::to_string(worker) + ":" + std::to_string(index));
        }
        threads.emplace_back([worker] {
            for (int index = 0; index < 100; ++index) {
                Log(std::to_string(worker) + ":" + std::to_string(index));
            }
        });
    }
    for (auto& thread : threads) { thread.join(); }
    std::istringstream captured(capture.str());
    std::vector<std::string> actualLines;
    std::string line;
    while (std::getline(captured, line)) { actualLines.push_back(line); }
    std::sort(actualLines.begin(), actualLines.end());
    std::sort(expectedLines.begin(), expectedLines.end());
    if (actualLines != expectedLines) { return 4; }

    // 3. Ошибка потока возвращает false, включая включённые исключения std::clog.
    std::clog.rdbuf(&failingBuffer);
    if (TryLog("failure")) { return 5; }
    if (TryLog("still failed") || std::clog.good()) { return 8; }
    std::clog.clear();
    std::clog.exceptions(std::ios::badbit | std::ios::failbit);
    if (TryLog("throwing failure")) { return 6; }
    Log("ignored failure");

    // 4. После восстановления потока блокировка освобождена и запись снова работает.
    std::clog.exceptions(std::ios::goodbit);
    std::clog.rdbuf(&capture);
    capture.str("");
    if (!TryLog("recovered") || capture.str() != "recovered\n") { return 7; }
    return 0;
}