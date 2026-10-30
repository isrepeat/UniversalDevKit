#pragma once
#include "ObservableCollection.h"
#include "Storyboard.h"
#include "Animation.h"

#include <initializer_list>
#include <functional>
#include <utility>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace xaml {
    class IRenderBackend;
    class RendererRegistry;
    class BindingScope;

    struct TextGlyphMetric {
        std::string fontWeight;
        uint32_t codepoint = 0;
        float top = 0.0f;
        float bottom = 0.0f;
    };

    enum class ElementType {
        page,
        stackPanel,
        textBlock,
        button,
        border,
        toggleSwitch,
        grid,
        scrollViewer,
        image,
        svgImage,
        iconButton,
        listView,
    };

    namespace attr {
        enum class Alignment {
            stretch,
            left,
            right,
            center,
            top,
            bottom,
        };

        enum class Orientation {
            horizontal,
            vertical,
        };

        enum class Visibility {
            collapsed,
            hidden,
            visible,
        };

        enum class ScrollBarVisibility {
            autoValue,
            disabled,
            hidden,
            visible,
        };

        struct Color {
            float red = 1.0f;
            float green = 1.0f;
            float blue = 1.0f;
            float alpha = 1.0f;
        };

        struct Thickness {
            float left = 0.0f;
            float right = 0.0f;
            float top = 0.0f;
            float bottom = 0.0f;
        };

        enum class WireframeLineStyle {
            solid,
            dashed,
        };

        struct Wireframe {
            float thickness = 0.0f;
            WireframeLineStyle lineStyle = WireframeLineStyle::solid;
            Color color{0.0f, 0.0f, 0.0f, 0.0f};
            Color marginColor{0.0f, 0.0f, 0.0f, 0.0f};
            Color paddingColor{0.0f, 0.0f, 0.0f, 0.0f};
        };
    }

    struct Size {
        float width = 0.0f;
        float height = 0.0f;
    };

    struct Rect {
        float x = 0.0f;
        float y = 0.0f;
        float width = 0.0f;
        float height = 0.0f;
    };

    class Element {
    public:
        using Command = std::function<void()>;
        using ItemTemplate = std::function<std::unique_ptr<Element>(const void*, BindingScope&)>;

        explicit Element(ElementType type);
        virtual ~Element();

        ElementType Type() const;

        const std::string& Id() const;
        void SetId(std::string value);

        int SourceLine() const;
        int SourceColumn() const;
        const std::string& SourcePath() const;
        void SetSourceLocation(int line, int column);
        void SetSourceLocation(std::string path, int line, int column);

        const void* DataContext() const;
        void SetDataContext(const void* value);

        const std::string& Renderer() const;
        void SetRenderer(std::string value);

        const std::string& Text() const;
        void SetText(std::string value);

        float FontSize() const;
        void SetFontSize(float value);

        float LineHeight() const;
        void SetLineHeight(float value);

        const std::string& FontFamily() const;
        void SetFontFamily(std::string value);

        const std::string& FontWeight() const;
        void SetFontWeight(std::string value);

        bool TextWrapping() const;
        void SetTextWrapping(bool value);

        const std::string& Source() const;
        void SetSource(std::string value);

        attr::Color Tint() const;
        void SetTint(attr::Color value);

        bool HasCommand() const;
        void SetCommand(Command value);
        void ExecuteCommand() const;
        void SetRuntimeSourceUpdate(std::function<void()> update);

        attr::Color Foreground() const;
        void SetForeground(attr::Color value);

        attr::Orientation OrientationValue() const;
        void SetOrientation(attr::Orientation value);

        attr::Alignment VerticalAlignmentValue() const;
        void SetVerticalAlignment(attr::Alignment value);

        attr::Alignment HorizontalAlignmentValue() const;
        void SetHorizontalAlignment(attr::Alignment value);

        attr::Alignment ContentAlignmentValue() const;
        void SetContentAlignment(attr::Alignment value);

        int GridRow() const;
        void SetGridRow(int value);

        int GridColumn() const;
        void SetGridColumn(int value);

        const std::string& Rows() const;
        void SetRows(std::string value);

        const std::string& Columns() const;
        void SetColumns(std::string value);

        attr::Color Background() const;
        void SetBackground(attr::Color value);

        attr::Color ActiveBackground() const;
        void SetActiveBackground(attr::Color value);

        attr::Color BorderColor() const;
        void SetBorderColor(attr::Color value);

        attr::Color ActiveBorderColor() const;
        void SetActiveBorderColor(attr::Color value);

        attr::Color ActiveForeground() const;
        void SetActiveForeground(attr::Color value);

        attr::Thickness Margin() const;
        void SetMargin(attr::Thickness value);

        attr::Thickness Padding() const;
        void SetPadding(attr::Thickness value);

        attr::Thickness BorderThickness() const;
        void SetBorderThickness(attr::Thickness value);

        const attr::Wireframe& Wireframe() const;
        void SetWireframe(attr::Wireframe value);

        bool HasInspectionWireframe() const;
        const attr::Wireframe& InspectionWireframe() const;
        void SetInspectionWireframe(attr::Wireframe value);
        void ClearInspectionWireframe();
        bool HasSelectedWireframe() const;
        const attr::Wireframe& SelectedWireframe() const;
        void SetSelectedWireframe(attr::Wireframe value);
        void ClearSelectedWireframe();

        float CornerRadius() const;
        void SetCornerRadius(float value);

        float Width() const;
        void SetWidth(float value);

        float Height() const;
        void SetHeight(float value);

        bool IsOn() const;
        void SetIsOn(bool value);

        attr::Visibility VisibilityValue() const;
        void SetVisibility(attr::Visibility value);
        void SetIsVisible(bool value);

        bool IsEnabled() const;
        void SetIsEnabled(bool value);

        float Opacity() const;
        void SetOpacity(float value);

        float RenderOffsetX() const;
        void SetRenderOffsetX(float value);

        float RenderOffsetY() const;
        void SetRenderOffsetY(float value);

        attr::ScrollBarVisibility VerticalScrollBarVisibility() const;
        void SetVerticalScrollBarVisibility(attr::ScrollBarVisibility value);

        attr::ScrollBarVisibility HorizontalScrollBarVisibility() const;
        void SetHorizontalScrollBarVisibility(attr::ScrollBarVisibility value);

        float HorizontalOffset() const;
        void SetHorizontalOffset(float value);

        float VerticalOffset() const;
        void SetVerticalOffset(float value);

        Size Extent() const;
        Size Viewport() const;
        void SetScrollMetrics(Size extentValue, Size viewportValue);
        void HoldScrollExtent(Size value);
        void ReleaseScrollExtent();

        float ToggleProgress() const;
        void SetToggleProgress(float value);

        float PressProgress() const;
        void SetPressProgress(float value);

        const std::string& DefaultAnimation() const;
        void SetDefaultAnimation(std::string value);

        void SetAnimationParametersProvider(std::function<AnimationParameters()> provider);
        PresencePhase Presence() const;
        bool IsPresent() const;
        bool ParticipatesInLayout() const;
        bool CanReceiveInput() const;
        ElementStates& States();
        const ElementStates& States() const;

        template<typename TState>
        const TState& State() const {
            return this->states.Get<TState>();
        }

        const AnimationParameters& CurrentAnimationParameters() const;
        AnimationTrigger AnimationEvent() const;

        const std::vector<Storyboard>& Storyboards() const;
        void SetStoryboards(std::vector<Storyboard> value);

        void AddStoryboard(Storyboard value);

        const std::vector<VisualStateGroup>& VisualStateGroups() const;
        std::vector<VisualStateGroup>& VisualStateGroups();
        void SetVisualStateGroups(std::vector<VisualStateGroup> value);

        Size DesiredSize() const;
        void SetDesiredSize(Size value);

        Rect Bounds() const;
        void SetBounds(Rect value);

        Rect ClipBounds() const;
        void SetClipBounds(Rect value);

        const std::vector<std::unique_ptr<Element>>& Children() const;
        std::vector<std::unique_ptr<Element>>& Children();
        void AddChild(std::unique_ptr<Element> child);
        void RemoveChild(Element& child);
        void RemoveChildImmediately(Element& child);
        void SwapTreePosition(Element& other) noexcept;
        void CopyLayoutFrom(const Element& other);

        template <typename TItemsSource>
        void SetItemsSource(const TItemsSource& value, ItemTemplate templateValue) {
            if (this->itemsUnsubscribe) {
                this->itemsUnsubscribe();
            }
            this->itemsCount = [&value]() { return value.size(); };
            this->itemAt = [&value](size_t index) -> const void* {
                auto iterator = value.begin();
                std::advance(iterator, index);
                return &*iterator;
            };
            this->itemTemplate = std::move(templateValue);
            this->itemsUnsubscribe = value.Subscribe([this](CollectionChange change) {
                this->OnItemsChanged(change);
            });
            this->RebuildItems();
        }

        Element* Parent() const;
        std::weak_ptr<void> LifetimeToken() const;

    private:
        void SetInheritedDataContext(const void* value);
        void InvalidateLayout();
        void OnItemsChanged(CollectionChange change);
        void RebuildItems();
        void InsertItems(size_t index, size_t count);
        void RemoveItems(size_t index, size_t count);
        void ReplaceItems(size_t index, size_t count);
        void MoveItems(size_t oldIndex, size_t index, size_t count);

        friend class AnimationController;
        friend class AnimationRegistry;
        friend class AnimationInvocation;
        friend void layout(Element& root, Size availableSize);
        friend void layoutInViewport(Element& root, Size availableSize);
        friend void Render(Element& root, IRenderBackend& backend);
        friend void Render(
            Element& root,
            IRenderBackend& backend,
            const RendererRegistry& renderers);

    private:
        ElementType type;
        std::string id;
        int sourceLine = 0;
        int sourceColumn = 0;
        std::string sourcePath;
        const void* dataContext = nullptr;
        bool hasLocalDataContext = false;
        std::string renderer;
        std::string text;
        float fontSize = 16.0f;
        float lineHeight = 0.0f;
        std::string fontFamily;
        std::string fontWeight;
        bool textWrapping = false;
        std::string source;
        attr::Color tint{1.0f, 1.0f, 1.0f, 1.0f};
        Command command;
        std::function<void()> runtimeSourceUpdate;
        attr::Color foreground{};
        attr::Orientation orientation = attr::Orientation::vertical;
        attr::Alignment verticalAlignment = attr::Alignment::center;
        attr::Alignment horizontalAlignment = attr::Alignment::stretch;
        attr::Alignment contentAlignment = attr::Alignment::left;
        int gridRow = 0;
        int gridColumn = 0;
        std::string rows;
        std::string columns;
        attr::Color background{0.0f, 0.0f, 0.0f, 0.0f};
        attr::Color activeBackground{0.0f, 0.0f, 0.0f, 0.0f};
        attr::Color borderColor{0.0f, 0.0f, 0.0f, 0.0f};
        attr::Color activeBorderColor{0.0f, 0.0f, 0.0f, 0.0f};
        attr::Color activeForeground{1.0f, 1.0f, 1.0f, 1.0f};
        attr::Thickness margin{};
        attr::Thickness padding{};
        attr::Thickness borderThickness{};
        attr::Wireframe wireframe{};
        bool hasInspectionWireframe = false;
        attr::Wireframe inspectionWireframe{};
        bool hasSelectedWireframe = false;
        attr::Wireframe selectedWireframe{};
        float cornerRadius = 0.0f;
        float width = 0.0f;
        float height = 0.0f;
        bool isOn = false;
        attr::Visibility visibility = attr::Visibility::visible;
        bool isEnabled = true;
        float opacity = 1.0f;
        float renderOffsetX = 0.0f;
        float renderOffsetY = 0.0f;
        attr::ScrollBarVisibility verticalScrollBarVisibility = attr::ScrollBarVisibility::autoValue;
        attr::ScrollBarVisibility horizontalScrollBarVisibility = attr::ScrollBarVisibility::disabled;
        float horizontalOffset = 0.0f;
        float verticalOffset = 0.0f;
        Size extent{};
        Size viewport{};
        Size heldScrollExtent{};
        bool isScrollExtentHeld = false;
        float toggleProgress = -1.0f;
        float pressProgress = 0.0f;
        std::string defaultAnimation;
        AnimationState animationState;
        ElementStates states;
        std::shared_ptr<int> lifetimeToken = std::make_shared<int>(0);
        std::function<AnimationParameters()> animationParametersProvider;
        std::vector<Storyboard> storyboards;
        std::vector<VisualStateGroup> visualStateGroups;
        Size desiredSize{};
        Rect bounds{};
        Rect clipBounds{};
        Element* parent = nullptr;
        Size availableSize{};
        bool layoutInvalid = true;
        std::vector<std::unique_ptr<Element>> children;
        struct RepeatedItem {
            Element* container = nullptr;
            std::unique_ptr<BindingScope> bindings;
        };
        std::function<size_t()> itemsCount;
        std::function<const void*(size_t)> itemAt;
        ItemTemplate itemTemplate;
        std::function<void()> itemsUnsubscribe;
        std::vector<RepeatedItem> repeatedItems;
    };

    // Проходит от root по индексам дочерних элементов из path: {1, 1} означает
    // root.Children()[1]->Children()[1]. Пустой путь возвращает сам root.
    Element& ElementAt(Element& root, std::initializer_list<size_t> path);

    void SetTextGlyphMetrics(std::vector<TextGlyphMetric> value);

    void layout(Element& root, Size availableSize);
    void layoutInViewport(Element& root, Size availableSize);
}