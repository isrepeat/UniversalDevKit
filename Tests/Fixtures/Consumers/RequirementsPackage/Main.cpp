#include <span>

int CommonValue();

int main() {
    const int values[] = {CommonValue()};
    const std::span<const int> result(values);
    return result.front() == 1 ? 0 : 1;
}