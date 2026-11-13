#pragma once
#include <UniversalDevKit/OpenGLESRenderer/Config.h>

namespace universaldevkit::openglesrenderer {
    namespace details {
        // Built-in GLSL programs for basic rendering.
        extern const char TextVertexShader[];
        extern const char TextFragmentShader[];
        extern const char SolidVertexShader[];
        extern const char SolidFragmentShader[];
        extern const char RoundedRectangleVertexShader[];
        extern const char RoundedRectangleFragmentShader[];
        extern const char ImageVertexShader[];
        extern const char ImageFragmentShader[];
    }
}