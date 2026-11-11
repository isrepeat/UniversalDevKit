#include "PowerShellScript.h"

#include <string_view>
#include <filesystem>
#include <exception>
#include <iostream>
#include <string>
#include <vector>

namespace universaldevkit::cli::details {
	int ShowHelp(bool invalidArguments = false) {
		auto& output = invalidArguments ? std::cerr : std::cout;
		output << "Usage:\n"
			"  udk project generate [manifest]\n"
			"  udk project check [manifest]\n"
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
		if (argc != 3 && argc != 4) {
			return universaldevkit::cli::details::ShowHelp(true);
		}

		const std::wstring_view group = argv[1];
		const std::wstring_view command = argv[2];
		if (group == L"project" && (command == L"generate" || command == L"check")) {
			return universaldevkit::cli::details::RunProject(argc == 4 ? argv[3] : L"Components.json", command == L"check");
		}
		if (group == L"package" && (command == L"build" || command == L"plan") && argc == 4) {
			std::vector<std::wstring> arguments{L"-PackagePath", argv[3]};
			if (command == L"plan") {
				arguments.emplace_back(L"-Plan");
			}
			return universaldevkit::cli::RunPowerShellScript(L"PackageTools/Build.ps1", arguments);
		}
		return universaldevkit::cli::details::ShowHelp(true);
	} catch (const std::exception& exception) {
		std::cerr << "udk: " << exception.what() << '\n';
		return 1;
	}
}