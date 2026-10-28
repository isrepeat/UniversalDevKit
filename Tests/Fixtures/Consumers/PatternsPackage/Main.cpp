#include <UniversalDevKit/Helpers/Patterns/Singleton.h>

#include <type_traits>
#include <stdexcept>
#include <atomic>
#include <thread>
#include <vector>

namespace patterns = universaldevkit::helpers::patterns;

struct Basic : patterns::Singleton<Basic> {};
struct DefaultValue {
    inline static std::atomic<int> constructions{0};
    DefaultValue() { ++constructions; }
};
struct ExplicitValue {
    int value;
    explicit ExplicitValue(int value) : value(value) {}
};

static_assert(!std::is_copy_constructible_v<Basic>);

void Require(bool condition) {
    if (!condition) {
        throw std::runtime_error("Singleton contract failed");
    }
}

int main() {
    // Check address stability and explicit initialization before the first access.
    Basic::InitSingleton();
    Require(&Basic::GetInstance() == &Basic::GetInstance());

    // Concurrent first access creates exactly one object for each variant.
    {
        std::vector<std::jthread> threads;
        for (int i = 0; i < 8; ++i) {
            threads.emplace_back([] {
                patterns::SingletonUnique<DefaultValue>::GetInstance();
                patterns::SingletonShared<DefaultValue>::GetInstance();
                patterns::SingletonUnscoped<DefaultValue>::GetInstance();
            });
        }
    }
    Require(DefaultValue::constructions == 3);
    auto shared = patterns::SingletonShared<DefaultValue>::GetInstance();
    Require(shared == patterns::SingletonShared<DefaultValue>::GetInstance());
    patterns::SingletonUnscoped<DefaultValue>::DeleteInstance();
    patterns::SingletonUnscoped<DefaultValue>::GetInstance();
    Require(DefaultValue::constructions == 4);
    patterns::SingletonUnscoped<DefaultValue>::DeleteInstance();

    // Repeated creation preserves the existing object and its original arguments.
    auto& unique = patterns::SingletonUnique<ExplicitValue>::CreateInstance(7);
    Require(&unique == &patterns::SingletonUnique<ExplicitValue>::CreateInstance(9));
    Require(patterns::SingletonUnique<ExplicitValue>::GetInstance().value == 7);
    auto explicitShared = patterns::SingletonShared<ExplicitValue>::CreateInstance(11);
    Require(explicitShared == patterns::SingletonShared<ExplicitValue>::GetInstance());
    Require(patterns::SingletonShared<ExplicitValue>::CreateInstance(13)->value == 11);
    auto* unscoped = patterns::SingletonUnscoped<ExplicitValue>::CreateInstance(17);
    Require(unscoped == patterns::SingletonUnscoped<ExplicitValue>::GetInstance());
    Require(patterns::SingletonUnscoped<ExplicitValue>::CreateInstance(19)->value == 17);
    patterns::SingletonUnscoped<ExplicitValue>::DeleteInstance();
    Require(patterns::SingletonUnscoped<ExplicitValue>::CreateInstance(23)->value == 23);
    patterns::SingletonUnscoped<ExplicitValue>::DeleteInstance();
}