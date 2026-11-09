#pragma once
#include "../Interface/IPageNavigator.h"
#include "../Interface/IPage.h"
#include "../Model/ApplicationRepository.h"
#include "./AppSessionController.h"

#include <memory>
#include <tuple>

namespace {{application}}::application::core {
    struct PageContext final {
        interface::IPageNavigator& navigator;
        model::ApplicationRepository& applicationRepository;
        interface::IHostCommandDispatcher& hostCommands;
        const AppSessionController& appSessionController;
    };

    template <typename... TPages>
    class PageRegistry final {
    public:
        explicit PageRegistry(PageContext& pageContext)
            : pageViewModels(std::make_unique<TPages>(pageContext)...) {
        }

        template <typename THandler>
        void ForEach(THandler&& handler) const {
            std::apply([&handler](const auto&... pageViewModels) {
                (handler(*pageViewModels), ...);
            }, this->pageViewModels);
        }

        interface::IPage* Find(std::string_view name) const {
            interface::IPage* result = nullptr;
            this->ForEach([&](interface::IPage& page) {
                if (page.Name() == name) {
                    result = &page;
                }
            });
            return result;
        }

    private:
        std::tuple<std::unique_ptr<TPages>...> pageViewModels;
    };
}