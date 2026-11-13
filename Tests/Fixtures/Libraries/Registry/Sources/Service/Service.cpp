#include <UniversalDevKit/Service/Service.h>

#include <atomic>

int IncrementCounter() {
    // The only dynamic implementation of the service owns its state.
    static std::atomic<int> counter{0};
    return ++counter;
}