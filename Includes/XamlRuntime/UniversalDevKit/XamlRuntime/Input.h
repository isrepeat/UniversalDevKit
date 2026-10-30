#pragma once

#include "XamlLayout.h"

namespace xaml {
    bool IsInteractive(const Element& element);
    Element* HitTest(Element& root, float x, float y);
    Element* HitTestVisual(Element& root, float x, float y);
    bool HandleTap(Element& element);
}