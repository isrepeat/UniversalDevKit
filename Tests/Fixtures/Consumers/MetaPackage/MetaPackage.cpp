#include <UniversalDevKit/Helpers/Meta/Utilities/TypeErasedDeleter.h>
#include <UniversalDevKit/Helpers/Meta/Utilities/ValueExtractor.h>
#include <UniversalDevKit/Helpers/Meta/Utilities/PointerGetter.h>
#include <UniversalDevKit/Helpers/Meta/Diagnostics.h>
#include <UniversalDevKit/Helpers/Meta/TypeTraits.h>
#include <UniversalDevKit/Helpers/Meta/Tags.h>

#include <type_traits>
#include <memory>
#include <vector>

namespace {
    static_assert(__cplusplus >= 202002L
#if defined(_MSVC_LANG)
        || _MSVC_LANG >= 202002L
#endif
    );
    struct DestructionProbe {
        explicit DestructionProbe(bool& wasDestroyed) noexcept
            : wasDestroyed(wasDestroyed) {
        }

        ~DestructionProbe() {
            wasDestroyed = true;
        }

        bool& wasDestroyed;
    };

    static_assert(std::is_same_v<universaldevkit::helpers::meta::ExtractUnderlyingType_t<std::vector<int>>, int>);
    static_assert(std::is_same_v<universaldevkit::helpers::meta::ExtractUnderlyingType_t<int>, int>);
    static_assert(!universaldevkit::helpers::meta::dependent_false_v<int>);
    static_assert(std::is_empty_v<universaldevkit::helpers::meta::nothing>);
}

int main() {
    int value = 42;
    int* pointer = &value;
    const int& extracted = universaldevkit::helpers::meta::utilities::ValueExtractor::From(pointer);
    if (&extracted != &value || universaldevkit::helpers::meta::utilities::PointerGetter::Get(value) != pointer) {
        return 1;
    }

    // Проверяем конечный объект, цепочку указателей и умный указатель.
    static_assert(std::is_same_v<decltype(universaldevkit::helpers::meta::utilities::ValueExtractor::From(value)), const int&>);
    static_assert(std::is_same_v<decltype(universaldevkit::helpers::meta::utilities::ValueExtractor::From(pointer)), const int&>);
    int** nestedPointer = &pointer;
    auto ownedValue = std::make_unique<int>(42);
    if (&universaldevkit::helpers::meta::utilities::ValueExtractor::From(nestedPointer) != &value ||
        &universaldevkit::helpers::meta::utilities::ValueExtractor::From(ownedValue) != ownedValue.get()) {
        return 1;
    }

    bool wasDestroyed = false;
    std::unique_ptr<void, universaldevkit::helpers::meta::utilities::TypeErasedDeleter> probe(
        new DestructionProbe(wasDestroyed),
        universaldevkit::helpers::meta::utilities::TypeErasedDeleter::Make<DestructionProbe>());
    probe.reset();
    return wasDestroyed ? 0 : 1;
}