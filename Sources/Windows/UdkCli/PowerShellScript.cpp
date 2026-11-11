#include "PowerShellScript.h"

#include <Windows.h>

#include <system_error>
#include <string_view>
#include <process.h>
#include <stdexcept>
#include <cerrno>

namespace universaldevkit::cli {
	namespace details {
		std::filesystem::path GetExecutableDirectory() {
			std::wstring modulePath(32768, L'\0');
			const auto length = ::GetModuleFileNameW(nullptr, modulePath.data(), static_cast<DWORD>(modulePath.size()));
			if (length == 0 || length == modulePath.size()) {
				throw std::system_error(static_cast<int>(::GetLastError()), std::system_category(), "Cannot resolve the CLI executable path");
			}
			modulePath.resize(length);
			return std::filesystem::path(modulePath).parent_path();
		}

		std::wstring QuoteArgument(std::wstring_view argument) {
			// Escape backslashes before literal quotes and the closing quote for Windows argument parsing.
			std::wstring quoted = L"\"";
			std::size_t backslashes = 0;
			for (const auto character : argument) {
				if (character == L'\\') {
					++backslashes;
					continue;
				}
				quoted.append(character == L'"' ? backslashes * 2 + 1 : backslashes, L'\\');
				quoted += character;
				backslashes = 0;
			}
			quoted.append(backslashes * 2, L'\\');
			quoted += L'"';
			return quoted;
		}
	} // namespace details

	int RunPowerShellScript(const std::filesystem::path& path, const std::vector<std::wstring>& arguments) {
		// Locate the tool scripts beside the installed CLI.
		const auto scriptPath = details::GetExecutableDirectory() / L"Tools" / path;
		if (!std::filesystem::is_regular_file(scriptPath)) {
			throw std::runtime_error("Bundled tool script is missing from the Tools directory.");
		}

		// Build the child process arguments without invoking cmd.exe.
		std::vector<std::wstring> childArguments{L"pwsh.exe", L"-NoProfile", L"-File", details::QuoteArgument(scriptPath.native())};
		for (const auto& argument : arguments) {
			childArguments.push_back(details::QuoteArgument(argument));
		}
		std::vector<const wchar_t*> argumentPointers;
		argumentPointers.reserve(childArguments.size() + 1);
		for (const auto& argument : childArguments) {
			argumentPointers.push_back(argument.c_str());
		}
		argumentPointers.push_back(nullptr);

		const auto exitCode = ::_wspawnvp(_P_WAIT, L"pwsh.exe", argumentPointers.data());
		if (exitCode == -1) {
			throw std::system_error(errno, std::generic_category(), "Cannot start pwsh.exe");
		}
		return static_cast<int>(exitCode);
	}
}