#pragma once
#include <cstdint>
#include <string>

namespace {{application}}::application::core {
    // Values are part of the JNI contract and independent of declaration order.
    enum class HostCommand : std::int32_t {
        requestApplicationUpdate = 1,
        sendLogs = 2,
    };

    struct HostCommandData final {
        std::string value;
        std::string additionalValue;
    };
}

namespace {{application}}::application::interface {
    class IHostCommandDispatcher {
    public:
        virtual ~IHostCommandDispatcher() = default;
        virtual void Dispatch(core::HostCommand hostCommand, const core::HostCommandData& hostCommandData = {}) = 0;
    };
}