#include <UniversalDevKit/Helpers/StdExt/Extensions/optional_ref.h>
#include <UniversalDevKit/Helpers/StdExt/Extensions/fstreamEx.h>
#include <UniversalDevKit/Helpers/StdExt/Extensions/memoryEx.h>
#include <UniversalDevKit/Helpers/StdExt/Extensions/rangesEx.h>
#include <UniversalDevKit/Helpers/StdExt/FormatSpecializations.h>

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
    auto reference = stdEx::make_optional_ref(value);
    reference.value() = 9;
    Require(value == 9);
    reference.reset();
    Require(reference == std::nullopt);

    auto unique = stdEx::make_unique_ex<int>(11);
    Require(*unique.Try() == 11);
    auto shared = stdEx::make_shared_ex<int>(13);
    stdEx::weak_ptr<int> weak(shared);
    Require(*weak.Try() == 13);
    Require(SAFE_RESULT(*shared.Try() == 13));

    std::vector<int> first{1, 2};
    std::vector<int> second{3, 4};
    auto combined = first | stdEx::views::concat(second) | stdEx::views::to<std::vector<int>>();
    Require(combined == std::vector<int>({1, 2, 3, 4}));
    auto shortened = combined | stdEx::views::drop_last(2) | stdEx::views::to<std::vector<int>>();
    Require(shortened == first);

    Node leaf;
    Node root{{&leaf}};
    std::vector<Node*> roots{&root};
    auto nodes = roots | stdEx::views::flatten_tree([](Node* node) { return node->children; })
        | stdEx::views::to<std::vector<Node*>>();
    Require(nodes == std::vector<Node*>({&root, &leaf}));
    Require(std::format("{}", std::filesystem::path("sample.txt")) == "sample.txt");
    Require(stdEx::ifstream::KnownUTFByteOrderMarks.at(stdEx::UTFByteOrderMark::UTF8).size() == 3);
}