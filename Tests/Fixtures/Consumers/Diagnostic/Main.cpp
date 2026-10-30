#include <UniversalDevKit/Diagnostic/Logging.h>
#include <UniversalDevKit/Platform.h>

#include "ContractValue.h"

#if UNIVERSALDEVKIT_PLATFORM_WINDOWS
#include <io.h>
#else
#include <unistd.h>
#endif

#include <source_location>
#include <filesystem>
#include <algorithm>
#include <stdexcept>
#include <iostream>
#include <fstream>
#include <barrier>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <format>
#include <thread>
#include <vector>
#include <string>
#include <set>

#if UNIVERSALDEVKIT_PLATFORM_WINDOWS
#define DIAGNOSTIC_TEST_IMPORT __declspec(dllimport)
#else
#define DIAGNOSTIC_TEST_IMPORT
#endif

extern "C" {
    DIAGNOSTIC_TEST_IMPORT bool ModuleAInitialize(universaldevkit::diagnostic::LoggerId loggerId, const char* path);
    DIAGNOSTIC_TEST_IMPORT bool ModuleBInitialize(universaldevkit::diagnostic::LoggerId loggerId, const char* path);
    DIAGNOSTIC_TEST_IMPORT void ModuleAWrite(universaldevkit::diagnostic::LoggerId loggerId, const char* message);
    DIAGNOSTIC_TEST_IMPORT void ModuleBWrite(universaldevkit::diagnostic::LoggerId loggerId, const char* message);
    DIAGNOSTIC_TEST_IMPORT bool ModuleAEnabled(universaldevkit::diagnostic::LoggerId loggerId);
    DIAGNOSTIC_TEST_IMPORT bool ModuleBEnabled(universaldevkit::diagnostic::LoggerId loggerId);
    DIAGNOSTIC_TEST_IMPORT void ModuleASetLevel(universaldevkit::diagnostic::LoggerId loggerId);
    DIAGNOSTIC_TEST_IMPORT void ModuleBSetLevel(universaldevkit::diagnostic::LoggerId loggerId);
}

namespace diagnostic_tests {
    namespace diagnostic = universaldevkit::diagnostic;
    namespace fs = std::filesystem;

    void Check(bool value, std::string_view message, std::source_location sourceLocation = std::source_location::current()) {
        if (!value) {
            throw std::runtime_error(std::format("{}:{}: {}", sourceLocation.file_name(), sourceLocation.line(), message));
        }
    }

    std::string Read(const fs::path& path) {
        std::ifstream stream(path, std::ios::binary);
        diagnostic_tests::Check(stream.good(), "Cannot read log file");
        return { std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>() };
    }

    std::size_t Count(std::string_view text, std::string_view token) {
        std::size_t count = 0;
        for (auto offset = text.find(token); offset != std::string_view::npos; offset = text.find(token, offset + token.size())) {
            ++count;
        }
        return count;
    }

    diagnostic::LoggerOptions Options(const fs::path& path) {
        diagnostic::LoggerOptions loggerOptions;
        loggerOptions.filePath = path;
        loggerOptions.minimumLevel = diagnostic::Level::Trace;
        loggerOptions.appendNewSession = false;
        return loggerOptions;
    }

    void Initialize(const diagnostic::LoggerOptions& loggerOptions, diagnostic::LoggerId loggerId = 0) {
        const auto result = diagnostic::Logger::Initialize(loggerOptions, loggerId);
        diagnostic_tests::Check(static_cast<bool>(result), result.message);
    }

    void Fallback(const fs::path& path) {
        // Restore stderr before asserting so a failure is visible to the runner.
#if UNIVERSALDEVKIT_PLATFORM_WINDOWS
        auto* file = ::_wfopen(path.c_str(), L"w+b");
        const int stderrFd = ::_fileno(stderr);
        const int original = ::_dup(stderrFd);
        std::fflush(stderr);
        const bool redirected = file && original >= 0 && ::_dup2(::_fileno(file), stderrFd) == 0;
#else
        auto* file = std::fopen(path.c_str(), "w+b");
        const int stderrFd = ::fileno(stderr);
        const int original = ::dup(stderrFd);
        std::fflush(stderr);
        const bool redirected = file && original >= 0 && ::dup2(::fileno(file), stderrFd) >= 0;
#endif
        if (redirected) {
            diagnostic::Logger::SetLevel(diagnostic::Level::Warning);
            diagnostic::Logger::Write(diagnostic::Level::Info, "Fallback", "hidden-fallback");
            diagnostic::Logger::Write(diagnostic::Level::Warning, "Fallback", "fallback-after-shutdown");
        }
        std::fflush(stderr);
#if UNIVERSALDEVKIT_PLATFORM_WINDOWS
        const bool restored = original >= 0 && ::_dup2(original, stderrFd) == 0;
        if (original >= 0) { ::_close(original); }
#else
        const bool restored = original >= 0 && ::dup2(original, stderrFd) >= 0;
        if (original >= 0) { ::close(original); }
#endif
        if (file) { std::fclose(file); }
        diagnostic_tests::Check(redirected && restored, "Cannot capture fallback stderr");
        const auto text = diagnostic_tests::Read(path);
        diagnostic_tests::Check(text.find("fallback-after-shutdown") != std::string::npos && text.find("hidden-fallback") == std::string::npos, "Fallback or its filter failed");
    }

    class Worker {
        UDK_LOG_CLASS(Worker)
    public:
        void Run(bool fail) {
            UDK_LOG_FUNCTION_SCOPE_C();
            UDK_LOG_SCOPE_C("operation {}", 17);
            UDK_LOG_INFO_C("object-context");
            if (fail) {
                throw std::runtime_error("expected");
            }
            return;
        }
    };

    void Contract(const fs::path& root) {
        // Initialization failures must not replace a working backend.
        auto loggerOptions = diagnostic_tests::Options(root / "contract.log");
        diagnostic_tests::Initialize(loggerOptions);
        auto result = diagnostic::Logger::Initialize(loggerOptions);
        diagnostic_tests::Check(!result && result.error == diagnostic::LoggerInitError::AlreadyInitialized && !result.message.empty(), "Repeated ID");
        result = diagnostic::Logger::Initialize(loggerOptions, 8);
        diagnostic_tests::Check(!result && result.error == diagnostic::LoggerInitError::FileAlreadyUsed, "Shared file ownership");
        auto invalid = loggerOptions;
        invalid.maxFileSize = 0;
        result = diagnostic::Logger::Initialize(invalid, 8);
        diagnostic_tests::Check(!result && result.error == diagnostic::LoggerInitError::InvalidOptions, "Invalid size");
        const auto blocker = root / "not-directory";
        std::ofstream{blocker} << "file";
        invalid.filePath = blocker / "child.log";
        invalid.maxFileSize = 1024;
        result = diagnostic::Logger::Initialize(invalid, 8);
        diagnostic_tests::Check(!result && result.error == diagnostic::LoggerInitError::DirectoryUnavailable && result.systemError, "Directory error details");

        // Levels, eager flush and compile-time checked narrow/wide formatting.
        int evaluated = 0;
        diagnostic::Logger::SetLevel(diagnostic::Level::Info);
        UDK_LOG_DEBUG("Test", "hidden-debug {}", ++evaluated);
        diagnostic_tests::Check(evaluated == 0, "Filtered arguments were evaluated");
        UDK_LOG_INFO("Test", "visible-info");
        UDK_LOG_WARNING("Test", "visible-warning");
        UDK_LOG_ERROR("Test", "visible-error");
        UDK_LOG_CRITICAL("Test", "visible-critical");
        const auto beforeShutdown = diagnostic_tests::Read(loggerOptions.filePath);
        diagnostic_tests::Check(beforeShutdown.find("visible-critical") != std::string::npos, "Flush before shutdown");
        diagnostic::Logger::SetLevel(diagnostic::Level::Off);
        UDK_LOG_CRITICAL("Test", "hidden-off");
        diagnostic::Logger::SetLevel(diagnostic::Level::Trace);
        UDK_LOG_TRACE("Test", "visible-trace");
        UDK_LOG_DEBUG("Test", "visible-debug");
        UDK_LOG_INFO("Unicode", "Кириллица 日本 😀");
        UDK_LOG_INFO("Unicode", L"Кириллица 日本 😀");
        UDK_LOG_INFO("Custom", "custom-narrow {}", ContractValue{42});
        UDK_LOG_INFO("Custom", L"custom-wide {}", ContractValue{43});
        diagnostic::Logger::Write(diagnostic::Level::Info, "Ready", "literal {} braces");
        diagnostic::Logger::Write(diagnostic::Level::Info, "Ready", std::wstring_view(L"ready-wide 😀"));
        diagnostic::Logger::Write(diagnostic::Level::Info, "Ready", std::string_view("embedded\0value", 14));
        diagnostic::Logger::Write(diagnostic::Level::Info, "Invalid", std::wstring(1, static_cast<wchar_t>(0xD800)));
        Worker worker;
        worker.SetLogInstanceName("one");
        worker.Run(false);
        try { worker.Run(true); } catch (const std::runtime_error&) {}
        {
            UDK_LOG_SCOPE("Scope", "wide {}", 3);
            UDK_LOG_SCOPE("Scope", L"wide {}", 4);
        }
        diagnostic::Logger::SetLevel(diagnostic::Level::Info);
        { UDK_LOG_SCOPE("Scope", "hidden-scope {}", ++evaluated); }
        diagnostic_tests::Check(evaluated == 0, "Disabled scope evaluated arguments");
        diagnostic::Logger::Shutdown();
        diagnostic::Logger::Shutdown();
        const auto text = diagnostic_tests::Read(loggerOptions.filePath);
        for (const auto* token : { "visible-info", "visible-warning", "visible-error", "visible-critical", "visible-debug", "visible-trace", "custom-narrow 42", "custom-wide 43", "literal {} braces", "ready-wide 😀", "Worker[one]", ">> operation 17", "<< operation 17", ", exception)", "us)" }) {
            diagnostic_tests::Check(text.find(token) != std::string::npos, token);
        }
        diagnostic_tests::Check(diagnostic_tests::Count(text, "Кириллица 日本 😀") == 2, "Narrow/wide UTF-8 must agree");
        diagnostic_tests::Check(text.find(std::string("embedded\0value", 14)) != std::string::npos, "Embedded NUL was lost");
        diagnostic_tests::Check(text.find("Failed to convert wide log message to UTF-8") != std::string::npos, "Invalid wide input did not produce an error record");
        diagnostic_tests::Check(text.find("hidden-") == std::string::npos && text.find('\x1b') == std::string::npos, "Filtered messages or color escaped into file");

        // Appending sessions and independent destinations.
        loggerOptions.appendNewSession = true;
        for (int session = 0; session < 2; ++session) {
            diagnostic_tests::Initialize(loggerOptions);
            UDK_LOG_INFO("Session", "session-value {}", session);
            diagnostic::Logger::Shutdown();
        }
        diagnostic_tests::Check(diagnostic_tests::Count(diagnostic_tests::Read(loggerOptions.filePath), "New session started") == 2, "Session markers");
        diagnostic_tests::Check(diagnostic_tests::Read(loggerOptions.filePath).find("visible-info") != std::string::npos, "Append lost old records");
        loggerOptions.fileMode = diagnostic::FileMode::Truncate;
        loggerOptions.appendNewSession = false;
        diagnostic_tests::Initialize(loggerOptions);
        auto second = diagnostic_tests::Options(root / "subdirectory" / fs::path(u8"журнал😀.log"));
        second.minimumLevel = diagnostic::Level::Warning;
        diagnostic_tests::Initialize(second, 7);
        UDK_LOG_INFO("Test", "fresh-only");
        UDK_LOG_INFO_N(7, "Other", "hidden-other");
        UDK_LOG_ERROR_N(7, "Other", "second-only");
        diagnostic::Logger::Shutdown();
        const auto fresh = diagnostic_tests::Read(loggerOptions.filePath);
        diagnostic_tests::Check(fresh.find("visible-info") == std::string::npos && fresh.find("New session started") == std::string::npos, "Truncate or marker disabled");
        diagnostic_tests::Check(fresh.find("second-only") == std::string::npos, "ID isolation");
        diagnostic_tests::Check(diagnostic_tests::Read(second.filePath).find("second-only") != std::string::npos && diagnostic_tests::Read(second.filePath).find("hidden-other") == std::string::npos, "Independent ID level/path");

        // Rotation contracts: one archive, no archive, oversized record and startup rotation.
        for (std::size_t archives : { 0u, 1u }) {
            auto rotating = diagnostic_tests::Options(root / std::format("rotation{}.log", archives));
            rotating.maxFileSize = 512;
            rotating.maxFiles = archives;
            diagnostic_tests::Initialize(rotating);
            for (int index = 0; index < 50; ++index) { UDK_LOG_INFO("Rotate", "rotation-record {} abcdefghijklmnopqrstuvwxyz", index); }
            diagnostic::Logger::Shutdown();
            diagnostic_tests::Check(fs::file_size(rotating.filePath) <= rotating.maxFileSize, "Active file size");
            diagnostic_tests::Check(fs::exists(root / std::format("rotation{}.1.log", archives)) == (archives == 1), "Archive count");
            diagnostic_tests::Check(!fs::exists(root / std::format("rotation{}.2.log", archives)), "Excess archive");
        }
        auto large = diagnostic_tests::Options(root / "large.log");
        large.maxFileSize = 512;
        diagnostic_tests::Initialize(large);
        const std::string payload(2048, 'x');
        UDK_LOG_INFO("Large", "large-record {}", payload);
        diagnostic::Logger::Shutdown();
        diagnostic_tests::Check(diagnostic_tests::Read(large.filePath).find(payload) != std::string::npos, "Large record was truncated");
        diagnostic_tests::Initialize(large);
        UDK_LOG_INFO("Large", "after-reopen");
        diagnostic::Logger::Shutdown();
        diagnostic_tests::Check(fs::exists(root / "large.1.log") && fs::file_size(large.filePath) <= large.maxFileSize, "Oversized startup rotation");
        diagnostic_tests::Fallback(root / "fallback.log");
    }

    void Threads(const fs::path& root) {
        // Race initialization, then verify the exact set of concurrent records.
        const auto loggerOptions = diagnostic_tests::Options(root / "threads.log");
        constexpr int workers = 8;
        constexpr int records = 100;
        std::barrier start(workers);
        std::atomic<int> successes{0};
        std::atomic<int> unexpected{0};
        std::vector<std::thread> threads;
        for (int worker = 0; worker < workers; ++worker) {
            threads.emplace_back([&] {
                start.arrive_and_wait();
                const auto result = diagnostic::Logger::Initialize(loggerOptions);
                if (result) { ++successes; }
                else if (result.error != diagnostic::LoggerInitError::AlreadyInitialized) { ++unexpected; }
            });
        }
        for (auto& thread : threads) { thread.join(); }
        diagnostic_tests::Check(successes == 1 && unexpected == 0, "Concurrent initialization");
        threads.clear();
        for (int worker = 0; worker < workers; ++worker) {
            threads.emplace_back([&, worker] {
                for (int record = 0; record < records; ++record) {
                    UDK_LOG_INFO("Concurrent", "REC|{}|{}|abcdefghijklmnopqrstuvwxyz", worker, record);
                }
            });
        }
        for (auto& thread : threads) { thread.join(); }
        diagnostic::Logger::Shutdown();
        std::set<std::string> expected;
        for (int worker = 0; worker < workers; ++worker) {
            for (int record = 0; record < records; ++record) {
                expected.insert(std::format("REC|{}|{}|abcdefghijklmnopqrstuvwxyz", worker, record));
            }
        }
        std::ifstream stream(loggerOptions.filePath);
        std::string line;
        int count = 0;
        while (std::getline(stream, line)) {
            if (!line.empty() && line.back() == '\r') { line.pop_back(); }
            const auto offset = line.find("REC|");
            diagnostic_tests::Check(offset != std::string::npos && expected.erase(line.substr(offset)) == 1, "Mixed, duplicate or unexpected line");
            ++count;
        }
        diagnostic_tests::Check(expected.empty() && count == workers * records, "Lost concurrent records");
    }

    void Modules(const fs::path& root) {
        // Initialize in A, change the common level in B, observe and write from all three modules.
        constexpr diagnostic::LoggerId id = 27;
        const auto path = root / "modules.log";
        const auto utf8Path = path.u8string();
        const std::string pathString(reinterpret_cast<const char*>(utf8Path.data()), utf8Path.size());
        diagnostic_tests::Check(::ModuleAInitialize(id, pathString.c_str()), "Module A initialization");
        diagnostic_tests::Check(::ModuleAEnabled(id) && ::ModuleBEnabled(id) && diagnostic::Logger::ShouldLog(diagnostic::Level::Debug, id), "Level not shared");
        diagnostic_tests::Check(!::ModuleBInitialize(id, pathString.c_str()), "Module B created another logger");
        auto duplicate = diagnostic::Logger::Initialize(diagnostic_tests::Options(path), id);
        diagnostic_tests::Check(!duplicate && duplicate.error == diagnostic::LoggerInitError::AlreadyInitialized, "Host has separate state");
        ::ModuleBSetLevel(id);
        diagnostic_tests::Check(!::ModuleAEnabled(id) && !::ModuleBEnabled(id) && !diagnostic::Logger::ShouldLog(diagnostic::Level::Debug, id), "Module B level invisible");
        ::ModuleAWrite(id, "from-A");
        ::ModuleBWrite(id, "from-B");
        UDK_LOG_WARNING_N(id, "Host", "from-host");
        diagnostic::Logger::Shutdown();
        auto text = diagnostic_tests::Read(path);
        for (const auto* token : { "from-A", "from-B", "from-host" }) {
            diagnostic_tests::Check(diagnostic_tests::Count(text, token) == 1, "Module message missing or repeated");
        }
        diagnostic_tests::Check(::ModuleBInitialize(id, pathString.c_str()), "Shutdown in host did not release module state");
        ::ModuleASetLevel(id);
        diagnostic_tests::Check(!::ModuleBEnabled(id), "Module A level invisible");
        diagnostic::Logger::Shutdown();
    }
}

int main(int argc, char** argv) {
    try {
        diagnostic_tests::Check(argc == 3, "Usage: DiagnosticContract contract|threads|modules output-directory");
        const std::string scenario(argv[1]);
        const auto root = std::filesystem::absolute(argv[2]) / std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
        std::filesystem::create_directories(root);
        if (scenario == "contract") { diagnostic_tests::Contract(root); }
        else if (scenario == "threads") { diagnostic_tests::Threads(root); }
        else if (scenario == "modules") { diagnostic_tests::Modules(root); }
        else { throw std::invalid_argument("Unknown diagnostic test"); }
        std::cout << "DIAGNOSTIC_PASS " << scenario << '\n';
        return 0;
    }
    catch (const std::exception& exception) {
        universaldevkit::diagnostic::Logger::Shutdown();
        std::cerr << "DIAGNOSTIC_FAIL " << exception.what() << '\n';
        return 1;
    }
}