#include "Probe.h"

#include <wrl.h>
#include <activation.h>
#include <winstring.h>

#include <cwchar>

namespace {
    class Probe final : public Microsoft::WRL::RuntimeClass<Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::WinRt>, IProbe> {
        InspectableClass(L"UniversalDevKit.TestPackages.Probe", BaseTrust)
    public:
        HRESULT STDMETHODCALLTYPE GetValue(INT32* value) override {
            if (!value) { return E_POINTER; }
            *value = 42;
            return S_OK;
        }
    };

    class Factory final : public Microsoft::WRL::ActivationFactory<> {
    public:
        HRESULT STDMETHODCALLTYPE GetTrustLevel(TrustLevel* trustLevel) override {
            if (!trustLevel) { return E_POINTER; }
            *trustLevel = BaseTrust;
            return S_OK;
        }

        HRESULT STDMETHODCALLTYPE ActivateInstance(IInspectable** instance) override {
            if (!instance) { return E_POINTER; }
            const auto probe = Microsoft::WRL::Make<Probe>();
            return probe ? probe.CopyTo(instance) : E_OUTOFMEMORY;
        }
    };
}

extern "C" __declspec(dllexport) HRESULT __stdcall DllGetActivationFactory(HSTRING classId, IActivationFactory** activationFactory) {
    if (!activationFactory) { return E_POINTER; }
    *activationFactory = nullptr;
    if (std::wcscmp(::WindowsGetStringRawBuffer(classId, nullptr), L"UniversalDevKit.TestPackages.Probe") != 0) {
        return CLASS_E_CLASSNOTAVAILABLE;
    }
    const auto factory = Microsoft::WRL::Make<Factory>();
    return factory ? factory.CopyTo(activationFactory) : E_OUTOFMEMORY;
}

STDAPI DllCanUnloadNow() {
    // Тестовый компонент остаётся загруженным до завершения процесса.
    return S_FALSE;
}