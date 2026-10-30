#pragma once
#include "../Binding.h"

#include <map>
#include <memory>

namespace xaml::runtime {
    class RuntimeBindingRegistry;
    using SubscriptionFactory = std::function<std::function<void()>(std::function<void()>)>;

    struct RuntimeCollectionDescriptor {
        std::function<size_t()> count;
        std::function<const void*(size_t)> at;
        std::function<std::shared_ptr<RuntimeBindingRegistry>(const void*)> itemBindings;
        std::function<void(Element&, Element::ItemTemplate)> bind;
    };

    class RuntimeBindingRegistry final {
    public:
        RuntimeBindingRegistry() = default;
        explicit RuntimeBindingRegistry(std::shared_ptr<const RuntimeBindingRegistry> fallback);

        struct Entry {
            enum class Kind { text, boolean, command, collection };
            Kind kind = Kind::text;
            std::function<std::string()> text;
            std::function<bool()> boolean;
            std::function<void(bool)> setBoolean;
            Element::Command command;
            RuntimeCollectionDescriptor collection;
            SubscriptionFactory subscribe;
        };

        void AddText(std::string name, std::function<std::string()> getter, SubscriptionFactory subscribe = {});
        void AddBoolean(std::string name, std::function<bool()> getter, SubscriptionFactory subscribe = {},
            std::function<void(bool)> setter = {});
        void AddCommand(std::string name, Element::Command command);
        void AddCollection(std::string name, RuntimeCollectionDescriptor collection);
        const Entry* Find(std::string_view name) const;
        std::string Available() const;

    private:
        std::map<std::string, Entry, std::less<>> entries;
        std::shared_ptr<const RuntimeBindingRegistry> fallback;
    };
}