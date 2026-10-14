#include <Probe.h>

#include <wrl.h>
#include <activation.h>
#include <roapi.h>
#include <winstring.h>

#include <iostream>

int main() {
    if (FAILED(::RoInitialize(RO_INIT_MULTITHREADED))) { return 1; }
    const auto module = ::LoadLibraryW(L"UdkWinRtProbe.dll");
    if (!module) { return 2; }
    const auto getFactory = reinterpret_cast<HRESULT (__stdcall*)(HSTRING, IActivationFactory**)>(
        ::GetProcAddress(module, "DllGetActivationFactory")
    );
    if (!getFactory) { return 3; }
    HSTRING classId = nullptr;
    constexpr wchar_t className[] = L"UniversalDevKit.TestPackages.Probe";
    if (FAILED(::WindowsCreateString(className, _countof(className) - 1, &classId))) { return 4; }
    int result = 1;
    {
        // Проверяем фабрику, создание объекта и вызов интерфейса из DLL пакета.
        Microsoft::WRL::ComPtr<IActivationFactory> factory;
        Microsoft::WRL::ComPtr<IInspectable> instance;
        Microsoft::WRL::ComPtr<IProbe> probe;
        INT32 value = 0;
        if (SUCCEEDED(getFactory(classId, &factory))
            && SUCCEEDED(factory->ActivateInstance(&instance))
            && SUCCEEDED(instance.As(&probe))
            && SUCCEEDED(probe->GetValue(&value)) && value == 42) {
            std::cout << "WinRT package passed\n";
            result = 0;
        }
    }
    ::WindowsDeleteString(classId);
    // DLL остаётся загруженной до завершения процесса.
    ::RoUninitialize();
    return result;
}