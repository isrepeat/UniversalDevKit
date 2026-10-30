#pragma once
#include <format>

namespace diagnostic_tests {
    struct ContractValue {
        int value;
    };
}

template<typename TChar>
struct std::formatter<diagnostic_tests::ContractValue, TChar> : std::formatter<int, TChar> {
    template<typename TFormatContext>
    auto format(const diagnostic_tests::ContractValue& contractValue, TFormatContext& formatContext) const {
        return std::formatter<int, TChar>::format(contractValue.value, formatContext);
    }
};