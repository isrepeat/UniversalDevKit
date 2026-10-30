#pragma once
#include "ScrollController.h"
#include "Config.h"
#include "Export.h"

#include <functional>

namespace universaldevkit::xamlruntime {
    class UNIVERSALDEVKIT_XAMLRUNTIME_API AnimationController;
    class UNIVERSALDEVKIT_XAMLRUNTIME_API Element;

    enum class GestureKind {
        none,
        tap,
        pan,
        scroll,
    };

    enum class GestureDirection {
        none,
        left,
        right,
    };

    struct GestureContext {
        Element& root;
        Element& target;
        Element* scrollViewer;
        AnimationController& animations;
        float downX;
        float downY;
        float previousX;
        float previousY;
        float currentX;
        float currentY;
    };

    struct GestureResult {
        GestureKind kind = GestureKind::none;
        GestureDirection direction = GestureDirection::none;
        Element* target = nullptr;
        int itemIndex = -1;
    };

    class UNIVERSALDEVKIT_XAMLRUNTIME_API GestureRecognizer {
    public:
        virtual ~GestureRecognizer() = default;

        virtual bool Update(const GestureContext& context) = 0;
        virtual GestureResult Complete(const GestureContext& context) = 0;
        virtual void Cancel() = 0;
        virtual bool UpdateInertia() = 0;
    };

    class UNIVERSALDEVKIT_XAMLRUNTIME_API TapGestureRecognizer final : public GestureRecognizer {
    public:
        bool Update(const GestureContext& context) override;
        GestureResult Complete(const GestureContext& context) override;
        void Cancel() override;
        bool UpdateInertia() override;
    };

    class UNIVERSALDEVKIT_XAMLRUNTIME_API PanGestureRecognizer final : public GestureRecognizer {
    public:
        using TargetPredicate = std::function<bool(const Element&)>;

        void SetTargetPredicate(TargetPredicate value);

        //
        // GestureRecognizer
        //
        bool Update(const GestureContext& context) override;
        GestureResult Complete(const GestureContext& context) override;
        void Cancel() override;
        bool UpdateInertia() override;

    private:
        TargetPredicate targetPredicate;
    };

    class UNIVERSALDEVKIT_XAMLRUNTIME_API ScrollGestureRecognizer final : public GestureRecognizer {
    public:
        bool Update(const GestureContext& context) override;
        GestureResult Complete(const GestureContext& context) override;
        void Cancel() override;
        bool UpdateInertia() override;

    private:
        bool isDragging = false;
        ScrollController scrollController;
    };
}