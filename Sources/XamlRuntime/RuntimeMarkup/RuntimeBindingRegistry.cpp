#include "../../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/RuntimeMarkup/RuntimeBindingRegistry.h"

#include <utility>

namespace xaml::runtime {
    RuntimeBindingRegistry::RuntimeBindingRegistry(std::shared_ptr<const RuntimeBindingRegistry> fallback)
        : fallback(std::move(fallback)) {
    }

    //
    // API
    //
    void RuntimeBindingRegistry::AddText(std::string name, std::function<std::string()> getter, SubscriptionFactory subscribe) {
        Entry entry;
        entry.text = std::move(getter);
        entry.subscribe = std::move(subscribe);
        this->entries.insert_or_assign(std::move(name), std::move(entry));
    }

    void RuntimeBindingRegistry::AddBoolean(std::string name, std::function<bool()> getter,
        SubscriptionFactory subscribe, std::function<void(bool)> setter) {
        Entry entry;
        entry.kind = Entry::Kind::boolean;
        entry.boolean = std::move(getter);
        entry.setBoolean = std::move(setter);
        entry.subscribe = std::move(subscribe);
        this->entries.insert_or_assign(std::move(name), std::move(entry));
    }

    void RuntimeBindingRegistry::AddCommand(std::string name, Element::Command command) {
        Entry entry;
        entry.kind = Entry::Kind::command;
        entry.command = std::move(command);
        this->entries.insert_or_assign(std::move(name), std::move(entry));
    }

    void RuntimeBindingRegistry::AddCollection(std::string name, RuntimeCollectionDescriptor collection) {
        Entry entry;
        entry.kind = Entry::Kind::collection;
        entry.collection = std::move(collection);
        this->entries.insert_or_assign(std::move(name), std::move(entry));
    }

    const RuntimeBindingRegistry::Entry* RuntimeBindingRegistry::Find(std::string_view name) const {
        const auto found = this->entries.find(name);
        if (found != this->entries.end()) {
            return &found->second;
        }
        return this->fallback == nullptr ? nullptr : this->fallback->Find(name);
    }

    std::string RuntimeBindingRegistry::Available() const {
        std::string result;
        for (const auto& pair : this->entries) {
            if (!result.empty()) {
                result += ", ";
            }
            result += pair.first;
        }
        const std::string fallbackEntries = this->fallback == nullptr ? "" : this->fallback->Available();
        if (!fallbackEntries.empty()) {
            result += result.empty() ? "" : ", ";
            result += fallbackEntries;
        }
        return result;
    }
}