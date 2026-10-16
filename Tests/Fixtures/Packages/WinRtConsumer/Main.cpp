#include <winrt/UniversalDevKit.TestPackages.h>

#include <iostream>

int main() {
    try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        // Штатная активация использует манифест EXE и DLL из восстановленного пакета.
        const winrt::UniversalDevKit::TestPackages::Probe probe;
        if (probe.GetValue() != 42) { return 1; }
        std::cout << "Native Desktop WinRT activation passed\n";
        return 0;
    }
    catch (const winrt::hresult_error& error) {
        std::cerr << "WinRT activation failed: " << error.code().value << '\n';
        return 2;
    }
}