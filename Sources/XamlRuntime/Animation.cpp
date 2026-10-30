#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/Animation.h"

#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/ElementBuilder.h"
#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/XamlLayout.h"

#include <stdexcept>
#include <algorithm>
#include <cmath>

namespace xaml::_details {
    attr::Color AnimatedColor(const Element& target, AnimatedProperty property) {
        switch (property) {
        case AnimatedProperty::background: return target.Background();
        case AnimatedProperty::foreground: return target.Foreground();
        case AnimatedProperty::borderColor: return target.BorderColor();
        case AnimatedProperty::tint: return target.Tint();
        default: throw std::invalid_argument("Unsupported animated color property");
        }
    }

    std::array<float, 4> ColorChannels(const attr::Color& color) {
        return {color.red, color.green, color.blue, color.alpha};
    }

    void SetAnimatedColor(Element& target, AnimatedProperty property, const std::array<float, 4>& channels) {
        const attr::Color color{channels[0], channels[1], channels[2], channels[3]};
        switch (property) {
        case AnimatedProperty::background: target.SetBackground(color); break;
        case AnimatedProperty::foreground: target.SetForeground(color); break;
        case AnimatedProperty::borderColor: target.SetBorderColor(color); break;
        case AnimatedProperty::tint: target.SetTint(color); break;
        default: throw std::invalid_argument("Unsupported animated color property");
        }
    }

    void SetAnimatedValue(Element& target, AnimatedProperty property, float value) {
        if (property == AnimatedProperty::opacity) {
            target.SetOpacity(value);
        } else if (property == AnimatedProperty::renderOffsetX) {
            target.SetRenderOffsetX(value);
        } else if (property == AnimatedProperty::renderOffsetY) {
            target.SetRenderOffsetY(value);
        } else if (property == AnimatedProperty::height) {
            target.SetHeight(value);
        } else if (property == AnimatedProperty::toggleProgress) {
            target.SetToggleProgress(value);
        } else {
            target.SetPressProgress(value);
        }
    }

    float AnimatedValue(const Element& target, AnimatedProperty property, AnimationTrigger trigger) {
        if (property == AnimatedProperty::opacity) {
            return target.Opacity();
        }
        if (property == AnimatedProperty::renderOffsetX) {
            return target.RenderOffsetX();
        }
        if (property == AnimatedProperty::renderOffsetY) {
            return target.RenderOffsetY();
        }
        if (property == AnimatedProperty::height) {
            return target.Height();
        }
        if (property == AnimatedProperty::toggleProgress) {
            if (target.ToggleProgress() < 0.0f && trigger == AnimationTrigger::toggled) {
                // HandleTap already changed IsOn; the first animation starts at the previous state.
                return target.IsOn() ? 0.0f : 1.0f;
            }
            return target.ToggleProgress() < 0.0f
                ? (target.IsOn() ? 1.0f : 0.0f) : target.ToggleProgress();
        }
        return target.PressProgress();
    }
}

namespace xaml {
    AnimationTrack AnimationTrack::Color(AnimatedProperty property, const attr::Color& from, const attr::Color& to,
        std::chrono::milliseconds duration, Easing easing, bool fromCurrent) {
        if (property != AnimatedProperty::background && property != AnimatedProperty::foreground
            && property != AnimatedProperty::borderColor && property != AnimatedProperty::tint) {
            throw std::invalid_argument("Unsupported animated color property");
        }
        AnimationTrack track;
        track.property = property;
        track.fromCurrent = fromCurrent;
        track.duration = duration;
        track.easing = easing;
        track.isColor = true;
        track.fromColor = _details::ColorChannels(from);
        track.toColor = _details::ColorChannels(to);
        return track;
    }

    //
    // API
    //
    void AnimationSettings::Set(std::string name, std::string value) {
        this->values.insert_or_assign(std::move(name), std::move(value));
    }

    const std::string& AnimationSettings::Get(const std::string& name) const {
        static const std::string empty;
        const auto found = this->values.find(name);
        return found == this->values.end() ? empty : found->second;
    }

    float AnimationSettings::Number(const std::string& name, float fallback) const {
        const auto found = this->values.find(name);
        if (found == this->values.end()) {
            return fallback;
        }
        size_t consumed = 0;
        const float value = std::stof(found->second, &consumed);
        if (consumed != found->second.size() || !std::isfinite(value)) {
            throw std::invalid_argument("Invalid animation number: " + name);
        }
        return value;
    }

    const std::unordered_map<std::string, std::string>& AnimationSettings::Values() const {
        return this->values;
    }

    AnimationInvocation::AnimationInvocation(Element& element, AnimationTrigger trigger, bool startingFromHidden,
        const AnimationSettings* settings)
        : element(element)
        , trigger(trigger)
        , startingFromHidden(startingFromHidden)
        , settings(settings) {
    }

    //
    // API
    //
    Element& AnimationInvocation::Target() {
        return this->element;
    }

    AnimationTrigger AnimationInvocation::Trigger() const {
        return this->trigger;
    }

    bool AnimationInvocation::IsStartingFromHidden() const {
        return this->startingFromHidden;
    }

    const AnimationSettings& AnimationInvocation::Settings() const {
        static const AnimationSettings empty;
        return this->settings ? *this->settings : empty;
    }

    const AnimationParameters& AnimationInvocation::Parameters() const {
        return this->element.animationState.parameters;
    }

    ElementStates& AnimationInvocation::Storage() {
        return this->element.States();
    }

    VisualTransform& AnimationInvocation::Transform() {
        return this->Storage().Get<VisualTransform>();
    }

    void AnimationInvocation::AnimateTransform(float VisualTransform::* member, float to,
        std::chrono::milliseconds duration, Easing easing) {
        if (member == nullptr) {
            throw std::invalid_argument("Transform field is required");
        }
        this->AnimateField(this->Transform().*member, to, duration, easing);
    }

    void AnimationInvocation::AnimateProperty(AnimatedProperty property, float from, float to,
        std::chrono::milliseconds duration, Easing easing) {
        AnimationController::AddPropertyTrack(this->element, property, from, to, duration, easing,
            this->trigger == AnimationTrigger::show || this->trigger == AnimationTrigger::hide);
    }

    void AnimationInvocation::StartDefaultAnimation() {
        if (this->defaultStarted) {
            return;
        }
        this->defaultStarted = true;
        const auto& state = this->element.animationState;
        AnimationInvocation fallback(this->element, this->trigger, this->startingFromHidden);
        fallback.defaultStarted = true;
        if (state.registry && !this->element.defaultAnimation.empty()
            && state.registry->Configure(this->element.defaultAnimation, fallback)) {
            return;
        }
        if (this->trigger == AnimationTrigger::show || this->trigger == AnimationTrigger::hide) {
            auto& transform = this->Storage().Get<VisualTransform>();
            transform.opacity = 1.0f;
            transform.offsetX = 0.0f;
            transform.offsetY = 0.0f;
        }
    }

    //
    // Internal
    //
    void AnimationInvocation::AnimateField(float& field, float value,
        std::chrono::milliseconds duration, Easing easing) {
        if (duration.count() < 0 || !std::isfinite(value) || !std::isfinite(field)) {
            throw std::invalid_argument("Invalid field animation");
        }
        auto& tracks = this->element.animationState.tracks;
        tracks.erase(std::remove_if(tracks.begin(), tracks.end(),
            [&field](const RunningAnimation& track) { return track.field == &field; }), tracks.end());
        if (duration.count() == 0) {
            field = value;
            return;
        }
        tracks.push_back({&field, field, value, 0.0f, static_cast<float>(duration.count()), easing,
            AnimatedProperty::opacity,
            this->trigger == AnimationTrigger::show || this->trigger == AnimationTrigger::hide});
    }

    AnimationRegistry::AnimationRegistry(StateRegistry states)
        : states(std::move(states)) {
    }

    //
    // API
    //
    void AnimationRegistry::Prepare(Element& element) const {
        element.States().Prepare(this->states, std::type_index(typeid(VisualTransform)));
        for (const auto& storyboard : element.Storyboards()) {
            for (const auto& track : storyboard.tracks) {
                const auto found = this->handlers.find(track.name);
                if (found != this->handlers.end()) {
                    found->second.validate(track.settings);
                    element.States().Prepare(this->states, found->second.stateType);
                }
            }
        }
        const auto fallback = this->handlers.find(element.DefaultAnimation());
        if (fallback != this->handlers.end()) {
            fallback->second.validate(AnimationSettings{});
            element.States().Prepare(this->states, fallback->second.stateType);
        }
    }

    void AnimationRegistry::ValidateTree(const Element& element) const {
        const auto validate = [this, &element](const AnimationTrack& track) {
            if (track.name.empty()) {
                return;
            }
            const auto found = this->handlers.find(track.name);
            if (found == this->handlers.end()) {
                throw std::invalid_argument(element.SourcePath() + ":" + std::to_string(element.SourceLine())
                    + ":" + std::to_string(element.SourceColumn()) + ": Unknown animation '" + track.name + "'");
            }
            found->second.validate(track.settings);
        };
        for (const auto& storyboard : element.Storyboards()) {
            for (const auto& track : storyboard.tracks) {
                validate(track);
            }
        }
        for (const auto& group : element.VisualStateGroups()) {
            for (const auto& state : group.states) {
                for (const auto& track : state.tracks) {
                    validate(track.animation);
                }
            }
        }
        for (const auto& child : element.Children()) {
            this->ValidateTree(*child);
        }
    }

    bool AnimationRegistry::Configure(const std::string& name, AnimationInvocation& context) const {
        const auto found = this->handlers.find(name);
        if (found == this->handlers.end()) {
            return false;
        }
        context.Storage().Prepare(this->states, found->second.stateType);
        auto& tracks = context.Target().animationState.tracks;
        const auto original = tracks;
        context.Storage().Prepare(this->states, std::type_index(typeid(VisualTransform)));
        const auto originalTransform = context.Transform();
        try {
            if (found->second.invoke(context)) {
                return true;
            }
        } catch (...) {
            tracks = original;
            context.Transform() = originalTransform;
            throw;
        }
        tracks = original;
        context.Transform() = originalTransform;
        return false;
    }

    void AnimationController::Attach(Element& root, const AnimationRegistry& registry, bool animateInitial) {
        this->TrackRoot(root);
        AttachTree(root, std::make_shared<const AnimationRegistry>(registry), true, animateInitial, {});
        root.InvalidateLayout();
    }

    void AnimationController::Animate(Element& target, AnimatedProperty property, float from, float to,
        std::chrono::milliseconds duration, Easing easing) {
        this->TrackRoot(target);
        AddPropertyTrack(target, property, from, to, duration, easing, false);
    }

    void AnimationController::ReleaseScrollExtentAfter(Element& scrollViewer, std::chrono::milliseconds duration) {
        this->deferredScrollExtentReleases.push_back({
            &scrollViewer,
            scrollViewer.lifetimeToken,
            std::chrono::steady_clock::now()
                + std::chrono::duration_cast<std::chrono::milliseconds>(duration / this->playbackRate)});
    }

    void AnimationController::Start(Element& target, AnimationTrigger trigger) {
        this->TrackRoot(target);
        if (trigger == AnimationTrigger::show || trigger == AnimationTrigger::hide) {
            target.SetVisibility(trigger == AnimationTrigger::show
                ? attr::Visibility::visible : attr::Visibility::collapsed);
            return;
        }
        target.animationState.parameters = target.animationParametersProvider
            ? target.animationParametersProvider()
            : target.parent ? target.parent->animationState.parameters : AnimationParameters{};
        if (!target.animationState.registry) {
            static const AnimationRegistry emptyRegistry;
            emptyRegistry.Prepare(target);
        }
        Configure(target, trigger, false);
    }

    void AnimationController::SetPlaybackRate(float value) {
        if (!std::isfinite(value) || value <= 0.0f) {
            throw std::invalid_argument("Playback rate must be positive and finite");
        }
        this->playbackRate = value;
        for (const auto& root : this->roots) {
            if (!root.lifetime.expired()) {
                root.element->animationState.updatedAt = std::chrono::steady_clock::now();
            }
        }
    }

    void AnimationController::Update() {
        const auto now = std::chrono::steady_clock::now();
        this->roots.erase(std::remove_if(this->roots.begin(), this->roots.end(),
            [](const Root& root) { return root.lifetime.expired(); }), this->roots.end());
        // Обновляем только внешние корни: Animate() может отдельно отслеживать и дочерний элемент.
        for (const auto& root : this->roots) {
            if (root.lifetime.expired()) {
                continue;
            }
            bool covered = false;
            for (Element* parent = root.element->parent; parent != nullptr; parent = parent->parent) {
                covered = std::any_of(this->roots.begin(), this->roots.end(),
                    [parent](const Root& other) { return other.element == parent; });
                if (covered) {
                    break;
                }
            }
            if (!covered) {
                const auto previous = root.element->animationState.updatedAt;
                root.element->animationState.updatedAt = now;
                const float elapsed = previous.time_since_epoch().count() == 0 ? 0.0f
                    : std::chrono::duration<float, std::milli>(now - previous).count();
                Advance(*root.element, elapsed * this->playbackRate);
            }
        }
        for (const auto& release : this->deferredScrollExtentReleases) {
            if (!release.lifetime.expired() && release.expiresAt <= now) {
                release.element->ReleaseScrollExtent();
            }
        }
        this->deferredScrollExtentReleases.erase(std::remove_if(
            this->deferredScrollExtentReleases.begin(),
            this->deferredScrollExtentReleases.end(),
            [now](const DeferredScrollExtentRelease& release) {
                return release.lifetime.expired() || release.expiresAt <= now;
            }), this->deferredScrollExtentReleases.end());
    }

    bool AnimationController::IsAnimating() const {
        for (const auto& root : this->roots) {
            if (!root.lifetime.expired() && AnimationController::IsAnimating(*root.element)) {
                return true;
            }
        }
        return !this->deferredScrollExtentReleases.empty();
    }

    void AnimationController::Synchronize(Element& element) {
        Element* root = &element;
        while (root->parent != nullptr) {
            root = root->parent;
        }
        // Время простоя перед новым переходом не должно учитываться в его длительности.
        if (!IsAnimating(*root)) {
            root->animationState.updatedAt = std::chrono::steady_clock::now();
        }
        const bool parentVisible = element.parent == nullptr
            || (element.parent->animationState.registry ? element.parent->animationState.targetVisible
                : element.parent->IsPresent());
        const AnimationParameters inherited = element.parent == nullptr
            ? AnimationParameters{} : element.parent->animationState.parameters;
        SynchronizeTree(element, parentVisible, inherited);
    }

    void AnimationController::Update(Element& root, std::chrono::duration<float, std::milli> elapsed) {
        if (elapsed.count() < 0.0f || !std::isfinite(elapsed.count())) {
            throw std::invalid_argument("Invalid animation elapsed time");
        }
        Advance(root, elapsed.count());
    }

    bool AnimationController::IsAnimating(const Element& root) {
        if (!root.animationState.tracks.empty()
            || root.animationState.phase == PresencePhase::appearing
            || root.animationState.phase == PresencePhase::disappearing) {
            return true;
        }
        for (const auto& child : root.children) {
            if (IsAnimating(*child)) {
                return true;
            }
        }
        return false;
    }

    //
    // Internal
    //
    void AnimationController::TrackRoot(Element& root) {
        if (!IsAnimating(root)) {
            Element* outer = &root;
            while (outer->parent != nullptr) {
                outer = outer->parent;
            }
            if (!IsAnimating(*outer)) {
                outer->animationState.updatedAt = std::chrono::steady_clock::now();
            }
            root.animationState.updatedAt = std::chrono::steady_clock::now();
        }
        const auto found = std::find_if(this->roots.begin(), this->roots.end(),
            [&root](const Root& tracked) {
                return !tracked.lifetime.expired() && tracked.element == &root;
            });
        if (found == this->roots.end()) {
            this->roots.push_back({&root, root.lifetimeToken});
        }
    }

    bool AnimationController::StartStoryboards(Element& target, AnimationTrigger trigger, bool fromHidden) {
        bool handled = false;
        for (const Storyboard& storyboard : target.Storyboards()) {
            if (storyboard.trigger != trigger) {
                continue;
            }
            if (storyboard.tracks.empty()) {
                handled = true;
            }
            handled = StartTracks(target, storyboard.tracks, trigger, true, fromHidden) || handled;
        }
        return handled;
    }

    bool AnimationController::StartTracks(Element& target, const std::vector<AnimationTrack>& tracks,
        AnimationTrigger trigger, bool useTransitions, bool fromHidden) {
        bool handled = false;
        static const AnimationRegistry emptyRegistry;
        for (const AnimationTrack& track : tracks) {
            if (!track.name.empty()) {
                AnimationInvocation context(target, trigger, fromHidden, &track.settings);
                const auto& registry = target.animationState.registry ? *target.animationState.registry : emptyRegistry;
                handled = registry.Configure(track.name, context) || handled;
                continue;
            }
            handled = true;
            if (track.isColor) {
                AddColorTrack(target, track, useTransitions,
                    trigger == AnimationTrigger::show || trigger == AnimationTrigger::hide);
                continue;
            }
            AddPropertyTrack(target, track.property,
                track.fromCurrent ? _details::AnimatedValue(target, track.property, trigger) : track.from,
                track.toToggleState ? (target.IsOn() ? 1.0f : 0.0f) : track.to,
                useTransitions ? track.duration : std::chrono::milliseconds(0), track.easing,
                trigger == AnimationTrigger::show || trigger == AnimationTrigger::hide);
        }
        return handled;
    }

    bool AnimationController::GoToVisualState(Element& scope, const std::string& groupName,
        const std::string& stateName, bool useTransitions) {
        const auto group = std::find_if(scope.visualStateGroups.begin(), scope.visualStateGroups.end(),
            [&groupName](const VisualStateGroup& value) { return value.name == groupName; });
        if (group == scope.visualStateGroups.end()) {
            return false;
        }
        const auto state = std::find_if(group->states.begin(), group->states.end(),
            [&stateName](const VisualState& value) { return value.name == stateName; });
        if (state == group->states.end()) {
            return false;
        }
        if (group->currentState == stateName) {
            return true;
        }
        const auto findTarget = [&scope](const std::string& name) -> Element* {
            std::function<Element*(Element&)> find = [&](Element& element) -> Element* {
                if (element.Id() == name) {
                    return &element;
                }
                for (const auto& child : element.Children()) {
                    if (Element* const result = find(*child)) {
                        return result;
                    }
                }
                return nullptr;
            };
            return find(scope);
        };
        for (const VisualStateSetter& setter : state->setters) {
            Element* const target = findTarget(setter.targetName);
            if (target == nullptr) {
                throw std::invalid_argument("Visual state target was not found: " + setter.targetName);
            }
            if (setter.property == "width" && setter.value == "Auto") {
                target->SetWidth(0.0f);
            } else {
                SetAttribute(*target, setter.property, setter.value);
            }
        }
        for (const VisualStateTrack& track : state->tracks) {
            Element* const target = findTarget(track.targetName);
            if (target == nullptr) {
                throw std::invalid_argument("Visual state target was not found: " + track.targetName);
            }
            StartTracks(*target, {track.animation}, AnimationTrigger::visualState, useTransitions);
        }
        group->currentState = stateName;
        return true;
    }

    bool VisualStateManager::GoToState(Element& scope, const std::string& groupName,
        const std::string& stateName, bool useTransitions) {
        return AnimationController::GoToVisualState(scope, groupName, stateName, useTransitions);
    }

    void AnimationController::AddPropertyTrack(Element& target, AnimatedProperty property,
        float from, float to, std::chrono::milliseconds duration, Easing easing, bool presence) {
        if (duration.count() < 0 || !std::isfinite(from) || !std::isfinite(to)) {
            throw std::invalid_argument("Invalid property animation");
        }
        auto& tracks = target.animationState.tracks;
        tracks.erase(std::remove_if(tracks.begin(), tracks.end(),
            [property](const RunningAnimation& track) { return track.field == nullptr && track.property == property; }),
            tracks.end());
        _details::SetAnimatedValue(target, property, duration.count() == 0 ? to : from);
        if (duration.count() != 0) {
            tracks.push_back({nullptr, from, to, 0.0f, static_cast<float>(duration.count()), easing, property, presence});
        }
    }

    void AnimationController::AddColorTrack(Element& target, const AnimationTrack& track, bool useTransitions,
        bool presence) {
        const auto from = track.fromCurrent ? _details::ColorChannels(_details::AnimatedColor(target, track.property))
            : track.fromColor;
        const auto valid = [](const std::array<float, 4>& color) {
            return std::all_of(color.begin(), color.end(), [](float channel) {
                return std::isfinite(channel) && channel >= 0.0f && channel <= 1.0f;
            });
        };
        if (track.duration.count() < 0 || !valid(from) || !valid(track.toColor)) {
            throw std::invalid_argument("Invalid color animation");
        }
        auto& tracks = target.animationState.tracks;
        tracks.erase(std::remove_if(tracks.begin(), tracks.end(), [&track](const RunningAnimation& running) {
            return running.field == nullptr && running.property == track.property;
        }), tracks.end());
        const auto duration = useTransitions ? track.duration : std::chrono::milliseconds(0);
        _details::SetAnimatedColor(target, track.property, duration.count() == 0 ? track.toColor : from);
        if (duration.count() != 0) {
            RunningAnimation running{nullptr, 0.0f, 0.0f, 0.0f, static_cast<float>(duration.count()),
                track.easing, track.property, presence};
            running.isColor = true;
            running.fromColor = from;
            running.toColor = track.toColor;
            tracks.push_back(running);
        }
    }

    void AnimationController::Configure(Element& element, AnimationTrigger trigger, bool fromHidden) {
        auto& state = element.animationState;
        state.trigger = trigger;
        if (StartStoryboards(element, trigger, fromHidden)) {
            return;
        }
        AnimationInvocation context(element, trigger, fromHidden);
        context.StartDefaultAnimation();
    }

    bool AnimationController::HasPresenceTracks(const Element& element) {
        return std::any_of(element.animationState.tracks.begin(), element.animationState.tracks.end(),
            [](const RunningAnimation& track) { return track.presence; });
    }

    void AnimationController::AttachTree(Element& element, std::shared_ptr<const AnimationRegistry> registry,
        bool parentVisible, bool animateInitial, const AnimationParameters& parameters) {
        auto& state = element.animationState;
        state.registry = std::move(registry);
        state.updatedAt = std::chrono::steady_clock::now();
        state.targetVisible = element.visibility == attr::Visibility::visible;
        state.phase = state.targetVisible ? PresencePhase::visible : PresencePhase::hidden;
        state.parameters = parameters;
        state.tracks.clear();
        element.States().Clear();
        state.registry->Prepare(element);
        for (const auto& child : element.children) {
            AttachTree(*child, state.registry, state.targetVisible, false, parameters);
        }
        if (animateInitial && state.targetVisible) {
            state.targetVisible = false;
            state.phase = PresencePhase::hidden;
            // Сбрасываем и потомков, чтобы их первое появление начиналось из скрытого состояния.
            for (const auto& child : element.children) {
                AttachTree(*child, state.registry, false, false, parameters);
            }
            SynchronizeTree(element, parentVisible, parameters);
        }
    }

    void AnimationController::SynchronizeTree(Element& element, bool parentVisible,
        const AnimationParameters& parameters) {
        auto& state = element.animationState;
        if (!state.registry) {
            element.InvalidateLayout();
            return;
        }
        const bool visible = element.visibility == attr::Visibility::visible && !state.removing;
        const bool changed = visible != state.targetVisible;
        if (changed) {
            const bool fromHidden = state.phase == PresencePhase::hidden;
            state.parameters = element.animationParametersProvider ? element.animationParametersProvider() : parameters;
            state.targetVisible = visible;
            state.trigger = visible ? AnimationTrigger::show : AnimationTrigger::hide;
            state.phase = visible ? PresencePhase::appearing : PresencePhase::disappearing;
            state.tracks.erase(std::remove_if(state.tracks.begin(), state.tracks.end(),
                [](const RunningAnimation& track) { return track.presence; }), state.tracks.end());
            if (fromHidden) {
                auto& transform = element.States().Get<VisualTransform>();
                transform.opacity = 1.0f;
                transform.offsetX = 0.0f;
                transform.offsetY = 0.0f;
            }
            Configure(element, state.trigger, fromHidden);
            StartDescendantStoryboards(element, visible ? AnimationTrigger::parentShow : AnimationTrigger::parentHide,
                state.parameters);
        }
        for (const auto& child : element.children) {
            SynchronizeTree(*child, parentVisible, state.parameters);
        }
        // Visibility ребёнка не зависит от Visibility родителя.
        if (!HasPresenceTracks(element)) {
            state.phase = state.targetVisible ? PresencePhase::visible : PresencePhase::hidden;
        }
        element.InvalidateLayout();
    }

    void AnimationController::Advance(Element& element, float milliseconds) {
        auto& state = element.animationState;
        for (auto& track : state.tracks) {
            track.elapsed += milliseconds;
            float progress = std::min(1.0f, track.elapsed / track.duration);
            if (track.easing == Easing::cubicOut) {
                const float inverse = 1.0f - progress;
                progress = 1.0f - inverse * inverse * inverse;
            }
            if (track.isColor) {
                std::array<float, 4> color;
                for (size_t i = 0; i < color.size(); ++i) {
                    color[i] = track.fromColor[i] + (track.toColor[i] - track.fromColor[i]) * progress;
                }
                _details::SetAnimatedColor(element, track.property, color);
                continue;
            }
            const float value = track.from + (track.to - track.from) * progress;
            if (track.field != nullptr) {
                *track.field = value;
            } else {
                _details::SetAnimatedValue(element, track.property, value);
            }
        }
        state.tracks.erase(std::remove_if(state.tracks.begin(), state.tracks.end(),
            [](const RunningAnimation& track) { return track.elapsed >= track.duration; }), state.tracks.end());
        for (const auto& child : element.children) {
            Advance(*child, milliseconds);
        }
        if (state.registry && !HasPresenceTracks(element)) {
            const auto phase = state.targetVisible ? PresencePhase::visible : PresencePhase::hidden;
            if (state.phase != phase) {
                state.phase = phase;
                element.InvalidateLayout();
            }
        }
        const auto end = std::remove_if(element.children.begin(), element.children.end(),
            [](const auto& child) { return child->animationState.removing && !child->IsPresent(); });
        if (end != element.children.end()) {
            element.children.erase(end, element.children.end());
            element.InvalidateLayout();
        }
    }

    void AnimationController::StartDescendantStoryboards(Element& element, AnimationTrigger trigger,
        const AnimationParameters& parameters) {
        for (const auto& child : element.children) {
            auto& state = child->animationState;
            state.parameters = child->animationParametersProvider ? child->animationParametersProvider() : parameters;
            StartStoryboards(*child, trigger, false);
            StartDescendantStoryboards(*child, trigger, state.parameters);
        }
    }
}