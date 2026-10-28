#pragma once

namespace universaldevkit::meta::concepts {
    template<typename T>
    concept Dereferenceable = requires(const T & value) {
        *value;
    };
}