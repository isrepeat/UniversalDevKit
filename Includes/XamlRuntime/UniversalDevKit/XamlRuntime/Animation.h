#pragma once
#include "VisualState.h"

#include <unordered_map>
#include <functional>
#include <chrono>
#include <memory>
#include <string>
#include <any>

namespace xaml {
    class Element;
    class AnimationRegistry;

    enum class PresencePhase { hidden, appearing, visible, disappearing };

    class AnimationParameters final {
    public:
        template <typename T>
        static AnimationParameters Create(T value) {
            AnimationParameters result;
            result.data = std::make_shared<const std::any>(std::move(value));
            return result;
        }

        template <typename T>
        const T* TryGet() const {
            return this->data ? std::any_cast<T>(this->data.get()) : nullptr;
        }

    private:
        std::shared_ptr<const std::any> data;
    };

    struct RunningAnimation {
        float* field;
        float from;
        float to;
        float elapsed;
        float duration;
        Easing easing;
        AnimatedProperty property = AnimatedProperty::opacity;
        bool presence = true;
        bool isColor = false;
        std::array<float, 4> fromColor{};
        std::array<float, 4> toColor{};
    };

    // Служебное состояние анимации элемента; обработчики получают доступ через контексты.
    struct AnimationState {
        std::shared_ptr<const AnimationRegistry> registry;
        AnimationParameters parameters;
        std::vector<RunningAnimation> tracks;
        AnimationTrigger trigger = AnimationTrigger::show;
        PresencePhase phase = PresencePhase::hidden;
        bool targetVisible = false;
        bool removing = false;
        std::chrono::steady_clock::time_point updatedAt{};
    };

    // Нетипизированный контекст вызова. Типизированные контексты предоставляют своё состояние и общую трансформацию.
    class AnimationInvocation {
    public:
        AnimationInvocation(Element& element, AnimationTrigger trigger, bool startingFromHidden = false,
            const AnimationSettings* settings = nullptr);
        Element& Target();
        AnimationTrigger Trigger() const;
        bool IsStartingFromHidden() const;
        const AnimationSettings& Settings() const;
        const AnimationParameters& Parameters() const;
        ElementStates& Storage();
        VisualTransform& Transform();
        void AnimateTransform(float VisualTransform::* member, float to,
            std::chrono::milliseconds duration, Easing easing = Easing::cubicOut);
        void AnimateProperty(AnimatedProperty property, float from, float to,
            std::chrono::milliseconds duration, Easing easing = Easing::cubicOut);
        void StartDefaultAnimation();

    private:
        template<typename TState>
        friend class AnimationContext;
        void AnimateField(float& field, float to, std::chrono::milliseconds duration, Easing easing);

    private:
        Element& element;
        AnimationTrigger trigger;
        bool startingFromHidden;
        bool defaultStarted = false;
        const AnimationSettings* settings;
    };

    template<typename TState>
    class AnimationContext final : private AnimationInvocation {
    public:
        AnimationContext(const AnimationInvocation& invocation, TState& state)
            : AnimationInvocation(invocation)
            , state(state) {
        }

        using AnimationInvocation::Target;
        using AnimationInvocation::Trigger;
        using AnimationInvocation::IsStartingFromHidden;
        using AnimationInvocation::Parameters;
        using AnimationInvocation::Settings;
        using AnimationInvocation::AnimateProperty;
        using AnimationInvocation::Transform;
        using AnimationInvocation::AnimateTransform;
        using AnimationInvocation::StartDefaultAnimation;

        TState& State() {
            return this->state;
        }

        void Animate(float TState::* member, float to, std::chrono::milliseconds duration,
            Easing easing = Easing::cubicOut) {
            if (member == nullptr) {
                throw std::invalid_argument("Animation field is required");
            }
            this->AnimateField(this->state.*member, to, duration, easing);
        }

    private:
        TState& state;
    };

    class AnimationRegistry final {
    public:
        explicit AnimationRegistry(StateRegistry states = {});

        template<typename TState>
        void Register(std::string name, std::initializer_list<OptionBinding<TState>> options,
            bool (*handler)(AnimationContext<TState>&)) {
            this->states.Require(std::type_index(typeid(TState)));
            if (name.empty() || handler == nullptr) {
                throw std::invalid_argument("Animation name and handler are required");
            }
            OptionSchema<TState> schema(options);
            Entry entry{
                std::type_index(typeid(TState)),
                [schema](const AnimationSettings& settings) {
                    schema.Bind(TState{}, settings);
                },
                [schema, handler](AnimationInvocation& invocation) {
                    auto& state = invocation.Storage().Get<TState>();
                    const TState original = state;
                    state = schema.Bind(state, invocation.Settings());
                    AnimationContext<TState> context(invocation, state);
                    try {
                        if (handler(context)) {
                            return true;
                        }
                    } catch (...) {
                        state = original;
                        throw;
                    }
                    state = original;
                    return false;
                },
            };
            if (!this->handlers.emplace(std::move(name), std::move(entry)).second) {
                throw std::invalid_argument("Animation name already registered");
            }
        }

        void Prepare(Element& element) const;
        void ValidateTree(const Element& element) const;
        bool Configure(const std::string& name, AnimationInvocation& context) const;

    private:
        struct Entry {
            std::type_index stateType;
            std::function<void(const AnimationSettings&)> validate;
            std::function<bool(AnimationInvocation&)> invoke;
        };

    private:
        StateRegistry states;
        std::unordered_map<std::string, Entry> handlers;
    };

    class AnimationController final {
    public:
        void Attach(Element& root, const AnimationRegistry& registry, bool animateInitial = false);
        void Animate(Element& target, AnimatedProperty property, float from, float to,
            std::chrono::milliseconds duration, Easing easing = Easing::cubicOut);
        void ReleaseScrollExtentAfter(Element& scrollViewer, std::chrono::milliseconds duration);
        void Start(Element& target, AnimationTrigger trigger);
        void SetPlaybackRate(float value);
        void Update();
        bool IsAnimating() const;

        static void Synchronize(Element& element);
        static void Update(Element& root, std::chrono::duration<float, std::milli> elapsed);
        static bool IsAnimating(const Element& root);

        static bool GoToVisualState(Element& scope, const std::string& groupName,
            const std::string& stateName, bool useTransitions = true);

    private:
        struct Root {
            Element* element;
            std::weak_ptr<int> lifetime;
        };

        struct DeferredScrollExtentRelease {
            Element* element;
            std::weak_ptr<int> lifetime;
            std::chrono::steady_clock::time_point expiresAt;
        };

        friend class Element;
        friend class AnimationInvocation;
        void TrackRoot(Element& root);
        static bool StartStoryboards(Element& element, AnimationTrigger trigger, bool fromHidden);
        static bool StartTracks(Element& target, const std::vector<AnimationTrack>& tracks,
            AnimationTrigger trigger, bool useTransitions, bool fromHidden = false);
        static void AddPropertyTrack(Element& target, AnimatedProperty property, float from, float to,
            std::chrono::milliseconds duration, Easing easing, bool presence);
        static void AddColorTrack(Element& target, const AnimationTrack& track, bool useTransitions,
            bool presence);
        static void Configure(Element& element, AnimationTrigger trigger, bool fromHidden);
        static void StartDescendantStoryboards(Element& element, AnimationTrigger trigger,
            const AnimationParameters& parameters);
        static void AttachTree(Element& element, std::shared_ptr<const AnimationRegistry> registry,
            bool parentVisible, bool animateInitial, const AnimationParameters& parameters);
        static void SynchronizeTree(Element& element, bool parentVisible,
            const AnimationParameters& parameters);
        static void Advance(Element& element, float milliseconds);
        static bool HasPresenceTracks(const Element& element);

    private:
        std::vector<Root> roots;
        std::vector<DeferredScrollExtentRelease> deferredScrollExtentReleases;
        float playbackRate = 1.0f;
    };

    class VisualStateManager final {
    public:
        static bool GoToState(Element& scope, const std::string& groupName,
            const std::string& stateName, bool useTransitions = true);
    };
}