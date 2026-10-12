#include <UniversalDevKit/Service/Service.h>

#include <atomic>

int IncrementCounter() {
    // Состояние принадлежит единственной динамической реализации сервиса.
    static std::atomic<int> counter{0};
    return ++counter;
}