#pragma once
#include <string>

namespace {{application}}::application::model {
    struct ApplicationStateDocument final {
        std::string greeting = "Hello from Main!";
        bool operator==(const ApplicationStateDocument&) const = default;
    };
}