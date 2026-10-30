#pragma once
#include "../Interface/INavigationPage.h"
#include "../Interface/IPageNavigator.h"
#include "../Base/NavigationStateBase.h"

#include <string_view>
#include <memory>

namespace {{application}}::application::core {
    // Описывает данные, допустимые для конкретного ребра графа. Preview-default
    // создаёт сам native-тип, поэтому previewer не конструирует бизнес-объекты.
    struct NavigationDataContract final {
        std::string_view typeId;
#if defined(ANDROID_APP_PREVIEWER)
        std::unique_ptr<base::NavigationStateBase> (*preview_CreatePreviewDefaultFn)();
#endif
        bool isRequired;
    };

    // Общая часть контрактов данных перехода. Конкретный тип задаёт только
    // идентификатор, обязательность и способ построения preview-состояния.
    template <typename TDerived>
    class NavigationState : public base::NavigationStateBase {
    public:
        static const NavigationDataContract& Contract() {
            static const NavigationDataContract contract{
                TDerived::DataTypeId,
#if defined(ANDROID_APP_PREVIEWER)
                &TDerived::preview_CreatePreviewDefault,
#endif
                TDerived::IsRequired,
            };
            return contract;
        }

        std::string_view TypeId() const final {
            return this->Contract().typeId;
        }
    };

    // Маркер для переходов, которым payload не требуется и не разрешён.
    struct NoNavigationData final {};

    enum class NavigationTrigger {
        navigateToSettings,
        navigateBack,
    };

    enum class NavigationTargetKind {
        page,
        // Цель определяется предпоследней записью фактической истории PageManager.
        previousPage,
    };

    struct NavigationRequest final {
        std::string_view source;
        std::string_view target;
        NavigationTrigger navigationTrigger;
    };
}