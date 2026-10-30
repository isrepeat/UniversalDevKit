#define NOMINMAX
#undef DrawText
#include "../../Includes/OpenGLESRenderer/UniversalDevKit/OpenGLESRenderer/OpenGlRenderer.h"

#include <GLES3/gl3.h>
#define STBTT_STATIC
#define STB_TRUETYPE_IMPLEMENTATION
#pragma warning(disable: 4505)
#include "../../ThirdParty/XamlRuntime/stb_truetype.h"
#define NANOSVG_IMPLEMENTATION
#define NANOSVGRAST_IMPLEMENTATION
#include "../../ThirdParty/XamlRuntime/nanosvgrast.h"

#include <UniversalDevKit/Diagnostic/Logging.h>
#include <UniversalDevKit/Helpers/Text/Utf8.h>

#undef DrawText
#include "StandardShaders.h"

#include <unordered_map>
#include <algorithm>
#include <stdexcept>
#include <cstdint>
#include <cstring>
#include <limits>
#include <string>
#include <vector>
#include <array>
#include <cmath>

namespace universaldevkit::openglesrenderer {
    namespace details {
        constexpr int FirstAsciiGlyph = 32;
        constexpr int AsciiGlyphCount = 96;
        constexpr int FirstCyrillicGlyph = 0x0400;
        constexpr int CyrillicGlyphCount = 256;
        constexpr int SettingsGlyph = 0x2699;
        constexpr float AtlasFontSize = 96.0f;
        constexpr int AtlasWidth = 2048;
        constexpr int AtlasHeight = 1024;
        constexpr int MaximumTextGlyphs = 256;

        // Команды runtime хранят текст в UTF-8, а stb_truetype ожидает code point.
        // Повреждённая либо неподдерживаемая последовательность заменяется на '?'.
    } // namespace details

    class OpenGlRenderer::Implementation {
    public:
        Implementation(
            int width,
            int height,
            const unsigned char* regularFontData,
            size_t regularFontSize,
            const unsigned char* boldFontData,
            size_t boldFontSize,
            const unsigned char* blackFontData,
            size_t blackFontSize,
            ShaderProgramSources shaderPrograms,
            ResourceLoader resourceLoader);
        ~Implementation();

        Implementation(const Implementation&) = delete;
        Implementation& operator=(const Implementation&) = delete;

        void BeginFrame() const;
        std::vector<xaml::TextGlyphMetric> TextGlyphMetrics() const;
        void BeginClip(const xaml::Rect& bounds) const;
        void EndClip() const;
        void DrawOutline(const xaml::Rect& bounds, xaml::attr::Color color);
        void DrawRoundedRectangle(
            const xaml::Rect& bounds,
            xaml::attr::Color color,
            float cornerRadius,
            bool outline,
            float thickness);
        void DrawShader(
            std::string_view shaderName,
            const xaml::Rect& bounds,
            std::initializer_list<xaml::ShaderUniform> uniforms);
        void DrawText(
            const xaml::Rect& bounds,
            std::string_view text,
            xaml::attr::Color color,
            float fontSize,
            std::string_view fontWeight,
            xaml::attr::Alignment horizontalAlignment);
        void DrawImage(const xaml::Rect& bounds, std::string_view source, xaml::attr::Color tint);
        void ApplyClip(const xaml::Rect& bounds) const;

    private:
        struct GlyphReference {
            const stbtt_packedchar* glyphs = nullptr;
            int index = 0;
        };

        struct FontAtlas {
            GLuint texture = 0;
            stbtt_packedchar asciiGlyphs[details::AsciiGlyphCount]{};
            stbtt_packedchar cyrillicGlyphs[details::CyrillicGlyphCount]{};
            stbtt_packedchar settingsGlyph[1]{};
        };

        struct SvgTexture {
            GLuint texture = 0;
            int width = 0;
            int height = 0;
        };

        GLuint CompileShader(GLenum type, std::string_view source) const;
        GLuint CreateProgram(
            std::string_view vertexSource,
            std::string_view fragmentSource) const;
        void CreateFontAtlas(const unsigned char* fontData, FontAtlas& fontAtlas);
        void AppendPosition(std::vector<float>& vertices, float x, float y) const;
        void AppendTextVertex(
            std::vector<float>& vertices,
            float x,
            float y,
            float textureX,
            float textureY) const;
        void AppendTextQuad(std::vector<float>& vertices, const stbtt_aligned_quad& quad) const;
        const FontAtlas& GetFontAtlas(std::string_view fontWeight) const;
        GlyphReference GetGlyph(uint32_t codepoint, const FontAtlas& fontAtlas) const;
        SvgTexture GetSvgTexture(std::string_view source);

    private:
        int width;
        int height;
        GLuint textProgram = 0;
        GLuint solidProgram = 0;
        GLint solidColorLocation = -1;
        GLuint roundedRectangleProgram = 0;
        GLint roundedRectangleSizeLocation = -1;
        GLint roundedRectangleRadiusLocation = -1;
        GLint roundedRectangleBorderThicknessLocation = -1;
        GLint roundedRectangleColorLocation = -1;
        std::unordered_map<std::string, GLuint> shaderPrograms;
        mutable std::vector<xaml::Rect> clipStack;
        GLuint imageProgram = 0;
        GLuint vertexBuffer = 0;
        ResourceLoader resourceLoader;
        std::unordered_map<std::string, SvgTexture> imageTextures;
        FontAtlas regularFontAtlas;
        FontAtlas boldFontAtlas;
        FontAtlas blackFontAtlas;
    };

    OpenGlRenderer::Implementation::Implementation(
        int width,
        int height,
        const unsigned char* regularFontData,
        size_t regularFontSize,
        const unsigned char* boldFontData,
        size_t boldFontSize,
        const unsigned char* blackFontData,
        size_t blackFontSize,
        ShaderProgramSources shaderPrograms,
        ResourceLoader resourceLoader)
        : width(width)
        , height(height)
        , resourceLoader(std::move(resourceLoader)) {
        if (width <= 0
            || height <= 0
            || regularFontData == nullptr
            || regularFontSize == 0
            || boldFontData == nullptr
            || boldFontSize == 0
            || blackFontData == nullptr
            || blackFontSize == 0) {
            throw std::invalid_argument("Invalid OpenGL renderer arguments");
        }

        // Стандартная графика работает без программ от хоста. Явная подмена
        // по ключу роли имеет приоритет над встроенным исходником.
        shaderPrograms.try_emplace(ShaderRoles::text,
            ShaderProgramSource{details::TextVertexShader, details::TextFragmentShader});
        shaderPrograms.try_emplace(ShaderRoles::solid,
            ShaderProgramSource{details::SolidVertexShader, details::SolidFragmentShader});
        shaderPrograms.try_emplace(ShaderRoles::roundedRectangle,
            ShaderProgramSource{
                details::RoundedRectangleVertexShader,
                details::RoundedRectangleFragmentShader,
            });
        shaderPrograms.try_emplace(ShaderRoles::image,
            ShaderProgramSource{details::ImageVertexShader, details::ImageFragmentShader});
        for (const auto& [name, source] : shaderPrograms) {
            if (name.empty() || source.vertex.empty() || source.fragment.empty()) {
                throw std::invalid_argument("Invalid OpenGL shader program source");
            }
        }
        for (const auto& [name, source] : shaderPrograms) {
            this->shaderPrograms.emplace(name, this->CreateProgram(source.vertex, source.fragment));
        }
        this->textProgram = this->shaderPrograms.at(ShaderRoles::text);
        this->solidProgram = this->shaderPrograms.at(ShaderRoles::solid);
        this->solidColorLocation = glGetUniformLocation(this->solidProgram, "color");
        this->roundedRectangleProgram = this->shaderPrograms.at(ShaderRoles::roundedRectangle);
        this->imageProgram = this->shaderPrograms.at(ShaderRoles::image);
        this->roundedRectangleSizeLocation = glGetUniformLocation(
            this->roundedRectangleProgram,
            "size");
        this->roundedRectangleRadiusLocation = glGetUniformLocation(
            this->roundedRectangleProgram,
            "radius");
        this->roundedRectangleBorderThicknessLocation = glGetUniformLocation(
            this->roundedRectangleProgram,
            "borderThickness");
        this->roundedRectangleColorLocation = glGetUniformLocation(
            this->roundedRectangleProgram,
            "color");
        glGenBuffers(1, &this->vertexBuffer);
        this->CreateFontAtlas(regularFontData, this->regularFontAtlas);
        this->CreateFontAtlas(boldFontData, this->boldFontAtlas);
        this->CreateFontAtlas(blackFontData, this->blackFontAtlas);
        UDK_LOG_INFO(
            "OpenGlRenderer",
            "Initialized: viewport={}x{}, regularFontBytes={}, boldFontBytes={}, blackFontBytes={}",
            width,
            height,
            regularFontSize,
            boldFontSize,
            blackFontSize);
    }

    OpenGlRenderer::Implementation::~Implementation() {
        if (this->regularFontAtlas.texture != 0) {
            glDeleteTextures(1, &this->regularFontAtlas.texture);
        }
        if (this->boldFontAtlas.texture != 0) {
            glDeleteTextures(1, &this->boldFontAtlas.texture);
        }
        if (this->blackFontAtlas.texture != 0) {
            glDeleteTextures(1, &this->blackFontAtlas.texture);
        }
        for (const auto& [source, texture] : this->imageTextures) {
            glDeleteTextures(1, &texture.texture);
        }
        for (const auto& [name, program] : this->shaderPrograms) {
            glDeleteProgram(program);
        }
        if (this->vertexBuffer != 0) {
            glDeleteBuffers(1, &this->vertexBuffer);
        }
    }

    void OpenGlRenderer::Implementation::BeginFrame() const {
        glViewport(0, 0, this->width, this->height);
        glDisable(GL_SCISSOR_TEST);
        this->clipStack.clear();
        glEnable(GL_BLEND);
        // Шейдеры возвращают straight alpha, а поверхность Android ожидает
        // premultiplied RGB. Альфа накапливается отдельно, без повторного умножения.
        glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT);
    }

    GLuint OpenGlRenderer::Implementation::CompileShader(
        GLenum type,
        std::string_view source) const {
        const GLuint shader = glCreateShader(type);
        const char* const sourceData = source.data();
        const GLint sourceLength = static_cast<GLint>(source.size());
        glShaderSource(shader, 1, &sourceData, &sourceLength);
        glCompileShader(shader);
        GLint compiled = GL_FALSE;
        glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
        if (compiled == GL_FALSE) {
            GLint logLength = 0;
            glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
            std::string log(static_cast<size_t>(std::max(1, logLength)), '\0');
            glGetShaderInfoLog(shader, logLength, nullptr, log.data());
            glDeleteShader(shader);
            UDK_LOG_ERROR("OpenGlRenderer", "Shader compilation failed: {}", log);
            throw std::runtime_error("ANGLE shader compilation failed: " + log);
        }
        return shader;
    }

    GLuint OpenGlRenderer::Implementation::CreateProgram(
        std::string_view vertexSource,
        std::string_view fragmentSource) const {
        const GLuint vertexShader = this->CompileShader(GL_VERTEX_SHADER, vertexSource);
        const GLuint fragmentShader = this->CompileShader(GL_FRAGMENT_SHADER, fragmentSource);
        const GLuint program = glCreateProgram();
        glAttachShader(program, vertexShader);
        glAttachShader(program, fragmentShader);
        glLinkProgram(program);
        glDeleteShader(vertexShader);
        glDeleteShader(fragmentShader);
        GLint linked = GL_FALSE;
        glGetProgramiv(program, GL_LINK_STATUS, &linked);
        if (linked == GL_FALSE) {
            GLint logLength = 0;
            glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
            std::string log(static_cast<size_t>(std::max(1, logLength)), '\0');
            glGetProgramInfoLog(program, logLength, nullptr, log.data());
            glDeleteProgram(program);
            UDK_LOG_ERROR("OpenGlRenderer", "Shader program linking failed: {}", log);
            throw std::runtime_error("ANGLE program linking failed: " + log);
        }
        return program;
    }

    void OpenGlRenderer::Implementation::CreateFontAtlas(
        const unsigned char* fontData,
        FontAtlas& fontAtlas) {
        // Один atlas покрывает ASCII, кириллицу и значок настроек из тестовой разметки.
        std::vector<unsigned char> atlas(details::AtlasWidth * details::AtlasHeight, 0);
        stbtt_pack_context packingContext{};
        const int packingStarted = stbtt_PackBegin(
            &packingContext,
            atlas.data(),
            details::AtlasWidth,
            details::AtlasHeight,
            0,
            1,
            nullptr);
        const int asciiPacked = packingStarted == 0 ? 0 : stbtt_PackFontRange(
            &packingContext,
            fontData,
            0,
            details::AtlasFontSize,
            details::FirstAsciiGlyph,
            details::AsciiGlyphCount,
            fontAtlas.asciiGlyphs);
        const int cyrillicPacked = asciiPacked == 0 ? 0 : stbtt_PackFontRange(
            &packingContext,
            fontData,
            0,
            details::AtlasFontSize,
            details::FirstCyrillicGlyph,
            details::CyrillicGlyphCount,
            fontAtlas.cyrillicGlyphs);
        const int settingsPacked = cyrillicPacked == 0 ? 0 : stbtt_PackFontRange(
            &packingContext,
            fontData,
            0,
            details::AtlasFontSize,
            details::SettingsGlyph,
            1,
            fontAtlas.settingsGlyph);
        if (packingStarted != 0) {
            stbtt_PackEnd(&packingContext);
        }
        if (asciiPacked == 0 || cyrillicPacked == 0 || settingsPacked == 0) {
            throw std::runtime_error("ANGLE renderer font atlas is too small");
        }

        glGenTextures(1, &fontAtlas.texture);
        glBindTexture(GL_TEXTURE_2D, fontAtlas.texture);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(
            GL_TEXTURE_2D,
            0,
            GL_R8,
            details::AtlasWidth,
            details::AtlasHeight,
            0,
            GL_RED,
            GL_UNSIGNED_BYTE,
            atlas.data());
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        UDK_LOG_DEBUG(
            "OpenGlRenderer",
            "Font atlas created: {}x{}",
            details::AtlasWidth,
            details::AtlasHeight);
    }

    void OpenGlRenderer::Implementation::EndClip() const {
        if (this->clipStack.empty()) {
            return;
        }
        this->clipStack.pop_back();
        if (this->clipStack.empty()) {
            glDisable(GL_SCISSOR_TEST);
            return;
        }
        this->ApplyClip(this->clipStack.back());
    }

    void OpenGlRenderer::Implementation::DrawOutline(
        const xaml::Rect& bounds,
        xaml::attr::Color color) {
        std::vector<float> vertices;
        vertices.reserve(8);
        this->AppendPosition(vertices, bounds.x, bounds.y);
        this->AppendPosition(vertices, bounds.x + bounds.width, bounds.y);
        this->AppendPosition(
            vertices,
            bounds.x + bounds.width,
            bounds.y + bounds.height);
        this->AppendPosition(vertices, bounds.x, bounds.y + bounds.height);

        glUseProgram(this->solidProgram);
        glUniform4f(
            this->solidColorLocation,
            color.red,
            color.green,
            color.blue,
            color.alpha);
        glBindBuffer(GL_ARRAY_BUFFER, this->vertexBuffer);
        glBufferData(
            GL_ARRAY_BUFFER,
            static_cast<GLsizeiptr>(vertices.size() * sizeof(float)),
            vertices.data(),
            GL_DYNAMIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), nullptr);
        glLineWidth(2.0f);
        glDrawArrays(GL_LINE_LOOP, 0, 4);
    }

    void OpenGlRenderer::Implementation::DrawRoundedRectangle(
        const xaml::Rect& bounds,
        xaml::attr::Color color,
        float cornerRadius,
        bool outline,
        float thickness) {
        // Радиус ограничивается половиной каждой стороны: иначе дуги углов
        // пересекаются на очень узких прямоугольниках.
        const float maximumRadius = std::max(
            0.0f,
            std::min(bounds.width / 2.0f, bounds.height / 2.0f));
        const float radius = std::clamp(cornerRadius, 0.0f, maximumRadius);
        const float borderThickness = std::clamp(thickness, 0.0f, maximumRadius);
        if (outline && borderThickness <= 0.0f) {
            return;
        }
        // Заливка прямоугольника без скругления не требует shader-пути. Контур
        // всё же рисуем шейдером: GL_LINE_LOOP не гарантирует заданную ширину
        // линии в ANGLE и даёт другой результат, чем скруглённая рамка.
        if (radius == 0.0f && !outline) {
            const std::array<float, 8> vertices{
                bounds.x * 2.0f / this->width - 1.0f,
                1.0f - bounds.y * 2.0f / this->height,
                (bounds.x + bounds.width) * 2.0f / this->width - 1.0f,
                1.0f - bounds.y * 2.0f / this->height,
                (bounds.x + bounds.width) * 2.0f / this->width - 1.0f,
                1.0f - (bounds.y + bounds.height) * 2.0f / this->height,
                bounds.x * 2.0f / this->width - 1.0f,
                1.0f - (bounds.y + bounds.height) * 2.0f / this->height,
            };
            glUseProgram(this->solidProgram);
            glUniform4f(
                this->solidColorLocation,
                color.red,
                color.green,
                color.blue,
                color.alpha);
            glBindBuffer(GL_ARRAY_BUFFER, this->vertexBuffer);
            glBufferData(
                GL_ARRAY_BUFFER,
                static_cast<GLsizeiptr>(vertices.size() * sizeof(float)),
                vertices.data(),
                GL_DYNAMIC_DRAW);
            glEnableVertexAttribArray(0);
            glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), nullptr);
            glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
            return;
        }
        const std::array<float, 24> vertices{
            bounds.x * 2.0f / this->width - 1.0f, 1.0f - bounds.y * 2.0f / this->height, 0.0f, 0.0f,
            (bounds.x + bounds.width) * 2.0f / this->width - 1.0f, 1.0f - bounds.y * 2.0f / this->height, bounds.width, 0.0f,
            (bounds.x + bounds.width) * 2.0f / this->width - 1.0f, 1.0f - (bounds.y + bounds.height) * 2.0f / this->height, bounds.width, bounds.height,
            bounds.x * 2.0f / this->width - 1.0f, 1.0f - bounds.y * 2.0f / this->height, 0.0f, 0.0f,
            (bounds.x + bounds.width) * 2.0f / this->width - 1.0f, 1.0f - (bounds.y + bounds.height) * 2.0f / this->height, bounds.width, bounds.height,
            bounds.x * 2.0f / this->width - 1.0f, 1.0f - (bounds.y + bounds.height) * 2.0f / this->height, 0.0f, bounds.height,
        };
        glUseProgram(this->roundedRectangleProgram);
        glUniform2f(
            this->roundedRectangleSizeLocation,
            bounds.width,
            bounds.height);
        glUniform1f(
            this->roundedRectangleRadiusLocation,
            radius);
        glUniform1f(
            this->roundedRectangleBorderThicknessLocation,
            outline ? borderThickness : 0.0f);
        glUniform4f(
            this->roundedRectangleColorLocation,
            color.red,
            color.green,
            color.blue,
            color.alpha);
        glBindBuffer(GL_ARRAY_BUFFER, this->vertexBuffer);
        glBufferData(
            GL_ARRAY_BUFFER,
            static_cast<GLsizeiptr>(vertices.size() * sizeof(float)),
            vertices.data(),
            GL_DYNAMIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), nullptr);
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(
            1,
            2,
            GL_FLOAT,
            GL_FALSE,
            4 * sizeof(float),
            reinterpret_cast<void*>(2 * sizeof(float)));
        glDrawArrays(GL_TRIANGLES, 0, 6);
    }

    void OpenGlRenderer::Implementation::DrawShader(
        std::string_view shaderName,
        const xaml::Rect& bounds,
        std::initializer_list<xaml::ShaderUniform> uniforms) {
        const auto found = this->shaderPrograms.find(std::string(shaderName));
        if (found == this->shaderPrograms.end()) {
            UDK_LOG_ERROR("OpenGlRenderer", "Shader program is not registered: {}", shaderName);
            return;
        }
        const GLuint program = found->second;
        const std::vector<float> vertices{
            bounds.x * 2.0f / this->width - 1.0f, 1.0f - bounds.y * 2.0f / this->height, 0.0f, 0.0f,
            (bounds.x + bounds.width) * 2.0f / this->width - 1.0f, 1.0f - bounds.y * 2.0f / this->height, 1.0f, 0.0f,
            (bounds.x + bounds.width) * 2.0f / this->width - 1.0f, 1.0f - (bounds.y + bounds.height) * 2.0f / this->height, 1.0f, 1.0f,
            bounds.x * 2.0f / this->width - 1.0f, 1.0f - bounds.y * 2.0f / this->height, 0.0f, 0.0f,
            (bounds.x + bounds.width) * 2.0f / this->width - 1.0f, 1.0f - (bounds.y + bounds.height) * 2.0f / this->height, 1.0f, 1.0f,
            bounds.x * 2.0f / this->width - 1.0f, 1.0f - (bounds.y + bounds.height) * 2.0f / this->height, 0.0f, 1.0f,
        };
        glUseProgram(program);
        glUniform2f(
            glGetUniformLocation(program, "size"),
            bounds.width,
            bounds.height);
        for (const xaml::ShaderUniform& uniform : uniforms) {
            const GLint location = glGetUniformLocation(program, uniform.name.data());
            if (location < 0) {
                continue;
            }
            if (uniform.valueCount == 1) {
                glUniform1f(location, uniform.values[0]);
            }
            else if (uniform.valueCount == 2) {
                glUniform2f(location, uniform.values[0], uniform.values[1]);
            }
            else if (uniform.valueCount == 3) {
                glUniform3f(location, uniform.values[0], uniform.values[1], uniform.values[2]);
            }
            else if (uniform.valueCount == 4) {
                glUniform4f(location, uniform.values[0], uniform.values[1], uniform.values[2], uniform.values[3]);
            }
        }
        glBindBuffer(GL_ARRAY_BUFFER, this->vertexBuffer);
        glBufferData(
            GL_ARRAY_BUFFER,
            static_cast<GLsizeiptr>(vertices.size() * sizeof(float)),
            vertices.data(),
            GL_DYNAMIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), nullptr);
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(
            1,
            2,
            GL_FLOAT,
            GL_FALSE,
            4 * sizeof(float),
            reinterpret_cast<void*>(2 * sizeof(float)));
        glDrawArrays(GL_TRIANGLES, 0, 6);
    }

    void OpenGlRenderer::Implementation::DrawText(
        const xaml::Rect& bounds,
        std::string_view text,
        xaml::attr::Color color,
        float fontSize,
        std::string_view fontWeight,
        xaml::attr::Alignment horizontalAlignment) {
        if (text.empty()) {
            return;
        }
        const FontAtlas& fontAtlas = this->GetFontAtlas(fontWeight);
        // stb_truetype выдаёт метрики для размера atlas; scale переводит их
        // обратно в fontSize, заданный XAML-командой.
        const float scale = fontSize / details::AtlasFontSize;
        float textWidth = 0.0f;
        float minimumY = std::numeric_limits<float>::max();
        float maximumY = std::numeric_limits<float>::lowest();
        int glyphCount = 0;
        const char* current = text.data();
        const char* const end = text.data() + text.size();
        while (current < end && glyphCount < details::MaximumTextGlyphs) {
            const GlyphReference reference = this->GetGlyph(
                universaldevkit::helpers::text::Utf8::Next(current, end, '?'),
                fontAtlas);
            const stbtt_packedchar& glyph = reference.glyphs[reference.index];
            textWidth += glyph.xadvance * scale;
            minimumY = std::min(minimumY, glyph.yoff * scale);
            maximumY = std::max(maximumY, glyph.yoff2 * scale);
            ++glyphCount;
        }

        // Первый проход собрал метрики всей строки. Теперь выравниваем её в
        // bounds и вторым проходом формируем по два треугольника на glyph.
        float cursorX = bounds.x / scale;
        if (horizontalAlignment == xaml::attr::Alignment::center) {
            cursorX = (bounds.x + (bounds.width - textWidth) * 0.5f) / scale;
        }
        else if (horizontalAlignment == xaml::attr::Alignment::right) {
            cursorX = (bounds.x + bounds.width - textWidth) / scale;
        }
        float cursorY = (
            bounds.y
            + (bounds.height - (maximumY - minimumY)) * 0.5f
            - minimumY) / scale;
        std::vector<float> vertices;
        vertices.reserve(static_cast<size_t>(glyphCount) * 6 * 4);
        current = text.data();
        int renderedGlyphs = 0;
        while (current < end && renderedGlyphs < details::MaximumTextGlyphs) {
            const GlyphReference reference = this->GetGlyph(
                universaldevkit::helpers::text::Utf8::Next(current, end, '?'),
                fontAtlas);
            stbtt_aligned_quad quad{};
            stbtt_GetPackedQuad(
                reference.glyphs,
                details::AtlasWidth,
                details::AtlasHeight,
                reference.index,
                &cursorX,
                &cursorY,
                &quad,
                1);
            quad.x0 *= scale;
            quad.x1 *= scale;
            quad.y0 *= scale;
            quad.y1 *= scale;
            this->AppendTextQuad(vertices, quad);
            ++renderedGlyphs;
        }

        glUseProgram(this->textProgram);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, fontAtlas.texture);
        glUniform1i(glGetUniformLocation(this->textProgram, "fontAtlas"), 0);
        glUniform4f(
            glGetUniformLocation(this->textProgram, "textColor"),
            color.red,
            color.green,
            color.blue,
            color.alpha);
        glBindBuffer(GL_ARRAY_BUFFER, this->vertexBuffer);
        glBufferData(
            GL_ARRAY_BUFFER,
            static_cast<GLsizeiptr>(vertices.size() * sizeof(float)),
            vertices.data(),
            GL_DYNAMIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), nullptr);
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(
            1,
            2,
            GL_FLOAT,
            GL_FALSE,
            4 * sizeof(float),
            reinterpret_cast<void*>(2 * sizeof(float)));
        glDrawArrays(GL_TRIANGLES, 0, static_cast<GLsizei>(vertices.size() / 4));
    }

    OpenGlRenderer::Implementation::SvgTexture OpenGlRenderer::Implementation::GetSvgTexture(std::string_view source) {
        const auto found = this->imageTextures.find(std::string(source));
        if (found != this->imageTextures.end()) {
            return found->second;
        }
        if (!this->resourceLoader) {
            return {};
        }
        std::vector<unsigned char> file;
        try {
            file = this->resourceLoader(source);
        } catch (...) {
            return {};
        }
        if (file.empty()) {
            return {};
        }
        file.push_back('\0');
        NSVGimage* image = nsvgParse(reinterpret_cast<char*>(file.data()), "px", 96.0f);
        if (image == nullptr || image->width <= 0.0f || image->height <= 0.0f) {
            nsvgDelete(image);
            return {};
        }
        constexpr int maximumTextureSize = 128;
        const float scale = universaldevkit::helpers::math::Geometry::FitScale({image->width, image->height}, {maximumTextureSize, maximumTextureSize});
        const int textureWidth = std::max(1, static_cast<int>(std::ceil(image->width * scale)));
        const int textureHeight = std::max(1, static_cast<int>(std::ceil(image->height * scale)));
        std::vector<unsigned char> pixels(textureWidth * textureHeight * 4, 0);
        NSVGrasterizer* rasterizer = nsvgCreateRasterizer();
        if (rasterizer == nullptr) {
            nsvgDelete(image);
            return {};
        }
        nsvgRasterize(
            rasterizer,
            image,
            0.0f,
            0.0f,
            scale,
            pixels.data(),
            textureWidth,
            textureHeight,
            textureWidth * 4);
        nsvgDeleteRasterizer(rasterizer);
        nsvgDelete(image);
        GLuint texture = 0;
        glGenTextures(1, &texture);
        glBindTexture(GL_TEXTURE_2D, texture);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(
            GL_TEXTURE_2D,
            0,
            GL_RGBA,
            textureWidth,
            textureHeight,
            0,
            GL_RGBA,
            GL_UNSIGNED_BYTE,
            pixels.data());
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        const SvgTexture result{texture, textureWidth, textureHeight};
        this->imageTextures.emplace(source, result);
        UDK_LOG_DEBUG(
            "OpenGlRenderer",
            "SVG texture loaded: source='{}', texture={}",
            source,
            texture);
        return result;
    }

    void OpenGlRenderer::Implementation::DrawImage(
        const xaml::Rect& bounds,
        std::string_view source,
        xaml::attr::Color tint) {
        const SvgTexture texture = this->GetSvgTexture(source);
        if (texture.texture == 0) {
            this->DrawOutline(bounds, tint);
            this->DrawText(
                bounds,
                "SVG",
                tint,
                std::max(6.0f, bounds.height * 0.3f),
                "Bold",
                xaml::attr::Alignment::center);
            return;
        }
        std::vector<float> vertices;
        vertices.reserve(24);
        const float scale = universaldevkit::helpers::math::Geometry::FitScale({static_cast<float>(texture.width), static_cast<float>(texture.height)}, {bounds.width, bounds.height});
        const float imageWidth = static_cast<float>(texture.width) * scale;
        const float imageHeight = static_cast<float>(texture.height) * scale;
        const float left = bounds.x + (bounds.width - imageWidth) / 2.0f;
        const float right = left + imageWidth;
        const float top = bounds.y + (bounds.height - imageHeight) / 2.0f;
        const float bottom = top + imageHeight;
        this->AppendTextVertex(vertices, left, top, 0.0f, 1.0f);
        this->AppendTextVertex(vertices, right, top, 1.0f, 1.0f);
        this->AppendTextVertex(vertices, right, bottom, 1.0f, 0.0f);
        this->AppendTextVertex(vertices, left, top, 0.0f, 1.0f);
        this->AppendTextVertex(vertices, right, bottom, 1.0f, 0.0f);
        this->AppendTextVertex(vertices, left, bottom, 0.0f, 0.0f);
        glUseProgram(this->imageProgram);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, texture.texture);
        glUniform1i(glGetUniformLocation(this->imageProgram, "imageTexture"), 0);
        glUniform4f(glGetUniformLocation(this->imageProgram, "tint"), tint.red, tint.green, tint.blue, tint.alpha);
        glBindBuffer(GL_ARRAY_BUFFER, this->vertexBuffer);
        glBufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(vertices.size() * sizeof(float)), vertices.data(), GL_DYNAMIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), nullptr);
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), reinterpret_cast<void*>(2 * sizeof(float)));
        glDrawArrays(GL_TRIANGLES, 0, 6);
    }

    void OpenGlRenderer::Implementation::BeginClip(const xaml::Rect& bounds) const {
        xaml::Rect clipped = bounds;
        if (!this->clipStack.empty()) {
            const xaml::Rect& parent = this->clipStack.back();
            clipped = universaldevkit::helpers::math::Geometry::Intersect(parent, clipped);
        }
        this->clipStack.push_back(clipped);
        this->ApplyClip(clipped);
    }

    void OpenGlRenderer::Implementation::ApplyClip(const xaml::Rect& bounds) const {
        // Пустое пересечение должно оставаться пустым: floor/ceil дробной
        // координаты иначе превращают нулевой размер в полосу из одного пикселя.
        if (bounds.width <= 0.0f || bounds.height <= 0.0f) {
            glEnable(GL_SCISSOR_TEST);
            glScissor(0, 0, 0, 0);
            return;
        }
        // Координаты XAML отсчитываются сверху, тогда как glScissor — снизу.
        // Поэтому вертикальные границы инвертируются перед включением scissor.
        const auto pixels = universaldevkit::helpers::math::Geometry::Intersect(
            universaldevkit::helpers::math::Geometry::RoundOut(bounds),
            universaldevkit::helpers::math::Bounds<int>{0, 0, this->width, this->height});
        glEnable(GL_SCISSOR_TEST);
        glScissor(pixels.x, this->height - pixels.y - pixels.height, pixels.width, pixels.height);
    }

    void OpenGlRenderer::Implementation::AppendPosition(
        std::vector<float>& vertices,
        float x,
        float y) const {
        // Преобразуем пиксельные координаты XAML в normalized device coordinates.
        vertices.push_back(x * 2.0f / this->width - 1.0f);
        vertices.push_back(1.0f - y * 2.0f / this->height);
    }

    void OpenGlRenderer::Implementation::AppendTextVertex(
        std::vector<float>& vertices,
        float x,
        float y,
        float textureX,
        float textureY) const {
        this->AppendPosition(vertices, x, y);
        vertices.push_back(textureX);
        vertices.push_back(textureY);
    }

    void OpenGlRenderer::Implementation::AppendTextQuad(
        std::vector<float>& vertices,
        const stbtt_aligned_quad& quad) const {
        this->AppendTextVertex(vertices, quad.x0, quad.y0, quad.s0, quad.t0);
        this->AppendTextVertex(vertices, quad.x1, quad.y0, quad.s1, quad.t0);
        this->AppendTextVertex(vertices, quad.x1, quad.y1, quad.s1, quad.t1);
        this->AppendTextVertex(vertices, quad.x0, quad.y0, quad.s0, quad.t0);
        this->AppendTextVertex(vertices, quad.x1, quad.y1, quad.s1, quad.t1);
        this->AppendTextVertex(vertices, quad.x0, quad.y1, quad.s0, quad.t1);
    }

    const OpenGlRenderer::Implementation::FontAtlas&
    OpenGlRenderer::Implementation::GetFontAtlas(std::string_view fontWeight) const {
        if (fontWeight == "ExtraBold" || fontWeight == "Black") {
            return this->blackFontAtlas;
        }
        if (fontWeight == "SemiBold" || fontWeight == "Bold") {
            return this->boldFontAtlas;
        }
        return this->regularFontAtlas;
    }

    std::vector<xaml::TextGlyphMetric> OpenGlRenderer::Implementation::TextGlyphMetrics() const {
        std::vector<xaml::TextGlyphMetric> result;
        result.reserve(3 * (details::AsciiGlyphCount + details::CyrillicGlyphCount + 1));
        const auto append = [&result](std::string_view fontWeight, const FontAtlas& fontAtlas) {
            const auto appendRange = [&result, fontWeight](uint32_t firstCodepoint, const auto& glyphs) {
                for (size_t index = 0; index < std::size(glyphs); ++index) {
                    const stbtt_packedchar& glyph = glyphs[index];
                    result.push_back({
                        std::string(fontWeight),
                        firstCodepoint + static_cast<uint32_t>(index),
                        glyph.yoff / details::AtlasFontSize,
                        glyph.yoff2 / details::AtlasFontSize,
                    });
                }
            };
            appendRange(details::FirstAsciiGlyph, fontAtlas.asciiGlyphs);
            appendRange(details::FirstCyrillicGlyph, fontAtlas.cyrillicGlyphs);
            appendRange(details::SettingsGlyph, fontAtlas.settingsGlyph);
        };
        append("Normal", this->regularFontAtlas);
        append("Bold", this->boldFontAtlas);
        append("Black", this->blackFontAtlas);
        return result;
    }

    OpenGlRenderer::Implementation::GlyphReference
    OpenGlRenderer::Implementation::GetGlyph(
        uint32_t codepoint,
        const FontAtlas& fontAtlas) const {
        if (codepoint >= details::FirstAsciiGlyph
            && codepoint < details::FirstAsciiGlyph + details::AsciiGlyphCount) {
            return {
                fontAtlas.asciiGlyphs,
                static_cast<int>(codepoint) - details::FirstAsciiGlyph,
            };
        }
        if (codepoint >= details::FirstCyrillicGlyph
            && codepoint < details::FirstCyrillicGlyph + details::CyrillicGlyphCount) {
            return {
                fontAtlas.cyrillicGlyphs,
                static_cast<int>(codepoint) - details::FirstCyrillicGlyph,
            };
        }
        if (codepoint == details::SettingsGlyph) {
            return {fontAtlas.settingsGlyph, 0};
        }
        return {fontAtlas.asciiGlyphs, '?' - details::FirstAsciiGlyph};
    }

    OpenGlRenderer::OpenGlRenderer(
        int width,
        int height,
        const unsigned char* regularFontData,
        size_t regularFontSize,
        const unsigned char* boldFontData,
        size_t boldFontSize,
        const unsigned char* blackFontData,
        size_t blackFontSize,
        ShaderProgramSources shaderPrograms,
        ResourceLoader resourceLoader)
        : implementation(std::make_unique<Implementation>(
            width,
            height,
            regularFontData,
            regularFontSize,
            boldFontData,
            boldFontSize,
            blackFontData,
            blackFontSize,
            std::move(shaderPrograms),
            std::move(resourceLoader))) {
    }

    OpenGlRenderer::~OpenGlRenderer() = default;

    std::vector<xaml::TextGlyphMetric> OpenGlRenderer::TextGlyphMetrics() const {
        return this->implementation->TextGlyphMetrics();
    }

    //
    // API
    //
    void OpenGlRenderer::BeginFrame() {
        this->implementation->BeginFrame();
    }

    //
    // IRenderBackend
    //
    void OpenGlRenderer::BeginClip(const xaml::Rect& bounds) {
        this->implementation->BeginClip(bounds);
    }

    void OpenGlRenderer::EndClip() {
        this->implementation->EndClip();
    }

    void OpenGlRenderer::DrawOutline(const xaml::Rect& bounds, xaml::attr::Color color) {
        this->implementation->DrawOutline(bounds, color);
    }

    void OpenGlRenderer::DrawRoundedRect(
        const xaml::Rect& bounds,
        xaml::attr::Color color,
        float cornerRadius) {
        this->implementation->DrawRoundedRectangle(
            bounds,
            color,
            cornerRadius,
            false,
            1.0f);
    }

    void OpenGlRenderer::DrawRoundedRectOutline(
        const xaml::Rect& bounds,
        xaml::attr::Color color,
        float cornerRadius,
        float thickness) {
        this->implementation->DrawRoundedRectangle(
            bounds,
            color,
            cornerRadius,
            true,
            thickness);
    }

    void OpenGlRenderer::DrawShader(
        std::string_view shaderName,
        const xaml::Rect& bounds,
        std::initializer_list<xaml::ShaderUniform> uniforms) {
        this->implementation->DrawShader(shaderName, bounds, uniforms);
    }

    void OpenGlRenderer::DrawText(
        const xaml::Rect& bounds,
        std::string_view text,
        xaml::attr::Color color,
        float fontSize,
        std::string_view fontWeight,
        xaml::attr::Alignment horizontalAlignment) {
        this->implementation->DrawText(
            bounds,
            text,
            color,
            fontSize,
            fontWeight,
            horizontalAlignment);
    }

    void OpenGlRenderer::DrawImage(
        const xaml::Rect& bounds,
        std::string_view source,
        xaml::attr::Color tint) {
        this->implementation->DrawImage(bounds, source, tint);
    }
}