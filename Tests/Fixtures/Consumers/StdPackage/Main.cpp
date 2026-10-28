#include <UniversalDevKit/Helpers/Std/Extensions/optional_ref.h>
#include <UniversalDevKit/Helpers/Std/Extensions/fstreamEx.h>
#include <UniversalDevKit/Helpers/Std/Extensions/memoryEx.h>
#include <UniversalDevKit/Helpers/Std/Extensions/rangesEx.h>
#include <UniversalDevKit/Helpers/Std/FormatSpecializations.h>

#include <stdexcept>
#include <vector>

void Require(bool condition) {
    if (!condition) {
        throw std::runtime_error("Legacy Std import smoke test failed");
    }
}

struct Node {
    std::vector<Node*> children;
};

int main() {
    // Keep the legacy names and exercise their basic supported operations.
    int value = 7;
    auto reference = std::ex::make_optional_ref(value);
    reference.value() = 9;
    Require(value == 9);
    reference.reset();
    Require(reference == std::nullopt);

    auto unique = std::ex::make_unique_ex<int>(11);
    Require(*unique.Try() == 11);
    auto shared = std::ex::make_shared_ex<int>(13);
    std::ex::weak_ptr<int> weak(shared);
    Require(*weak.Try() == 13);
    Require(SAFE_RESULT(*shared.Try() == 13));

    std::vector<int> first{1, 2};
    std::vector<int> second{3, 4};
    auto combined = first | std::ex::views::concat(second) | std::ex::views::to<std::vector<int>>();
    Require(combined == std::vector<int>({1, 2, 3, 4}));
    auto shortened = combined | std::ex::views::drop_last(2) | std::ex::views::to<std::vector<int>>();
    Require(shortened == first);

    Node leaf;
    Node root{{&leaf}};
    std::vector<Node*> roots{&root};
    auto nodes = roots | std::ex::views::flatten_tree([](Node* node) { return node->children; })
        | std::ex::views::to<std::vector<Node*>>();
    Require(nodes == std::vector<Node*>({&root, &leaf}));
    Require(std::format("{}", std::filesystem::path("sample.txt")) == "sample.txt");
    Require(std::ex::ifstream::KnownUTFByteOrderMarks.at(std::ex::UTFByteOrderMark::UTF8).size() == 3);
}