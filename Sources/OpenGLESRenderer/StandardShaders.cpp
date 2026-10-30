#include "StandardShaders.h"

namespace universaldevkit::openglesrenderer {
    namespace details {
        // Текстовый pipeline передаёт в шейдер позицию вершины и UV-координаты
        // альфа-канала glyph atlas. Геометрия уже приходит в NDC.
        const char TextVertexShader[] = R"(#version 300 es
        layout (location = 0) in vec2 position;
        layout (location = 1) in vec2 textureCoordinate;
        out vec2 uv;
        void main() {
            uv = textureCoordinate;
            gl_Position = vec4(position, 0.0, 1.0);
        }
    )";

        const char TextFragmentShader[] = R"(#version 300 es
        precision mediump float;
        in vec2 uv;
        uniform sampler2D fontAtlas;
        uniform vec4 textColor;
        out vec4 color;
        void main() {
            float alpha = texture(fontAtlas, uv).r;
            color = vec4(textColor.rgb, textColor.a * alpha);
        }
    )";

        // Программа заливки используется для фона, границ и контуров без текстуры.
        const char SolidVertexShader[] = R"(#version 300 es
        layout (location = 0) in vec2 position;
        void main() {
            gl_Position = vec4(position, 0.0, 1.0);
        }
    )";

        const char SolidFragmentShader[] = R"(#version 300 es
        precision mediump float;
        uniform vec4 color;
        out vec4 fragmentColor;
        void main() {
            fragmentColor = color;
        }
    )";

        // Скругление рассчитывается для прямоугольника из двух треугольников.
        // Это дешевле, чем строить на CPU дуги для каждого угла каждого элемента.
        const char RoundedRectangleVertexShader[] = R"(#version 300 es
        layout (location = 0) in vec2 position;
        layout (location = 1) in vec2 localPosition;
        out vec2 point;
        void main() {
            point = localPosition;
            gl_Position = vec4(position, 0.0, 1.0);
        }
    )";

        const char RoundedRectangleFragmentShader[] = R"(#version 300 es
        precision mediump float;
        in vec2 point;
        uniform vec2 size;
        uniform float radius;
        uniform float borderThickness;
        uniform vec4 color;
        out vec4 fragmentColor;

        float roundedBoxDistance(vec2 localPoint, vec2 boxSize, float cornerRadius) {
            vec2 halfSize = boxSize * 0.5;
            vec2 delta = abs(localPoint - halfSize) - (halfSize - vec2(cornerRadius));
            return length(max(delta, 0.0)) + min(max(delta.x, delta.y), 0.0) - cornerRadius;
        }

        void main() {
            float distance = roundedBoxDistance(point, size, radius);
            float edge = max(fwidth(distance), 0.001);
            float outerAlpha = 1.0 - smoothstep(-edge, edge, distance);
            if (borderThickness <= 0.0) {
                fragmentColor = vec4(color.rgb, color.a * outerAlpha);
                return;
            }
            float innerAlpha = smoothstep(-borderThickness - edge, -borderThickness + edge, distance);
            fragmentColor = vec4(color.rgb, color.a * outerAlpha * innerAlpha);
        }
    )";

        const char ImageVertexShader[] = R"(#version 300 es
        layout (location = 0) in vec2 position;
        layout (location = 1) in vec2 textureCoordinate;
        out vec2 uv;
        void main() { uv = textureCoordinate; gl_Position = vec4(position, 0.0, 1.0); }
    )";
        const char ImageFragmentShader[] = R"(#version 300 es
        precision mediump float;
        in vec2 uv;
        uniform sampler2D imageTexture;
        uniform vec4 tint;
        out vec4 color;
        void main() {
            float alpha = texture(imageTexture, uv).a;
            color = vec4(tint.rgb, tint.a * alpha);
        }
    )";
    }
}