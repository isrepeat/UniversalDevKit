#pragma once
#include <inspectable.h>

struct __declspec(uuid("61804DDD-F43C-4990-87B1-C99415254E79")) IProbe : IInspectable {
    virtual HRESULT STDMETHODCALLTYPE GetValue(INT32* value) = 0;
};