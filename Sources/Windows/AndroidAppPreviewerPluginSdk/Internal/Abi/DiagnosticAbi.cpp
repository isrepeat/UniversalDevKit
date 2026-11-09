#include "Internal/Abi/DiagnosticAbi.h"

#include <Windows.h>

#include <UniversalDevKit/Diagnostic/Logging.h>

#include <filesystem>
#include <exception>
#include <cstdlib>
#include <atomic>
#include <mutex>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi {
    namespace details {
        [[noreturn]] void HandleUnhandledCppException() noexcept {
            try {
                const std::exception_ptr exception = std::current_exception();
                if (exception == nullptr) {
                    UDK_LOG_ERROR("Application.PreviewPlugin", "std::terminate called without an active exception");
                } else {
                    std::rethrow_exception(exception);
                }
            } catch (const std::exception& error) {
                UDK_LOG_ERROR("Application.PreviewPlugin", "Unhandled C++ exception: {}", error.what());
            } catch (...) {
                UDK_LOG_ERROR("Application.PreviewPlugin", "Unhandled non-standard C++ exception");
            }
            std::abort();
        }

        bool IsFatalWindowsException(DWORD code) {
            switch (code) {
            case EXCEPTION_ACCESS_VIOLATION:
            case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:
            case EXCEPTION_DATATYPE_MISALIGNMENT:
            case EXCEPTION_ILLEGAL_INSTRUCTION:
            case EXCEPTION_IN_PAGE_ERROR:
            case EXCEPTION_INT_DIVIDE_BY_ZERO:
            case EXCEPTION_INT_OVERFLOW:
            case EXCEPTION_STACK_OVERFLOW:
                return true;
            default:
                return false;
            }
        }

        LONG WINAPI HandleVectoredWindowsException(EXCEPTION_POINTERS* exception) {
            static std::atomic_flag isLogging = ATOMIC_FLAG_INIT;
            if (exception == nullptr || exception->ExceptionRecord == nullptr) {
                return EXCEPTION_CONTINUE_SEARCH;
            }
            const DWORD code = exception->ExceptionRecord->ExceptionCode;
            if (IsFatalWindowsException(code) && !isLogging.test_and_set()) {
                UDK_LOG_ERROR("Application.PreviewPlugin", "Vectored Windows exception code: {}", code);
            }
            return EXCEPTION_CONTINUE_SEARCH;
        }

        LONG WINAPI HandleUnhandledWindowsException(EXCEPTION_POINTERS* exception) {
            const DWORD code = exception != nullptr && exception->ExceptionRecord != nullptr
                ? exception->ExceptionRecord->ExceptionCode
                : 0;
            UDK_LOG_ERROR("Application.PreviewPlugin", "Unhandled Windows exception code: {}", code);
            return EXCEPTION_CONTINUE_SEARCH;
        }

        void InstallUnhandledExceptionHandlers() {
            static std::once_flag installed;
            std::call_once(installed, [] {
                std::set_terminate(HandleUnhandledCppException);
                ::AddVectoredExceptionHandler(0, HandleVectoredWindowsException);
                ::SetUnhandledExceptionFilter(HandleUnhandledWindowsException);
            });
        }
    } // namespace details

    using namespace universaldevkit::windows::androidapppreviewerpluginsdk;

    //
    // Методы
    //
    void DiagnosticAbi::xp_configure_logging(const char* filePath) {
        universaldevkit::diagnostic::LoggerOptions loggerOptions;
        loggerOptions.filePath = filePath == nullptr ? std::filesystem::path{} : std::filesystem::path(filePath);
        const auto loggerInitResult = universaldevkit::diagnostic::Logger::Initialize(loggerOptions);
        if (!loggerInitResult && loggerInitResult.error != universaldevkit::diagnostic::LoggerInitError::AlreadyInitialized) {
            throw std::runtime_error(loggerInitResult.message);
        }
        details::InstallUnhandledExceptionHandlers();
        UDK_LOG_INFO("Application.PreviewPlugin", "Logging initialized");
    }

    void DiagnosticAbi::xp_log_info(const char* message) {
        if (message != nullptr) {
            UDK_LOG_INFO("AndroidAppPreviewer.Interaction", "{}", message);
        }
    }
} // namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi