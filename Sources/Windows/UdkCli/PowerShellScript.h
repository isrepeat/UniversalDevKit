#pragma once
#include <filesystem>
#include <string>
#include <vector>

namespace universaldevkit::cli {
	int RunPowerShellScript(const std::filesystem::path& path, const std::vector<std::wstring>& arguments);
	int RunExecutable(const std::filesystem::path& path, const std::vector<std::wstring>& arguments);
	void LaunchUninstaller();
}