#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/XamlLayout.h"

#include <UniversalDevKit/Diagnostic/Logging.h>
#include <UniversalDevKit/Helpers/Text/Utf8.h>

#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/Binding.h"

#include <algorithm>
#include <sstream>
#include <cctype>
#include <limits>

namespace universaldevkit::xamlruntime {
    namespace details {
        std::vector<TextGlyphMetric> textGlyphMetrics;

        size_t utf8Length(const std::string& text) {
            return universaldevkit::helpers::text::Utf8::Length(text);
        }

        float textHeight(const Element& element) {
            const std::string_view fontWeight = element.FontWeight() == "ExtraBold" || element.FontWeight() == "Black"
                ? "Black"
                : element.FontWeight() == "SemiBold" || element.FontWeight() == "Bold" ? "Bold" : "Normal";
            const auto glyphFor = [fontWeight](uint32_t codepoint) -> const TextGlyphMetric* {
                const auto found = std::find_if(textGlyphMetrics.begin(), textGlyphMetrics.end(),
                    [fontWeight, codepoint](const TextGlyphMetric& glyph) {
                        return glyph.fontWeight == fontWeight && glyph.codepoint == codepoint;
                    });
                return found == textGlyphMetrics.end() ? nullptr : &*found;
            };

            float top = std::numeric_limits<float>::max();
            float bottom = std::numeric_limits<float>::lowest();
            const char* current = element.Text().data();
            const char* const end = current + element.Text().size();
            while (current < end) {
                const TextGlyphMetric* const glyph = glyphFor(universaldevkit::helpers::text::Utf8::Next(current, end, '?'));
                if (glyph == nullptr) {
                    continue;
                }
                top = std::min(top, glyph->top);
                bottom = std::max(bottom, glyph->bottom);
            }
            return bottom > top ? (bottom - top) * element.FontSize() : element.FontSize();
        }

        float lineHeight(const Element& element) {
            return element.LineHeight() > 0.0f ? element.LineHeight() : textHeight(element);
        }

        size_t wrappedLineCount(const Element& element, float availableWidth) {
            if (!element.TextWrapping()) {
                return 1;
            }
            const float width = element.Width() > 0.0f ? element.Width() : availableWidth;
            if (width <= 0.0f) {
                return 1;
            }
            const size_t maximumCharacters = std::max(
                static_cast<size_t>(1),
                static_cast<size_t>(width / (element.FontSize() * 0.55f)));
            size_t lineLength = 0;
            size_t lineCount = 1;
            size_t wordLength = 0;
            const auto addWord = [&] {
                if (wordLength == 0) {
                    return;
                }
                if (lineLength != 0 && lineLength + 1 + wordLength > maximumCharacters) {
                    ++lineCount;
                    lineLength = 0;
                }
                lineLength += lineLength == 0 ? wordLength : wordLength + 1;
                wordLength = 0;
            };
            for (const unsigned char character : element.Text()) {
                if (std::isspace(character)) {
                    addWord();
                } else if ((character & 0xC0) != 0x80) {
                    ++wordLength;
                }
            }
            addWord();
            return lineCount;
        }

        float horizontal(const attr::Thickness& thickness) {
            return thickness.Horizontal();
        }

        float vertical(const attr::Thickness& thickness) {
            return thickness.Vertical();
        }

        Rect inset(Rect bounds, attr::Thickness thickness) {
            return universaldevkit::helpers::math::Geometry::Inset(bounds, thickness);
        }

        Rect intersect(Rect first, Rect second) {
            return universaldevkit::helpers::math::Geometry::Intersect(first, second);
        }

        void clipSubtree(Element& element) {
            element.SetClipBounds(element.Bounds());
            for (const std::unique_ptr<Element>& child : element.Children()) {
                clipSubtree(*child);
            }
        }

        Size withCommonSize(const Element& element, Size contentSize) {
            const attr::Thickness padding = element.Padding();
            const attr::Thickness border = element.BorderThickness();
            const attr::Thickness margin = element.Margin();
            contentSize.width += horizontal(padding) + horizontal(border);
            contentSize.height += vertical(padding) + vertical(border);
            if (element.Width() > 0.0f) {
                contentSize.width = element.Width();
            }
            if (element.Height() > 0.0f) {
                contentSize.height = element.Height();
            }
            contentSize.width += horizontal(margin);
            contentSize.height += vertical(margin);
            return contentSize;
        }

        std::vector<std::string> tracks(const std::string& definitions);

        Size measure(Element& element, float availableWidth) {
            if (!element.ParticipatesInLayout()) {
                element.SetDesiredSize({});
                return {};
            }
            const attr::Thickness decoration{
                element.Padding().left + element.BorderThickness().left,
                element.Padding().right + element.BorderThickness().right,
                element.Padding().top + element.BorderThickness().top,
                element.Padding().bottom + element.BorderThickness().bottom,
            };
            const float contentWidth = element.Width() > 0.0f
                ? std::max(0.0f, element.Width() - horizontal(decoration))
                : std::max(0.0f, availableWidth - horizontal(element.Margin()) - horizontal(decoration));
            // Первый проход вычисляет требуемый размер снизу вверх. Ширина
            // контейнера участвует в вычислении высоты переносимого текста.
            if (element.Type() == ElementType::textBlock
                || (element.Type() == ElementType::button && element.Children().empty())) {
                Size result{
                    std::max(1.0f, static_cast<float>(utf8Length(element.Text())) * element.FontSize() * 0.55f),
                    lineHeight(element) * static_cast<float>(wrappedLineCount(element, contentWidth)),
                };
                if (element.TextWrapping() && contentWidth > 0.0f) {
                    result.width = std::min(result.width, contentWidth);
                }
                if (element.Type() == ElementType::button) {
                    result.width += 48.0f;
                    result.height += 24.0f;
                }
                result = withCommonSize(element, result);
                element.SetDesiredSize(result);
                return result;
            }

            if (element.Type() == ElementType::toggleSwitch) {
                Size result{
                    element.Width() > 0.0f ? element.Width() : 56.0f,
                    element.Height() > 0.0f ? element.Height() : 32.0f,
                };
                result = withCommonSize(element, result);
                element.SetDesiredSize(result);
                return result;
            }

            if (element.Type() == ElementType::grid) {
                const std::vector<std::string> columns = tracks(element.Columns());
                const std::vector<std::string> rows = tracks(element.Rows());
                std::vector<float> columnSizes(columns.size());
                std::vector<float> rowSizes(rows.size());

                for (size_t index = 0; index < columns.size(); ++index) {
                    const std::string& definition = columns[index];
                    if (definition != "*" && definition != "Auto" && definition.back() != '%') {
                        columnSizes[index] = std::stof(definition);
                    }
                }
                for (size_t index = 0; index < rows.size(); ++index) {
                    const std::string& definition = rows[index];
                    if (definition != "*" && definition != "Auto" && definition.back() != '%') {
                        rowSizes[index] = std::stof(definition);
                    }
                }
                for (const auto& child : element.Children()) {
                    const Size childSize = measure(*child, contentWidth);
                    const size_t column = std::min(
                        static_cast<size_t>(std::max(0, child->GridColumn())), columns.size() - 1);
                    const size_t row = std::min(
                        static_cast<size_t>(std::max(0, child->GridRow())), rows.size() - 1);
                    if (columns[column] == "Auto" || columns[column] == "*" || columns[column].back() == '%') {
                        columnSizes[column] = std::max(columnSizes[column], childSize.width);
                    }
                    if (rows[row] == "Auto" || rows[row] == "*" || rows[row].back() == '%') {
                        rowSizes[row] = std::max(rowSizes[row], childSize.height);
                    }
                }

                const auto desiredTrackSize = [](const std::vector<std::string>& definitions,
                                                 const std::vector<float>& sizes) {
                    float nonPercentageSize = 0.0f;
                    float percentage = 0.0f;
                    float percentageMinimumSize = 0.0f;
                    for (size_t index = 0; index < definitions.size(); ++index) {
                        const std::string& definition = definitions[index];
                        if (!definition.empty() && definition.back() == '%') {
                            const float trackPercentage = std::stof(
                                definition.substr(0, definition.size() - 1)) / 100.0f;
                            percentage += trackPercentage;
                            if (trackPercentage > 0.0f) {
                                percentageMinimumSize = std::max(
                                    percentageMinimumSize,
                                    sizes[index] / trackPercentage);
                            }
                        } else {
                            nonPercentageSize += sizes[index];
                        }
                    }
                    if (percentage >= 1.0f) {
                        return nonPercentageSize + percentageMinimumSize;
                    }
                    return std::max(
                        nonPercentageSize / (1.0f - percentage),
                        percentageMinimumSize);
                };
                Size result{
                    desiredTrackSize(columns, columnSizes),
                    desiredTrackSize(rows, rowSizes),
                };
                result = withCommonSize(element, result);
                element.SetDesiredSize(result);
                return result;
            }

            if (element.Type() == ElementType::border || element.Type() == ElementType::button) {
                Size result{};
                if (!element.Children().empty()) {
                    result = measure(*element.Children().front(), contentWidth);
                }
                result = withCommonSize(element, result);
                element.SetDesiredSize(result);
                return result;
            }

            if (element.Type() == ElementType::scrollViewer) {
                Size result{};
                if (!element.Children().empty()) {
                    result = measure(*element.Children().front(), contentWidth);
                }
                result = withCommonSize(element, result);
                element.SetDesiredSize(result);
                return result;
            }

            Size result{};
            for (const auto& child : element.Children()) {
                const Size childSize = measure(*child, contentWidth);
                if (element.OrientationValue() == attr::Orientation::vertical) {
                    result.width = std::max(result.width, childSize.width);
                    result.height += childSize.height;
                } else {
                    result.width += childSize.width;
                    result.height = std::max(result.height, childSize.height);
                }
            }
            result = withCommonSize(element, result);
            element.SetDesiredSize(result);
            return result;
        }

        float alignedOffset(attr::Alignment alignment, float available, float desired) {
            if (alignment == attr::Alignment::right || alignment == attr::Alignment::bottom) {
                return available - desired;
            }
            if (alignment == attr::Alignment::center) {
                return (available - desired) / 2.0f;
            }
            return 0.0f;
        }

        float alignedSize(attr::Alignment alignment, float available, float desired, float explicitSize) {
            return alignment == attr::Alignment::stretch && explicitSize <= 0.0f ? available : desired;
        }

        std::vector<std::string> tracks(const std::string& definitions) {
            std::vector<std::string> result;
            std::istringstream input(definitions);
            std::string track;
            while (std::getline(input, track, ',')) {
                result.push_back(track.empty() ? "*" : track);
            }
            if (result.empty()) {
                result.push_back("*");
            }
            return result;
        }

        std::vector<float> trackSizes(
            const std::vector<std::string>& definitions,
            float available,
            const Element& grid,
            bool columns) {
            std::vector<float> sizes(definitions.size());
            float used = 0.0f;
            size_t starCount = 0;
            for (size_t index = 0; index < definitions.size(); ++index) {
                const std::string& definition = definitions[index];
                if (definition == "*") {
                    ++starCount;
                } else if (!definition.empty() && definition.back() == '%') {
                    sizes[index] = available * std::stof(definition.substr(0, definition.size() - 1)) / 100.0f;
                    used += sizes[index];
                } else if (definition == "Auto") {
                    for (const auto& child : grid.Children()) {
                        const int track = columns ? child->GridColumn() : child->GridRow();
                        if (track == static_cast<int>(index)) {
                            sizes[index] = std::max(sizes[index], columns
                                ? child->DesiredSize().width : child->DesiredSize().height);
                        }
                    }
                    used += sizes[index];
                } else {
                    sizes[index] = std::stof(definition);
                    used += sizes[index];
                }
            }
            const float starSize = starCount == 0 ? 0.0f : std::max(0.0f, available - used) / starCount;
            for (size_t index = 0; index < definitions.size(); ++index) {
                if (definitions[index] == "*") {
                    sizes[index] = starSize;
                }
            }
            return sizes;
        }

        void arrange(Element& element, Rect bounds, Rect parentClipBounds) {
            // Второй проход выдаёт каждому элементу конечный прямоугольник
            // сверху вниз. StackPanel центрирует детей по поперечной оси.
            const Rect elementBounds = inset(bounds, element.Margin());
            element.SetBounds(elementBounds);
            element.SetClipBounds(intersect(elementBounds, parentClipBounds));
            const attr::Thickness paddingAndBorder{
                element.Padding().left + element.BorderThickness().left,
                element.Padding().right + element.BorderThickness().right,
                element.Padding().top + element.BorderThickness().top,
                element.Padding().bottom + element.BorderThickness().bottom,
            };
            const Rect contentBounds = inset(elementBounds, paddingAndBorder);
            if (element.Type() == ElementType::page) {
                for (const auto& child : element.Children()) {
                    const Size childSize = child->DesiredSize();
                    arrange(*child, {
                        contentBounds.x + alignedOffset(
                            child->HorizontalAlignmentValue(), contentBounds.width, childSize.width),
                        contentBounds.y + alignedOffset(
                            child->VerticalAlignmentValue(), contentBounds.height, childSize.height),
                        alignedSize(child->HorizontalAlignmentValue(), contentBounds.width, childSize.width, child->Width()),
                        alignedSize(child->VerticalAlignmentValue(), contentBounds.height, childSize.height, child->Height()),
                    }, element.ClipBounds());
                }
                return;
            }
            if (element.Type() == ElementType::grid) {
                const std::vector<std::string> columns = tracks(element.Columns());
                const std::vector<std::string> rows = tracks(element.Rows());
                const std::vector<float> columnSizes = trackSizes(columns, contentBounds.width, element, true);
                const std::vector<float> rowSizes = trackSizes(rows, contentBounds.height, element, false);
                for (const auto& child : element.Children()) {
                    const size_t column = std::min(static_cast<size_t>(std::max(0, child->GridColumn())), columns.size() - 1);
                    const size_t row = std::min(static_cast<size_t>(std::max(0, child->GridRow())), rows.size() - 1);
                    float x = contentBounds.x;
                    for (size_t index = 0; index < column; ++index) {
                        x += columnSizes[index];
                    }
                    float y = contentBounds.y;
                    for (size_t index = 0; index < row; ++index) {
                        y += rowSizes[index];
                    }
                    const Size childSize = child->DesiredSize();
                    arrange(*child, {
                        x + alignedOffset(child->HorizontalAlignmentValue(), columnSizes[column], childSize.width),
                        y + alignedOffset(child->VerticalAlignmentValue(), rowSizes[row], childSize.height),
                        alignedSize(child->HorizontalAlignmentValue(), columnSizes[column], childSize.width, child->Width()),
                        alignedSize(child->VerticalAlignmentValue(), rowSizes[row], childSize.height, child->Height()),
                    }, element.ClipBounds());
                }
                return;
            }
            if (element.Type() == ElementType::border || element.Type() == ElementType::button) {
                if (!element.Children().empty()) {
                    Element& child = *element.Children().front();
                    const Size childSize = child.DesiredSize();
                    arrange(child, {
                        contentBounds.x + alignedOffset(
                            child.HorizontalAlignmentValue(), contentBounds.width, childSize.width),
                        contentBounds.y + alignedOffset(
                            child.VerticalAlignmentValue(), contentBounds.height, childSize.height),
                        alignedSize(child.HorizontalAlignmentValue(), contentBounds.width, childSize.width, child.Width()),
                        alignedSize(child.VerticalAlignmentValue(), contentBounds.height, childSize.height, child.Height()),
                    }, element.ClipBounds());
                }
                return;
            }
            if (element.Type() == ElementType::scrollViewer) {
                if (element.Children().empty()) {
                    element.SetScrollMetrics({}, {contentBounds.width, contentBounds.height});
                    element.SetHorizontalOffset(0.0f);
                    element.SetVerticalOffset(0.0f);
                    return;
                }
                Element& child = *element.Children().front();
                const Size desired = child.DesiredSize();
                element.SetScrollMetrics(
                    {std::max(contentBounds.width, desired.width), std::max(contentBounds.height, desired.height)},
                    {contentBounds.width, contentBounds.height});
                element.SetHorizontalOffset(std::clamp(element.HorizontalOffset(), 0.0f,
                    std::max(0.0f, element.Extent().width - element.Viewport().width)));
                element.SetVerticalOffset(std::clamp(element.VerticalOffset(), 0.0f,
                    std::max(0.0f, element.Extent().height - element.Viewport().height)));
                arrange(child, {
                    contentBounds.x,
                    contentBounds.y,
                    element.Extent().width,
                    element.Extent().height,
                }, element.ClipBounds());
                clipSubtree(child);
                return;
            }
            float cursor = element.OrientationValue() == attr::Orientation::vertical ? contentBounds.y : contentBounds.x;
            for (const auto& child : element.Children()) {
                const Size size = child->DesiredSize();
                Rect childBounds;
                if (element.OrientationValue() == attr::Orientation::vertical) {
                    childBounds = {contentBounds.x + alignedOffset(child->HorizontalAlignmentValue(), contentBounds.width, size.width), cursor, alignedSize(child->HorizontalAlignmentValue(), contentBounds.width, size.width, child->Width()), size.height};
                    cursor += size.height;
                } else {
                    childBounds = {cursor, contentBounds.y + alignedOffset(child->VerticalAlignmentValue(), contentBounds.height, size.height), size.width, alignedSize(child->VerticalAlignmentValue(), contentBounds.height, size.height, child->Height())};
                    cursor += size.width;
                }
                arrange(*child, childBounds, element.ClipBounds());
            }
        }
    } // namespace details

    Element::Element(ElementType type)
        : type(type) {
    }

    Element::~Element() {
        if (this->itemsUnsubscribe) {
            this->itemsUnsubscribe();
        }
    }

    ElementType Element::Type() const {
        return this->type;
    }

    const std::string& Element::Id() const {
        return this->id;
    }

    void Element::SetId(std::string value) {
        this->id = std::move(value);
    }

    int Element::SourceLine() const {
        return this->sourceLine;
    }

    int Element::SourceColumn() const {
        return this->sourceColumn;
    }

    const std::string& Element::SourcePath() const {
        return this->sourcePath;
    }

    void Element::SetSourceLocation(int line, int column) {
        this->SetSourceLocation({}, line, column);
    }

    void Element::SetSourceLocation(std::string path, int line, int column) {
        this->sourcePath = std::move(path);
        this->sourceLine = line;
        this->sourceColumn = column;
    }

    const void* Element::DataContext() const {
        return this->dataContext;
    }

    void Element::SetDataContext(const void* value) {
        this->hasLocalDataContext = true;
        this->dataContext = value;
        for (const std::unique_ptr<Element>& child : this->children) {
            child->SetInheritedDataContext(value);
        }
    }

    const std::string& Element::Renderer() const {
        return this->renderer;
    }

    void Element::SetRenderer(std::string value) {
        this->renderer = std::move(value);
    }

    const std::string& Element::Text() const {
        return this->text;
    }

    void Element::SetText(std::string value) {
        if (this->text == value) {
            return;
        }
        this->text = std::move(value);
        this->InvalidateLayout();
    }

    float Element::FontSize() const {
        return this->fontSize;
    }

    void Element::SetFontSize(float value) {
        this->fontSize = value;
    }

    float Element::LineHeight() const {
        return this->lineHeight;
    }

    void Element::SetLineHeight(float value) {
        if (value <= 0.0f) {
            throw std::invalid_argument("lineHeight must be positive");
        }
        this->lineHeight = value;
        this->InvalidateLayout();
    }

    const std::string& Element::FontFamily() const {
        return this->fontFamily;
    }

    void Element::SetFontFamily(std::string value) {
        this->fontFamily = std::move(value);
    }

    const std::string& Element::FontWeight() const {
        return this->fontWeight;
    }

    void Element::SetFontWeight(std::string value) {
        this->fontWeight = std::move(value);
    }

    bool Element::TextWrapping() const {
        return this->textWrapping;
    }

    void Element::SetTextWrapping(bool value) {
        if (this->textWrapping == value) {
            return;
        }
        this->textWrapping = value;
        this->InvalidateLayout();
    }

    const std::string& Element::Source() const {
        return this->source;
    }

    void Element::SetSource(std::string value) {
        this->source = std::move(value);
    }

    attr::Color Element::Tint() const {
        return this->tint;
    }

    void Element::SetTint(attr::Color value) {
        this->tint = value;
    }

    bool Element::HasCommand() const {
        return static_cast<bool>(this->command);
    }

    void Element::SetCommand(Command value) {
        this->command = std::move(value);
    }

    void Element::ExecuteCommand() const {
        if (this->runtimeSourceUpdate) {
            this->runtimeSourceUpdate();
        }
        if (this->command) {
            this->command();
        }
    }

    void Element::SetRuntimeSourceUpdate(std::function<void()> update) {
        this->runtimeSourceUpdate = std::move(update);
    }

    attr::Color Element::Foreground() const {
        return this->foreground;
    }

    void Element::SetForeground(attr::Color value) {
        this->foreground = value;
    }

    attr::Orientation Element::OrientationValue() const {
        return this->orientation;
    }

    void Element::SetOrientation(attr::Orientation value) {
        this->orientation = value;
    }

    attr::Alignment Element::VerticalAlignmentValue() const {
        return this->verticalAlignment;
    }

    void Element::SetVerticalAlignment(attr::Alignment value) {
        if (this->verticalAlignment != value) {
            this->verticalAlignment = value;
            this->InvalidateLayout();
        }
    }

    attr::Alignment Element::HorizontalAlignmentValue() const {
        return this->horizontalAlignment;
    }

    void Element::SetHorizontalAlignment(attr::Alignment value) {
        if (this->horizontalAlignment != value) {
            this->horizontalAlignment = value;
            this->InvalidateLayout();
        }
    }

    attr::Alignment Element::ContentAlignmentValue() const {
        return this->contentAlignment;
    }

    void Element::SetContentAlignment(attr::Alignment value) {
        this->contentAlignment = value;
    }

    int Element::GridRow() const {
        return this->gridRow;
    }

    void Element::SetGridRow(int value) {
        this->gridRow = value;
    }

    int Element::GridColumn() const {
        return this->gridColumn;
    }

    void Element::SetGridColumn(int value) {
        this->gridColumn = value;
    }

    const std::string& Element::Rows() const {
        return this->rows;
    }

    void Element::SetRows(std::string value) {
        this->rows = std::move(value);
    }

    const std::string& Element::Columns() const {
        return this->columns;
    }

    void Element::SetColumns(std::string value) {
        this->columns = std::move(value);
    }

    attr::Color Element::Background() const {
        return this->background;
    }

    void Element::SetBackground(attr::Color value) {
        this->background = value;
    }

    attr::Color Element::ActiveBackground() const {
        return this->activeBackground;
    }

    void Element::SetActiveBackground(attr::Color value) {
        this->activeBackground = value;
    }

    attr::Color Element::BorderColor() const {
        return this->borderColor;
    }

    void Element::SetBorderColor(attr::Color value) {
        this->borderColor = value;
    }

    attr::Color Element::ActiveBorderColor() const {
        return this->activeBorderColor;
    }

    void Element::SetActiveBorderColor(attr::Color value) {
        this->activeBorderColor = value;
    }

    attr::Color Element::ActiveForeground() const {
        return this->activeForeground;
    }

    void Element::SetActiveForeground(attr::Color value) {
        this->activeForeground = value;
    }

    attr::Thickness Element::Margin() const {
        return this->margin;
    }

    void Element::SetMargin(attr::Thickness value) {
        this->margin = value;
    }

    attr::Thickness Element::Padding() const {
        return this->padding;
    }

    void Element::SetPadding(attr::Thickness value) {
        this->padding = value;
    }

    attr::Thickness Element::BorderThickness() const {
        return this->borderThickness;
    }

    void Element::SetBorderThickness(attr::Thickness value) {
        this->borderThickness = value;
    }

    const attr::Wireframe& Element::Wireframe() const {
        return this->wireframe;
    }

    void Element::SetWireframe(attr::Wireframe value) {
        this->wireframe = value;
    }

    bool Element::HasInspectionWireframe() const {
        return this->hasInspectionWireframe;
    }

    const attr::Wireframe& Element::InspectionWireframe() const {
        return this->inspectionWireframe;
    }

    void Element::SetInspectionWireframe(attr::Wireframe value) {
        this->inspectionWireframe = value;
        this->hasInspectionWireframe = true;
    }

    void Element::ClearInspectionWireframe() {
        this->hasInspectionWireframe = false;
    }

    bool Element::HasSelectedWireframe() const { return this->hasSelectedWireframe; }
    const attr::Wireframe& Element::SelectedWireframe() const { return this->selectedWireframe; }
    void Element::SetSelectedWireframe(attr::Wireframe value) { this->selectedWireframe = value; this->hasSelectedWireframe = true; }
    void Element::ClearSelectedWireframe() { this->hasSelectedWireframe = false; }

    float Element::CornerRadius() const {
        return this->cornerRadius;
    }

    void Element::SetCornerRadius(float value) {
        this->cornerRadius = value;
    }

    float Element::Width() const {
        return this->width;
    }

    void Element::SetWidth(float value) {
        if (this->width != value) {
            this->width = value;
            this->InvalidateLayout();
        }
    }

    float Element::Height() const {
        return this->height;
    }

    void Element::SetHeight(float value) {
        if (this->height != value) {
            this->height = value;
            this->InvalidateLayout();
        }
    }

    bool Element::IsOn() const {
        return this->isOn;
    }

    void Element::SetIsOn(bool value) {
        this->isOn = value;
    }

    attr::Visibility Element::VisibilityValue() const {
        return this->visibility;
    }

    void Element::SetVisibility(attr::Visibility value) {
        if (this->visibility != value) {
            this->visibility = value;
            AnimationController::Synchronize(*this);
            this->InvalidateLayout();
        }
    }

    void Element::SetIsVisible(bool value) {
        this->SetVisibility(value ? attr::Visibility::visible : attr::Visibility::collapsed);
    }

    bool Element::IsEnabled() const {
        return this->isEnabled;
    }

    void Element::SetIsEnabled(bool value) {
        this->isEnabled = value;
    }

    float Element::Opacity() const {
        return this->opacity;
    }

    void Element::SetOpacity(float value) {
        this->opacity = value;
    }

    float Element::RenderOffsetX() const {
        return this->renderOffsetX;
    }

    void Element::SetRenderOffsetX(float value) {
        this->renderOffsetX = value;
    }

    float Element::RenderOffsetY() const {
        return this->renderOffsetY;
    }

    void Element::SetRenderOffsetY(float value) {
        this->renderOffsetY = value;
    }

    attr::ScrollBarVisibility Element::VerticalScrollBarVisibility() const { return this->verticalScrollBarVisibility; }
    void Element::SetVerticalScrollBarVisibility(attr::ScrollBarVisibility value) { this->verticalScrollBarVisibility = value; }
    attr::ScrollBarVisibility Element::HorizontalScrollBarVisibility() const { return this->horizontalScrollBarVisibility; }
    void Element::SetHorizontalScrollBarVisibility(attr::ScrollBarVisibility value) { this->horizontalScrollBarVisibility = value; }
    float Element::HorizontalOffset() const { return this->horizontalOffset; }
    void Element::SetHorizontalOffset(float value) {
        this->horizontalOffset = std::clamp(value, 0.0f, std::max(0.0f, this->extent.width - this->viewport.width));
    }
    float Element::VerticalOffset() const { return this->verticalOffset; }
    void Element::SetVerticalOffset(float value) {
        this->verticalOffset = std::clamp(value, 0.0f, std::max(0.0f, this->extent.height - this->viewport.height));
    }
    Size Element::Extent() const { return this->extent; }
    Size Element::Viewport() const { return this->viewport; }
    void Element::SetScrollMetrics(Size extentValue, Size viewportValue) {
        this->extent = this->isScrollExtentHeld
            ? Size{std::max(extentValue.width, this->heldScrollExtent.width), std::max(extentValue.height, this->heldScrollExtent.height)}
            : extentValue;
        this->viewport = viewportValue;
    }
    void Element::HoldScrollExtent(Size value) {
        this->heldScrollExtent = value;
        this->isScrollExtentHeld = true;
        this->extent = {std::max(this->extent.width, value.width), std::max(this->extent.height, value.height)};
    }
    void Element::ReleaseScrollExtent() {
        this->isScrollExtentHeld = false;
        this->InvalidateLayout();
    }

    float Element::ToggleProgress() const {
        return this->toggleProgress;
    }

    void Element::SetToggleProgress(float value) {
        this->toggleProgress = value;
    }

    float Element::PressProgress() const {
        return this->pressProgress;
    }

    void Element::SetPressProgress(float value) {
        this->pressProgress = value;
    }

    const std::string& Element::DefaultAnimation() const {
        return this->defaultAnimation;
    }

    void Element::SetDefaultAnimation(std::string value) {
        this->defaultAnimation = std::move(value);
    }

    void Element::SetAnimationParametersProvider(std::function<AnimationParameters()> provider) {
        this->animationParametersProvider = std::move(provider);
    }

    PresencePhase Element::Presence() const {
        return this->animationState.registry ? this->animationState.phase
            : this->visibility == attr::Visibility::visible ? PresencePhase::visible : PresencePhase::hidden;
    }

    bool Element::IsPresent() const {
        return this->Presence() != PresencePhase::hidden;
    }

    bool Element::ParticipatesInLayout() const {
        return this->visibility != attr::Visibility::collapsed || this->IsPresent();
    }

    bool Element::CanReceiveInput() const {
        return this->visibility == attr::Visibility::visible
            && !this->animationState.removing
            && (!this->animationState.registry || this->animationState.targetVisible)
            && (this->parent == nullptr || this->parent->CanReceiveInput());
    }

    ElementStates& Element::States() {
        return this->states;
    }

    const ElementStates& Element::States() const {
        return this->states;
    }

    const AnimationParameters& Element::CurrentAnimationParameters() const {
        return this->animationState.parameters;
    }

    AnimationTrigger Element::AnimationEvent() const {
        return this->animationState.trigger;
    }

    const std::vector<Storyboard>& Element::Storyboards() const {
        return this->storyboards;
    }

    void Element::SetStoryboards(std::vector<Storyboard> value) {
        this->storyboards = std::move(value);
    }

    void Element::AddStoryboard(Storyboard value) {
        this->storyboards.push_back(std::move(value));
    }

    const std::vector<VisualStateGroup>& Element::VisualStateGroups() const {
        return this->visualStateGroups;
    }

    std::vector<VisualStateGroup>& Element::VisualStateGroups() {
        return this->visualStateGroups;
    }

    void Element::SetVisualStateGroups(std::vector<VisualStateGroup> value) {
        this->visualStateGroups = std::move(value);
    }

    Size Element::DesiredSize() const {
        return this->desiredSize;
    }

    void Element::SetDesiredSize(Size value) {
        this->desiredSize = value;
    }

    Rect Element::Bounds() const {
        return this->bounds;
    }

    void Element::SetBounds(Rect value) {
        this->bounds = value;
    }

    Rect Element::ClipBounds() const {
        return this->clipBounds;
    }

    void Element::SetClipBounds(Rect value) {
        this->clipBounds = value;
    }

    const std::vector<std::unique_ptr<Element>>& Element::Children() const {
        return this->children;
    }

    std::vector<std::unique_ptr<Element>>& Element::Children() {
        return this->children;
    }

    void Element::AddChild(std::unique_ptr<Element> child) {
        child->parent = this;
        child->SetInheritedDataContext(this->dataContext);
        if (this->animationState.registry) {
            Element* root = this;
            while (root->parent != nullptr) {
                root = root->parent;
            }
            if (!AnimationController::IsAnimating(*root)) {
                root->animationState.updatedAt = std::chrono::steady_clock::now();
            }
            AnimationController::AttachTree(*child, this->animationState.registry,
                this->animationState.targetVisible, true, this->animationState.parameters);
        }
        this->children.push_back(std::move(child));
        this->InvalidateLayout();
    }

    void Element::SetInheritedDataContext(const void* value) {
        if (this->hasLocalDataContext) {
            return;
        }
        this->dataContext = value;
        for (const std::unique_ptr<Element>& child : this->children) {
            child->SetInheritedDataContext(value);
        }
    }

    void Element::RemoveChild(Element& child) {
        const auto found = std::find_if(this->children.begin(), this->children.end(),
            [&child](const auto& value) { return value.get() == &child; });
        if (found == this->children.end()) {
            return;
        }
        child.animationState.removing = true;
        if (child.animationState.registry) {
            AnimationController::Synchronize(child);
        } else {
            this->children.erase(found);
        }
        this->InvalidateLayout();
    }

    void Element::RemoveChildImmediately(Element& child) {
        const auto found = std::find_if(this->children.begin(), this->children.end(),
            [&child](const auto& value) { return value.get() == &child; });
        if (found == this->children.end()) {
            return;
        }
        this->children.erase(found);
        this->InvalidateLayout();
    }

    void Element::SwapTreePosition(Element& other) noexcept {
        if (this->parent == nullptr || other.parent == nullptr) {
            return;
        }
        auto& first = this->parent->children;
        auto& second = other.parent->children;
        const auto left = std::find_if(first.begin(), first.end(), [this](const auto& child) { return child.get() == this; });
        const auto right = std::find_if(second.begin(), second.end(), [&other](const auto& child) { return child.get() == &other; });
        std::swap(*left, *right);
        std::swap(this->parent, other.parent);
        this->parent->InvalidateLayout();
        other.parent->InvalidateLayout();
    }

    void Element::CopyLayoutFrom(const Element& other) {
        this->id = other.id;
        this->renderer = other.renderer;
        this->wireframe = other.wireframe;
        this->rows = other.rows;
        this->columns = other.columns;
        this->storyboards = other.storyboards;
        this->visualStateGroups = other.visualStateGroups;
        this->sourcePath = other.sourcePath;
        this->sourceLine = other.sourceLine;
        this->sourceColumn = other.sourceColumn;
        this->margin = other.margin;
        this->padding = other.padding;
        this->width = other.width;
        this->height = other.height;
        this->verticalAlignment = other.verticalAlignment;
        this->horizontalAlignment = other.horizontalAlignment;
        this->gridRow = other.gridRow;
        this->gridColumn = other.gridColumn;
        this->background = other.background;
        this->borderColor = other.borderColor;
        this->borderThickness = other.borderThickness;
        this->cornerRadius = other.cornerRadius;
        this->opacity = other.opacity;
        this->visibility = other.visibility;
        this->isEnabled = other.isEnabled;
        this->command = other.command;
        this->runtimeSourceUpdate = other.runtimeSourceUpdate;
        this->InvalidateLayout();
    }

    void Element::OnItemsChanged(CollectionChange change) {
        switch (change.kind) {
        case CollectionChangeKind::insert:
            this->InsertItems(change.index, change.count);
            return;
        case CollectionChangeKind::remove:
            this->RemoveItems(change.index, change.count);
            return;
        case CollectionChangeKind::replace:
            this->ReplaceItems(change.index, change.count);
            return;
        case CollectionChangeKind::move:
            this->MoveItems(change.oldIndex, change.index, change.count);
            return;
        case CollectionChangeKind::reset:
            this->RebuildItems();
            return;
        }
    }

    void Element::RebuildItems() {
        this->RemoveItems(0, this->repeatedItems.size());
        if (this->itemsCount) {
            this->InsertItems(0, this->itemsCount());
        }
    }

    void Element::InsertItems(size_t index, size_t count) {
        if (!this->itemAt || !this->itemTemplate || index > this->repeatedItems.size()) {
            return;
        }
        for (size_t offset = 0; offset < count; ++offset) {
            auto bindings = std::make_unique<BindingScope>();
            std::unique_ptr<Element> container = this->itemTemplate(this->itemAt(index + offset), *bindings);
            if (!container) {
                continue;
            }
            Element* const rawContainer = container.get();
            this->children.insert(this->children.begin() + static_cast<std::ptrdiff_t>(index + offset), std::move(container));
            this->repeatedItems.insert(this->repeatedItems.begin() + static_cast<std::ptrdiff_t>(index + offset),
                {rawContainer, std::move(bindings)});
        }
        this->InvalidateLayout();
    }

    void Element::RemoveItems(size_t index, size_t count) {
        if (index >= this->repeatedItems.size()) {
            return;
        }
        const size_t end = std::min(this->repeatedItems.size(), index + count);
        for (size_t current = end; current > index; --current) {
            RepeatedItem& item = this->repeatedItems[current - 1];
            this->RemoveChildImmediately(*item.container);
            this->repeatedItems.erase(this->repeatedItems.begin() + static_cast<std::ptrdiff_t>(current - 1));
        }
    }

    void Element::ReplaceItems(size_t index, size_t count) {
        this->RemoveItems(index, count);
        this->InsertItems(index, count);
    }

    void Element::MoveItems(size_t oldIndex, size_t index, size_t count) {
        if (count == 0 || oldIndex >= this->repeatedItems.size() || oldIndex + count > this->repeatedItems.size()) {
            return;
        }
        std::vector<RepeatedItem> moved(
            std::make_move_iterator(this->repeatedItems.begin() + static_cast<std::ptrdiff_t>(oldIndex)),
            std::make_move_iterator(this->repeatedItems.begin() + static_cast<std::ptrdiff_t>(oldIndex + count)));
        this->repeatedItems.erase(
            this->repeatedItems.begin() + static_cast<std::ptrdiff_t>(oldIndex),
            this->repeatedItems.begin() + static_cast<std::ptrdiff_t>(oldIndex + count));
        if (index > oldIndex) {
            index -= count;
        }
        this->repeatedItems.insert(this->repeatedItems.begin() + static_cast<std::ptrdiff_t>(index),
            std::make_move_iterator(moved.begin()), std::make_move_iterator(moved.end()));
        std::stable_sort(this->children.begin(), this->children.end(), [this](const auto& left, const auto& right) {
            const auto leftPosition = std::find_if(this->repeatedItems.begin(), this->repeatedItems.end(),
                [&left](const RepeatedItem& item) { return item.container == left.get(); });
            const auto rightPosition = std::find_if(this->repeatedItems.begin(), this->repeatedItems.end(),
                [&right](const RepeatedItem& item) { return item.container == right.get(); });
            return leftPosition < rightPosition;
        });
        this->InvalidateLayout();
    }

    Element* Element::Parent() const {
        return this->parent;
    }

    std::weak_ptr<void> Element::LifetimeToken() const {
        return this->lifetimeToken;
    }

    void Element::InvalidateLayout() {
        this->layoutInvalid = true;
        if (this->parent != nullptr) {
            this->parent->InvalidateLayout();
        }
    }

    Element& ElementAt(Element& root, std::initializer_list<size_t> path) {
        Element* element = &root;
        for (const size_t childIndex : path) {
            element = element->Children().at(childIndex).get();
        }
        return *element;
    }

    void SetTextGlyphMetrics(std::vector<TextGlyphMetric> value) {
        details::textGlyphMetrics = std::move(value);
    }

    void layoutInViewport(Element& root, Size availableSize) {
        details::measure(root, availableSize.width);
        const Rect bounds{0.0f, 0.0f, availableSize.width, availableSize.height};
        details::arrange(root, bounds, bounds);
        root.availableSize = availableSize;
        root.layoutInvalid = false;
    }

    void layout(Element& root, Size availableSize) {
        // Разделение measure/arrange позволяет заменить или расширить layout
        // контейнеры, не меняя контракт визуального дерева.
        const Size desired = details::measure(root, availableSize.width);
        // Layout вызывается только при invalidation, а не в каждом render frame.
        // Поэтому запись полезна для диагностики перестроений и не создаёт
        // постоянной нагрузки в render loop.
        UDK_LOG_DEBUG(
            "XamlRuntime.Layout",
            "Layout: root='{}', available={}x{}, desired={}x{}",
            root.Id(),
            availableSize.width,
            availableSize.height,
            desired.width,
            desired.height);
        if (root.Type() == ElementType::page) {
            details::arrange(
                root,
                {0.0f, 0.0f, availableSize.width, availableSize.height},
                {0.0f, 0.0f, availableSize.width, availableSize.height});
            root.availableSize = availableSize;
            root.layoutInvalid = false;
            return;
        }
        const Rect rootBounds{
            (availableSize.width - desired.width) / 2.0f,
            (availableSize.height - desired.height) / 2.0f,
            desired.width,
            desired.height,
        };
        details::arrange(root, rootBounds, rootBounds);
        root.availableSize = availableSize;
        root.layoutInvalid = false;
    }
}