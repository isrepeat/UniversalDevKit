#include "PowerShellScript.h"

#include <Windows.h>

#include <system_error>
#include <string_view>
#include <filesystem>
#include <stdexcept>
#include <exception>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <regex>

namespace universaldevkit::cli::details {
	constexpr std::string_view version = UDK_CLI_VERSION;
	constexpr std::wstring_view dispatchedArgument = L"--run-pinned-version";

	std::string ReadVersion(const std::filesystem::path& path) {
		if (!std::filesystem::exists(path)) {
			return {};
		}
		std::ifstream input(path, std::ios::binary);
		std::string value;
		if (!std::getline(input, value, '\0') || !input.eof()) {
			throw std::runtime_error("Cannot read .udk-version or the file is empty.");
		}
		if (value.starts_with("\xEF\xBB\xBF")) {
			value.erase(0, 3);
		}
		const auto start = value.find_first_not_of(" \t\r\n");
		if (start != std::string::npos) {
			value = value.substr(start, value.find_last_not_of(" \t\r\n") - start + 1);
		}
		static const std::regex pattern(R"([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?)");
		if (value.size() > 80 || !std::regex_match(value, pattern)) {
			throw std::runtime_error("Invalid version in .udk-version. Expected a release version such as 0.1.4.");
		}
		return value;
	}

	void WriteVersion(const std::filesystem::path& path, bool replace) {
		wchar_t temporaryPath[MAX_PATH]{};
		if (!::GetTempFileNameW(path.parent_path().c_str(), L"udk", 0, temporaryPath)) {
			throw std::system_error(static_cast<int>(::GetLastError()), std::system_category(), "Cannot stage .udk-version");
		}
		try {
			std::ofstream output(std::filesystem::path{temporaryPath}, std::ios::binary);
			output << version;
			output.close();
			if (!output) {
				throw std::runtime_error("Cannot write .udk-version.");
			}
			if (!::MoveFileExW(temporaryPath, path.c_str(), replace ? MOVEFILE_REPLACE_EXISTING : 0)) {
				throw std::system_error(static_cast<int>(::GetLastError()), std::system_category(), "Cannot save .udk-version");
			}
		} catch (...) {
			::DeleteFileW(temporaryPath);
			throw;
		}
		std::cout << "Pinned UDK CLI " << version << " in .udk-version." << std::endl;
	}

	int RunPinnedVersion(const std::string& pinnedVersion, int argc, wchar_t* argv[]) {
		std::wstring localAppData(32768, L'\0');
		const auto length = ::GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData.data(), static_cast<DWORD>(localAppData.size()));
		if (length == 0 || length >= localAppData.size()) {
			throw std::runtime_error("Cannot resolve LOCALAPPDATA for the UDK CLI version cache.");
		}
		localAppData.resize(length);
		const auto directory = std::filesystem::path(localAppData) / L"UdkCli" / L"versions" / pinnedVersion;
		const auto executable = directory / L"udk.exe";
		const std::wstring requestedVersion(pinnedVersion.begin(), pinnedVersion.end());
		if (!std::filesystem::is_regular_file(executable)) {
			const auto status = cli::RunPowerShellScript(L"InstallVersion.ps1", {requestedVersion, directory.native()});
			if (status != 0) {
				return status;
			}
		}
		std::vector<std::wstring> arguments{std::wstring(dispatchedArgument), requestedVersion};
		arguments.insert(arguments.end(), argv + 1, argv + argc);
		return cli::RunExecutable(executable, arguments);
	}

	int ShowHelp(bool invalidArguments = false) {
		auto& output = invalidArguments ? std::cerr : std::cout;
		output << "version: " UDK_CLI_VERSION "\n\n"
			"Usage:\n"
			"  udk project generate [manifest]\n"
			"  udk project check [manifest]\n"
			"  udk project update [manifest]\n"
			"  udk package build <package-path>\n"
			"  udk package plan <package-path>\n"
			"  udk uninstall\n\n"
			"The default project manifest is Components.json in the current directory.\n"
			"Run package commands from the repository root.\n";
		return invalidArguments ? 2 : 0;
	}

	int RunProject(const std::filesystem::path& path, bool check) {
		std::vector<std::wstring> arguments{L"-ManifestPath", std::filesystem::absolute(path).wstring()};
		if (check) {
			arguments.emplace_back(L"-Check");
		}
		return universaldevkit::cli::RunPowerShellScript(L"ProjectTools/Generate.ps1", arguments);
	}

	int RunRepositoryCommand(int argc, wchar_t* argv[], bool dispatched) {
		if (argc != 3 && argc != 4) {
			return details::ShowHelp(true);
		}
		const std::wstring_view group = argv[1];
		const std::wstring_view command = argv[2];
		const bool project = group == L"project" && (command == L"generate" || command == L"check" || command == L"update");
		const bool package = group == L"package" && (command == L"build" || command == L"plan") && argc == 4;
		if (!project && !package) {
			return details::ShowHelp(true);
		}
		const auto manifest = project ? std::filesystem::absolute(argc == 4 ? argv[3] : L"Components.json") : std::filesystem::path{};
		const auto versionPath = (project ? manifest.parent_path() : std::filesystem::current_path()) / L".udk-version";

		if (project && command == L"update") {
			details::WriteVersion(versionPath, true);
		} else if (!dispatched) {
			const auto pinnedVersion = details::ReadVersion(versionPath);
			if (!pinnedVersion.empty() && pinnedVersion != version) {
				return details::RunPinnedVersion(pinnedVersion, argc, argv);
			}
			if (pinnedVersion.empty() && project && command == L"generate") {
				details::WriteVersion(versionPath, false);
			}
		}
		if (project) {
			return details::RunProject(manifest, command == L"check");
		}
		std::vector<std::wstring> arguments{L"-PackagePath", argv[3]};
		if (command == L"plan") {
			arguments.emplace_back(L"-Plan");
		}
		return cli::RunPowerShellScript(L"PackageTools/Build.ps1", arguments);
	}
}

int wmain(int argc, wchar_t* argv[]) {
	try {
		if (argc == 1 || (argc == 2 && (std::wstring_view(argv[1]) == L"--help" || std::wstring_view(argv[1]) == L"-h"))) {
			return universaldevkit::cli::details::ShowHelp();
		}
		if (argc == 2 && std::wstring_view(argv[1]) == L"uninstall") {
			universaldevkit::cli::LaunchUninstaller();
			return 0;
		}
		if (std::wstring_view(argv[1]) == universaldevkit::cli::details::dispatchedArgument) {
			if (argc < 5 || std::wstring_view(argv[2]) != L"" UDK_CLI_VERSION) {
				throw std::runtime_error("The cached UDK CLI does not match the requested version.");
			}
			return universaldevkit::cli::details::RunRepositoryCommand(argc - 2, argv + 2, true);
		}
		return universaldevkit::cli::details::RunRepositoryCommand(argc, argv, false);
	} catch (const std::exception& exception) {
		std::cerr << "udk: " << exception.what() << '\n';
		return 1;
	}
}