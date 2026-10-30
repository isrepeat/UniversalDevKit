#pragma once
#include <functional>
#include <memory>

namespace universaldevkit::helpers::event {
    class ISubscriptionToken {
    public:
        virtual ~ISubscriptionToken() = default;
    };

    template<typename TSignature>
    class IEvent;

    template<typename... TArgs>
    class IEvent<void(TArgs...)> {
    public:
        using HandlerFunc_t = std::function<void(TArgs...)>;

        virtual ~IEvent() = default;
        virtual std::shared_ptr<ISubscriptionToken> Subscribe(const HandlerFunc_t& handlerFunction) = 0;
        virtual void Unsubscribe(std::shared_ptr<ISubscriptionToken> subscriptionToken) = 0;
        virtual void Invoke(const TArgs&... args) = 0;
    };
}