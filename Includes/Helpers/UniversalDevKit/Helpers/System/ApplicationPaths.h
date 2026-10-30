#pragma once
#include <UniversalDevKit/Platform.h>

#if UNIVERSALDEVKIT_PLATFORM_WINDOWS
#pragma push_macro("NOMINMAX")
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <roapi.h>
#if WINAPI_FAMILY_PARTITION(WINAPI_PARTITION_DESKTOP)
#include <appmodel.h>
#else
#include <winrt/Windows.ApplicationModel.h>
#endif
#include <winrt/Windows.Storage.h>
#if defined(_MSC_VER)
#pragma comment(lib, "windowsapp")
#endif
#pragma pop_macro("NOMINMAX")
#elif UNIVERSALDEVKIT_PLATFORM_MACOS
#include <mach-o/dyld.h>
#endif

#include <system_error>
#include <filesystem>
#include <stdexcept>
#include <cstdint>
#include <vector>

namespace universaldevkit::helpers::system {
    class ApplicationPaths final {
    public:
        ApplicationPaths() = delete;

        static std::filesystem::path GetExecutablePath() {
#if UNIVERSALDEVKIT_PLATFORM_WINDOWS
            std::vector<wchar_t> buffer(512);
            for (;;) {
                const auto length = ::GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
                if (length == 0) {
                    throw std::system_error(static_cast<int>(::GetLastError()), std::system_category(), "GetModuleFileNameW");
                }
                if (length < buffer.size()) {
                    return std::filesystem::path(std::wstring(buffer.data(), length));
                }
                if (buffer.size() >= 32768) {
                    throw std::runtime_error("Executable path exceeds Windows path limit");
                }
                buffer.resize(buffer.size() * 2);
            }
#elif (UNIVERSALDEVKIT_PLATFORM_LINUX || UNIVERSALDEVKIT_PLATFORM_ANDROID)
            return std::filesystem::read_symlink("/proc/self/exe");
#elif UNIVERSALDEVKIT_PLATFORM_MACOS
            std::uint32_t length = 0;
            ::_NSGetExecutablePath(nullptr, &length);
            std::vector<char> buffer(length);
            if (::_NSGetExecutablePath(buffer.data(), &length) != 0) {
                throw std::runtime_error("Cannot resolve executable path");
            }
            return std::filesystem::canonical(buffer.data());
#else
            throw std::runtime_error("Executable path is not supported on this platform");
#endif
        }

        static std::filesystem::path GetExecutableDirectory() {
            return ApplicationPaths::GetExecutablePath().parent_path();
        }

        // Installation directory, not writable package data or the current directory.
        // An unpackaged process (or a non-Windows platform) has no Windows package.
        static std::filesystem::path GetPackageDirectory() {
#if UNIVERSALDEVKIT_PLATFORM_WINDOWS
#if WINAPI_FAMILY_PARTITION(WINAPI_PARTITION_DESKTOP)
            UINT32 length = 0;
            const auto result = ::GetCurrentPackagePath(&length, nullptr);
            if (result == APPMODEL_ERROR_NO_PACKAGE) {
                return {};
            }
            if (result != ERROR_INSUFFICIENT_BUFFER) {
                throw std::system_error(result, std::system_category(), "GetCurrentPackagePath");
            }
            std::vector<wchar_t> buffer(length);
            const auto pathResult = ::GetCurrentPackagePath(&length, buffer.data());
            if (pathResult != ERROR_SUCCESS) {
                throw std::system_error(pathResult, std::system_category(), "GetCurrentPackagePath");
            }
            return std::filesystem::path(buffer.data());
#else
            return std::filesystem::path(winrt::Windows::ApplicationModel::Package::Current().InstalledLocation().Path().c_str());
#endif
#else
            return {};
#endif
        }

        // Writable per-user LocalState; never the package installation directory.
        static std::filesystem::path GetPackageLocalDataDirectory() {
#if UNIVERSALDEVKIT_PLATFORM_WINDOWS
            if (ApplicationPaths::GetPackageDirectory().empty()) {
                return {};
            }
            // Preserve an existing STA and balance only our own successful initialization.
            struct ApartmentScope {
                HRESULT result = ::RoInitialize(RO_INIT_MULTITHREADED);

                ~ApartmentScope() {
                    if (SUCCEEDED(result)) {
                        ::RoUninitialize();
                    }
                }
            };
            const ApartmentScope apartmentScope;
            if (FAILED(apartmentScope.result) && apartmentScope.result != RPC_E_CHANGED_MODE) {
                throw winrt::hresult_error(apartmentScope.result);
            }
            return std::filesystem::path(winrt::Windows::Storage::ApplicationData::Current().LocalFolder().Path().c_str());
#else
            return {};
#endif
        }

        static std::filesystem::path GetApplicationDirectory() {
#if UNIVERSALDEVKIT_PLATFORM_ANDROID
            throw std::runtime_error("Android application directories require an application Context; use its files/assets APIs");
#else
            const auto packageDirectory = ApplicationPaths::GetPackageDirectory();
            return packageDirectory.empty() ? ApplicationPaths::GetExecutableDirectory() : packageDirectory;
#endif
        }
    };
}