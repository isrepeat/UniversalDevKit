#pragma once
#include "IEvent.h"

#include <type_traits>
#include <functional>
#include <utility>
#include <memory>
#include <vector>
#include <mutex>

namespace universaldevkit::helpers::event {
    template<typename TSignature>
    class Signal;

    template<typename TRet, typename... TArgs>
    class Signal<TRet(TArgs...)> : public IEvent<void(TArgs...)> {
    public:
        static_assert(std::is_void_v<TRet>, "Signal currently supports only void return type");

        using MyBase_t = IEvent<void(TArgs...)>;
        using Signal_t = Signal<TRet(TArgs...)>;
        using HandlerFunc_t = typename MyBase_t::HandlerFunc_t;

    private:
        struct Subscription {
            HandlerFunc_t handlerFunc;
            bool connected = true;
        };

        struct State {
            std::mutex mutex;
            std::vector<std::weak_ptr<Subscription>> subscriptions;
        };

    public:
        class Connection : public ISubscriptionToken {
        public:
            Connection(std::weak_ptr<State> state, std::shared_ptr<Subscription> subscription)
                : state{ std::move(state) }
                , subscription{ std::move(subscription) } {
            }

            void Disconnect() {
                if (auto owner = state.lock()) {
                    std::scoped_lock lock{ owner->mutex };
                    subscription->connected = false;
                    subscription->handlerFunc = {};
                }
            }

            bool IsConnected() const {
                if (auto owner = state.lock()) {
                    std::scoped_lock lock{ owner->mutex };
                    return subscription->connected;
                }
                return false;
            }

        private:
            std::weak_ptr<State> state;
            std::shared_ptr<Subscription> subscription;
        };

        class ScopedConnection {
        public:
            using Signal_t = Signal<TRet(TArgs...)>;
            using Connection_t = typename Signal_t::Connection;

            ScopedConnection() = default;
            ScopedConnection(std::shared_ptr<Connection_t> connection)
                : connection{ std::move(connection) } {
            }

            ~ScopedConnection() {
                Disconnect();
            }

            ScopedConnection(const ScopedConnection&) = delete;
            ScopedConnection& operator=(const ScopedConnection&) = delete;
            ScopedConnection(ScopedConnection&& other) noexcept = default;

            ScopedConnection& operator=(ScopedConnection&& other) {
                if (this != &other) {
                    Disconnect();
                    connection = std::move(other.connection);
                }
                return *this;
            }

            void Disconnect() {
                if (connection) {
                    connection->Disconnect();
                    connection.reset();
                }
            }

            bool IsConnected() const {
                return connection && connection->IsConnected();
            }

        private:
            std::shared_ptr<Connection_t> connection;
        };

        Signal() = default;
        Signal(const Signal&) = delete;
        Signal& operator=(const Signal&) = delete;
        Signal(Signal&&) = delete;
        Signal& operator=(Signal&&) = delete;

        ~Signal() override {
            DisconnectAll();
        }

        std::shared_ptr<ISubscriptionToken> Subscribe(const HandlerFunc_t& handlerFunction) override {
            return AddHandler(handlerFunction);
        }

        template<typename TCallable>
        std::shared_ptr<Connection> Subscribe(TCallable&& callable) {
            return AddHandler(HandlerFunc_t{ std::forward<TCallable>(callable) });
        }

        template<typename TClass>
        std::shared_ptr<Connection> Subscribe(TClass* objectPtr, void (TClass::*method)(TArgs...)) {
            return AddHandler(std::bind_front(method, objectPtr));
        }

        template<typename TClass>
        std::shared_ptr<Connection> Subscribe(const TClass* objectPtr, void (TClass::*method)(TArgs...) const) {
            return AddHandler(std::bind_front(method, objectPtr));
        }

        void Unsubscribe(std::shared_ptr<ISubscriptionToken> subscriptionToken) override {
            if (auto connection = std::dynamic_pointer_cast<Connection>(subscriptionToken)) {
                connection->Disconnect();
            }
        }

        void Invoke(const TArgs&... args) override {
            // Snapshot handlers under the lock; user callbacks run outside it.
            std::vector<HandlerFunc_t> handlersSnapshot;
            {
                std::scoped_lock lock{ state->mutex };
                for (const auto& weakSubscription : state->subscriptions) {
                    if (auto subscription = weakSubscription.lock(); subscription && subscription->connected) {
                        handlersSnapshot.push_back(subscription->handlerFunc);
                    }
                }
            }

            for (auto& handlerFunc : handlersSnapshot) {
                handlerFunc(args...);
            }
        }

        void DisconnectAll() {
            std::scoped_lock lock{ state->mutex };
            for (const auto& weakSubscription : state->subscriptions) {
                if (auto subscription = weakSubscription.lock()) {
                    subscription->connected = false;
                    subscription->handlerFunc = {};
                }
            }
            state->subscriptions.clear();
        }

    private:
        std::shared_ptr<Connection> AddHandler(HandlerFunc_t handlerFunc) {
            auto subscription = std::make_shared<Subscription>(Subscription{ std::move(handlerFunc) });
            auto connection = std::make_shared<Connection>(state, subscription);
            std::scoped_lock lock{ state->mutex };
            std::erase_if(state->subscriptions, [](const auto& item) {
                auto subscription = item.lock();
                return !subscription || !subscription->connected;
            });
            state->subscriptions.push_back(subscription);
            return connection;
        }

        std::shared_ptr<State> state = std::make_shared<State>();
    };
}