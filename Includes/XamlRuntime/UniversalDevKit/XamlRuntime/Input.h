#pragma once
#include "XamlLayout.h"
#include "Config.h"
#include "Export.h"

namespace universaldevkit::xamlruntime {
    UNIVERSALDEVKIT_XAMLRUNTIME_API bool IsInteractive(const Element& element);
    UNIVERSALDEVKIT_XAMLRUNTIME_API Element* HitTest(Element& root, float x, float y);
    UNIVERSALDEVKIT_XAMLRUNTIME_API Element* HitTestVisual(Element& root, float x, float y);
    UNIVERSALDEVKIT_XAMLRUNTIME_API bool HandleTap(Element& element);
}