#include "../../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/RuntimeMarkup/RuntimeTreeBuilder.h"

#include "../../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/RuntimeMarkup/XamlSchemaValidator.h"
#include "../../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/RuntimeMarkup/RuntimeDiagnostics.h"
#include "../../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/ElementBuilder.h"

#include <algorithm>
#include <cmath>

namespace universaldevkit::xamlruntime::runtimemarkup::details {
    std::string Attribute(const XamlElementNode& node, std::string_view name, std::string fallback = {}) {
        for (const auto& attribute : node.attributes) {
            if (attribute.name == name) {
                return attribute.value;
            }
        }
        return fallback;
    }

    std::string Trim(std::string value) {
        const auto first = value.find_first_not_of(" \t\r\n");
        if (first == std::string::npos) {
            return {};
        }
        return value.substr(first, value.find_last_not_of(" \t\r\n") - first + 1);
    }

    std::string BindingPath(const XamlAttributeNode& attribute, bool& twoWay) {
        const auto& value = attribute.value;
        if (value.rfind("{Binding ", 0) != 0 || value.back() != '}') {
            throw RuntimeDiagnostic(attribute.location, "Expected {Binding Path} or {Binding Path, Mode=TwoWay}");
        }
        auto path = Trim(value.substr(9, value.size() - 10));
        const auto comma = path.find(',');
        if (comma != std::string::npos) {
            const auto mode = Trim(path.substr(comma + 1));
            if (mode != "Mode=TwoWay" && mode != "Mode=OneWay") {
                throw RuntimeDiagnostic(attribute.location, "Unsupported binding mode");
            }
            twoWay = mode == "Mode=TwoWay";
            path = Trim(path.substr(0, comma));
        }
        if (path.rfind("Path=", 0) == 0) {
            path.erase(0, 5);
        }
        return path;
    }

    float Number(const XamlElementNode& node, std::string_view name, std::string fallback = "0") {
        const auto value = Attribute(node, name, fallback);
        try {
            size_t count = 0;
            const float result = std::stof(value, &count);
            if (count != value.size() || !std::isfinite(result)) {
                throw std::invalid_argument("number");
            }
            return result;
        } catch (const std::exception&) {
            throw RuntimeDiagnostic(node.location, "Invalid numeric animation attribute '" + std::string(name) + "'");
        }
    }

    AnimationTrack Track(const XamlElementNode& node) {
        if (node.name != "Animation" && node.name != "FloatAnimation" && node.name != "ColorAnimation") {
            throw RuntimeDiagnostic(node.location, "Expected Animation, FloatAnimation or ColorAnimation");
        }
        if (!node.children.empty()) {
            throw RuntimeDiagnostic(node.location, "Animation cannot contain children");
        }
        AnimationTrack result;
        if (node.name == "ColorAnimation") {
            const std::map<std::string, AnimatedProperty> colors{{"background", AnimatedProperty::background},
                {"foreground", AnimatedProperty::foreground}, {"borderBrush", AnimatedProperty::borderColor},
                {"tint", AnimatedProperty::tint}};
            const auto property = colors.find(Attribute(node, "property"));
            const auto from = Attribute(node, "from");
            const auto to = Attribute(node, "to");
            if (property == colors.end() || from.empty() || to.empty() || Attribute(node, "duration").empty()) {
                throw RuntimeDiagnostic(node.location, "ColorAnimation requires supported property, from, to and duration");
            }
            try {
                result = AnimationTrack::Color(property->second, from == "Current" ? attr::Color{} : ParseColor(from),
                    ParseColor(to), std::chrono::milliseconds(0), Easing::linear, from == "Current");
            } catch (const std::exception& error) {
                throw RuntimeDiagnostic(node.location, error.what());
            }
        }
        if (!result.isColor) {
            const std::map<std::string, AnimatedProperty> properties{{"opacity", AnimatedProperty::opacity},
                {"height", AnimatedProperty::height}, {"renderOffsetX", AnimatedProperty::renderOffsetX},
                {"renderOffsetY", AnimatedProperty::renderOffsetY}, {"toggleProgress", AnimatedProperty::toggleProgress},
                {"pressProgress", AnimatedProperty::pressProgress}};
            result.name = Attribute(node, "name");
            const auto property = Attribute(node, "property", "opacity");
            const auto found = properties.find(property);
            if (found == properties.end() || (node.name == "Animation" && result.name.empty())) {
                throw RuntimeDiagnostic(node.location, "Unknown animated property or missing animation name");
            }
            result.property = found->second;
            result.fromCurrent = Attribute(node, "from") == "Current";
            result.toToggleState = Attribute(node, "to") == "ToggleState";
            result.from = result.fromCurrent ? 0.0f : Number(node, "from");
            result.to = result.toToggleState ? 0.0f : Number(node, "to");
        }
        const float duration = Number(node, "duration");
        if (duration < 0 || duration > 86400000) {
            throw RuntimeDiagnostic(node.location, "Animation duration is out of range");
        }
        result.duration = std::chrono::milliseconds(static_cast<long long>(duration));
        const auto easing = Attribute(node, "easing", "Linear");
        if (easing != "Linear" && easing != "CubicOut") {
            throw RuntimeDiagnostic(node.location, "Unsupported easing '" + easing + "'");
        }
        result.easing = easing == "Linear" ? Easing::linear : Easing::cubicOut;
        for (const auto& attribute : node.attributes) {
            if (attribute.name != "name" && attribute.name != "property" && attribute.name != "targetName") {
                result.settings.Set(attribute.name, attribute.value);
            }
        }
        return result;
    }

    Storyboard BuildStoryboard(const XamlElementNode& node) {
        if (node.name != "Storyboard") {
            throw RuntimeDiagnostic(node.location, "Expected Storyboard");
        }
        Storyboard result;
        const std::map<std::string, AnimationTrigger> triggers{{"PointerDown", AnimationTrigger::pointerDown},
            {"PointerUp", AnimationTrigger::pointerUp}, {"Toggled", AnimationTrigger::toggled},
            {"Show", AnimationTrigger::show}, {"Hide", AnimationTrigger::hide},
            {"ParentShow", AnimationTrigger::parentShow}, {"ParentHide", AnimationTrigger::parentHide}};
        const auto trigger = triggers.find(Attribute(node, "trigger"));
        if (trigger == triggers.end()) {
            throw RuntimeDiagnostic(node.location, "Unknown storyboard trigger");
        }
        result.trigger = trigger->second;
        for (const auto& child : node.children) {
            result.tracks.push_back(Track(child));
        }
        return result;
    }

    std::vector<VisualStateGroup> BuildStates(const XamlElementNode& node) {
        std::vector<VisualStateGroup> result;
        for (const auto& group : node.children) {
            if (group.name != "VisualStateGroup" || Attribute(group, "name").empty()) {
                throw RuntimeDiagnostic(group.location, "Expected named VisualStateGroup");
            }
            VisualStateGroup value;
            value.name = Attribute(group, "name");
            for (const auto& state : group.children) {
                if (state.name != "VisualState" || Attribute(state, "name").empty()) {
                    throw RuntimeDiagnostic(state.location, "Expected named VisualState");
                }
                VisualState item;
                item.name = Attribute(state, "name");
                for (const auto& child : state.children) {
                    if (child.name == "Setters") {
                        for (const auto& setter : child.children) {
                            const auto targetName = Attribute(setter, "targetName");
                            const auto property = Attribute(setter, "property");
                            const auto value = Attribute(setter, "value");
                            if (setter.name != "Setter" || !setter.children.empty()
                                || targetName.empty() || property.empty() || value.empty()) {
                                throw RuntimeDiagnostic(setter.location,
                                    "Setter requires targetName, property and value");
                            }
                            if (property != "width" && property != "height"
                                && property != "horizontalAlignment" && property != "verticalAlignment"
                                && property != "background") {
                                throw RuntimeDiagnostic(setter.location, "Unsupported VisualState Setter property");
                            }
                            if ((property == "width" || property == "height") && value == "Auto") {
                                if (property == "height") {
                                    throw RuntimeDiagnostic(setter.location, "height Auto is not supported");
                                }
                            }
                            item.setters.push_back({targetName, property, value});
                        }
                        continue;
                    }
                    if (child.name != "Storyboard") {
                        throw RuntimeDiagnostic(child.location, "Expected Setters or Storyboard");
                    }
                    for (const auto& track : child.children) {
                        item.tracks.push_back({Attribute(track, "targetName"), Track(track)});
                    }
                }
                value.states.push_back(std::move(item));
            }
            result.push_back(std::move(value));
        }
        return result;
    }

    void ValidateStateTargets(const Element& element) {
        const auto contains = [](auto&& self, const Element& node, const std::string& id) -> bool {
            if (node.Id() == id) {
                return true;
            }
            for (const auto& child : node.Children()) {
                if (self(self, *child, id)) {
                    return true;
                }
            }
            return false;
        };
        std::set<std::string> groups;
        for (const auto& group : element.VisualStateGroups()) {
            if (!groups.insert(group.name).second) {
                throw RuntimeDiagnostic({element.SourcePath(), element.SourceLine(), element.SourceColumn()}, "Duplicate VisualStateGroup");
            }
            std::set<std::string> states;
            for (const auto& state : group.states) {
                if (!states.insert(state.name).second) {
                    throw RuntimeDiagnostic({element.SourcePath(), element.SourceLine(), element.SourceColumn()}, "Duplicate VisualState");
                }
                for (const auto& track : state.tracks) {
                    if (track.targetName.empty() || !contains(contains, element, track.targetName)) {
                        throw RuntimeDiagnostic({element.SourcePath(), element.SourceLine(), element.SourceColumn()},
                            "VisualState target '" + track.targetName + "' was not found");
                    }
                }
                for (const auto& setter : state.setters) {
                    if (setter.targetName.empty() || !contains(contains, element, setter.targetName)) {
                        throw RuntimeDiagnostic({element.SourcePath(), element.SourceLine(), element.SourceColumn()},
                            "VisualState target '" + setter.targetName + "' was not found");
                    }
                }
            }
        }
        for (const auto& child : element.Children()) {
            ValidateStateTargets(*child);
        }
    }
}

namespace universaldevkit::xamlruntime::runtimemarkup {
    //
    // API
    //
    RuntimeBuildResult RuntimeTreeBuilder::BuildPage(const XamlElementNode& root,
        const RuntimeBindingContext& context, Size availableSize) {
        std::set<std::string> controls;
        for (const auto& control : context.controls) {
            controls.insert(control.first);
        }
        XamlSchemaValidator{}.Validate(
            root,
            context.xamlNamespace,
            context.controlXmlNamespace,
            controls);
        RuntimeBuildResult result;
        // BindingScope владеет подписками и целевыми элементами. Он передаётся вместе
        // с корнем, чтобы подписки старого дерева уничтожились при его замене.
        result.bindings = std::make_unique<BindingScope>();
        result.root = this->BuildElement(root, context, *result.bindings);
        details::ValidateStateTargets(*result.root);
        layoutInViewport(*result.root, availableSize);
        return result;
    }

    std::unique_ptr<Element> RuntimeTreeBuilder::BuildElement(const XamlElementNode& node,
        const RuntimeBindingContext& context, BindingScope& bindings) {
        const bool control = !context.controlXmlNamespace.empty()
            && node.nameSpace == context.controlXmlNamespace;
        auto element = control ? context.controls.at(node.name)(bindings)
            : std::make_unique<Element>(ParseElementType(node.name));
        element->SetSourceLocation(node.location.path, node.location.line, node.location.column);
        for (const auto& attribute : node.attributes) {
            if (attribute.nameSpace == "http://schemas.microsoft.com/winfx/2006/xaml") {
                if (attribute.name == "Name") {
                    element->SetId(attribute.value);
                }
                continue;
            }
            if (attribute.value.empty() || attribute.value.front() != '{') {
                try {
                    SetAttribute(*element, attribute.name, attribute.value);
                } catch (const std::exception& error) {
                    throw RuntimeDiagnostic(attribute.location, error.what());
                }
                continue;
            }
            bool twoWay = false;
            const auto path = details::BindingPath(attribute, twoWay);
            const auto* entry = context.bindings->Find(path);
            if (entry == nullptr) {
                throw RuntimeDiagnostic(attribute.location, "Binding '" + path + "' is not published by "
                    + context.owner + ". Available bindings: " + context.bindings->Available());
            }
            if (attribute.name == "command" && entry->kind == RuntimeBindingRegistry::Entry::Kind::command && !twoWay) {
                element->SetCommand(entry->command);
                continue;
            }
            if (attribute.name == "itemsSource" && entry->kind == RuntimeBindingRegistry::Entry::Kind::collection && !twoWay) {
                if (control) {
                    // Native-контрол сам интерпретирует ItemsSource в своём шаблоне.
                    // Автоматическое создание ListView здесь привело бы к двум владельцам коллекции.
                    continue;
                }
                const auto property = std::find_if(node.children.begin(), node.children.end(), [](const auto& child) {
                    return child.name == "ListView.ItemTemplate";
                });
                if (property == node.children.end()) {
                    throw RuntimeDiagnostic(attribute.location, "Collection requires ListView.ItemTemplate");
                }
                const auto itemNode = property->children.at(0).children.at(0);
                const auto descriptor = entry->collection;
                // Проверяем весь шаблон даже у пустой коллекции, чтобы ошибка была
                // показана сразу, а не при появлении первого элемента.
                RuntimeBindingContext itemContext = context;
                itemContext.bindings = descriptor.itemBindings(nullptr);
                itemContext.owner += " item";
                BindingScope probeBindings;
                auto probe = this->BuildElement(itemNode, itemContext, probeBindings);
                details::ValidateStateTargets(*probe);
                descriptor.bind(*element, [descriptor, itemNode, context](const void* item, BindingScope& scope) {
                    RuntimeBindingContext itemContext = context;
                    itemContext.bindings = descriptor.itemBindings(item);
                    itemContext.owner += " item";
                    auto result = RuntimeTreeBuilder{}.BuildElement(itemNode, itemContext, scope);
                    result->SetDataContext(item);
                    return result;
                });
                continue;
            }
            const auto target = bindings.AddRuntimeTarget(*element);
            const auto name = attribute.name;
            const auto registry = context.bindings;
            std::function<void()> apply;
            if (entry->kind == RuntimeBindingRegistry::Entry::Kind::text && name != "command" && name != "itemsSource") {
                apply = [target, name, registry, entry]() { SetAttribute(**target, name, entry->text()); };
            } else if (entry->kind == RuntimeBindingRegistry::Entry::Kind::boolean
                && (name == "isOn" || name == "isEnabled" || name == "visibility")) {
                apply = [target, name, registry, entry]() {
                    SetAttribute(**target, name, name == "visibility" ? (entry->boolean() ? "Visible" : "Collapsed")
                        : (entry->boolean() ? "true" : "false"));
                };
            } else {
                throw RuntimeDiagnostic(attribute.location, "Binding type is incompatible with '" + name + "'");
            }
            if (twoWay && (!entry->setBoolean || name != "isOn")) {
                throw RuntimeDiagnostic(attribute.location, "TwoWay binding requires a writable boolean and isOn target");
            }
            try {
                apply();
            } catch (const std::exception& error) {
                throw RuntimeDiagnostic(attribute.location, error.what());
            }
            if (entry->subscribe) {
                // Подписка принадлежит BindingScope и автоматически снимается вместе
                // с заменённым деревом, поэтому старый UI больше не получает обновления.
                bindings.AddRuntimeSubscription(entry->subscribe(apply));
            }
            if ((twoWay || name == "isOn") && entry->setBoolean) {
                (*target)->SetRuntimeSourceUpdate([target, registry, entry]() { entry->setBoolean((*target)->IsOn()); });
            }
        }
        for (const auto& child : node.children) {
            if (child.name == "rowDefinitions" || child.name == "Grid.rowDefinitions"
                || child.name == "columnDefinitions" || child.name == "Grid.columnDefinitions") {
                std::string value;
                for (const auto& definition : child.children) {
                    value += (value.empty() ? "" : ",") + definition.attributes.at(0).value;
                }
                if (child.name.find("rowDefinitions") != std::string::npos) {
                    element->SetRows(value);
                } else {
                    element->SetColumns(value);
                }
            } else if (child.name == node.name + ".Storyboards") {
                std::vector<Storyboard> storyboards;
                for (const auto& storyboard : child.children) {
                    storyboards.push_back(details::BuildStoryboard(storyboard));
                }
                element->SetStoryboards(std::move(storyboards));
            } else if (child.name == "VisualStateManager.VisualStateGroups") {
                element->SetVisualStateGroups(details::BuildStates(child));
            } else if (child.name != "ListView.ItemTemplate") {
                auto visual = this->BuildElement(child, context, bindings);
                ValidateChild(*element, *visual);
                element->AddChild(std::move(visual));
            }
        }
        return element;
    }
}