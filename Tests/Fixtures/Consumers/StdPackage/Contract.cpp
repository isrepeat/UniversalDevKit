#include <UniversalDevKit/Helpers/StdExt/Extensions/optional_ref.h>
#include <UniversalDevKit/Helpers/StdExt/Extensions/fstreamEx.h>
#include <UniversalDevKit/Helpers/StdExt/Extensions/memoryEx.h>
#include <UniversalDevKit/Helpers/StdExt/Extensions/rangesEx.h>

#include <forward_list>
#include <type_traits>
#include <filesystem>
#include <stdexcept>
#include <sstream>
#include <limits>
#include <vector>
#include <array>
#include <map>
#include <set>

void Require(bool condition) {
    if (!condition) {
        throw std::runtime_error("StdExt contract failed");
    }
}

template <typename TException, typename TFunction>
void RequireThrows(TFunction function) {
    try {
        function();
    }
    catch (const TException&) {
        return;
    }
    throw std::runtime_error("Expected exception was not thrown");
}

struct Base {
    inline static int destroyed = 0;
    virtual ~Base() { ++destroyed; }
};
struct Derived final : Base {};
struct Other final : Base {};
struct UnsafeBase { virtual void Anchor() {} };
struct UnsafeDerived final : UnsafeBase {};
struct Deleter {
    int* count;
    void operator()(Derived* pointer) const {
        ++*count;
        delete pointer;
    }
};

template <typename TPointer, typename TTarget>
concept CanOwnCast = requires(TPointer pointer) { std::move(pointer).template As<TTarget>(); };

template <typename TPointer, typename TTarget>
concept CanThrowCast = requires(TPointer pointer) { std::move(pointer).template Cast<TTarget>(); };

template <typename TPointer, typename TTarget>
concept CanObserveType = requires(const TPointer& pointer) { pointer.template Is<TTarget>(); };

template <typename TPointer, typename TTarget>
concept CanObserveView = requires(const TPointer& pointer) { pointer.template AsView<TTarget>(); };

template <typename TRange>
concept CanCopyUnique = requires(TRange&& range) {
    std::forward<TRange>(range) | stdEx::views::to<std::vector<std::unique_ptr<int>>>();
};

template <typename TReference>
concept CanUseTemporaryFallback = requires(TReference reference) { reference.value_or(1); };

static_assert(!std::is_constructible_v<stdEx::optional_ref<const int>, int&&>);
static_assert(!std::is_assignable_v<stdEx::optional_ref<const int>&, int&&>);
static_assert(!std::is_constructible_v<stdEx::optional_ref<const double>, int&>);
static_assert(std::is_constructible_v<stdEx::optional_ref<const int>, int&>);
static_assert(std::is_constructible_v<stdEx::optional_ref<Base>, Derived&>);
static_assert(!CanOwnCast<stdEx::unique_ptr<UnsafeDerived>, UnsafeBase>);
static_assert(!CanOwnCast<stdEx::unique_ptr<Derived, Deleter>, Base>);
static_assert(!CanOwnCast<stdEx::unique_ptr<int[]>, int>);
static_assert(!CanThrowCast<stdEx::unique_ptr<UnsafeDerived>, UnsafeBase>);
static_assert(!CanThrowCast<stdEx::unique_ptr<Derived, Deleter>, Base>);
static_assert(!CanThrowCast<stdEx::unique_ptr<int[]>, int>);
static_assert(!CanOwnCast<stdEx::unique_ptr<const Base>, Derived>);
static_assert(!CanOwnCast<stdEx::shared_ptr<int>, Derived>);
static_assert(!CanThrowCast<stdEx::shared_ptr<int>, Derived>);
static_assert(!CanOwnCast<stdEx::shared_ptr<Base[]>, Derived>);
static_assert(!CanThrowCast<stdEx::shared_ptr<const Base>, Derived>);
static_assert(!CanObserveType<stdEx::shared_ptr<int>, Derived>);
static_assert(!CanObserveType<stdEx::unique_ptr<int[]>, int>);
static_assert(!CanObserveView<stdEx::unique_ptr<const Base>, Derived>);
static_assert(CanOwnCast<stdEx::unique_ptr<Base>, const Derived>);
static_assert(CanOwnCast<stdEx::shared_ptr<const Base>, const Derived>);
static_assert(!CanCopyUnique<std::vector<std::unique_ptr<int>>&>);
static_assert(!CanUseTemporaryFallback<stdEx::optional_ref<const int>>);

void CheckReferencesAndPointers() {
    int value = 3;
    stdEx::optional_ref<const int> reference(value);
    Require(&*reference == &value);
    stdEx::optional_ref<int> mutableReference(value);
    reference = mutableReference;
    Require(&reference.value() == &value);
    reference.reset();
    RequireThrows<std::bad_optional_access>([&] { reference.value(); });
    Require(&reference.value_or(value) == &value);

    stdEx::unique_ptr<int> empty;
    Require(!empty);
    stdEx::weak_ptr<int> expired;
    Require(!expired.lock());

    Base::destroyed = 0;
    {
        stdEx::unique_ptr<Base> pointer(new Derived);
        Require(!std::move(pointer).As<Other>());
        Require(pointer != nullptr);
        RequireThrows<std::bad_cast>([&] { std::move(pointer).Cast<Other>(); });
        Require(pointer != nullptr);
        auto derived = std::move(pointer).Cast<Derived>();
        Require(!pointer && derived != nullptr);
        auto base = std::move(derived).As<Base>();
        Require(!derived && base != nullptr);
    }
    Require(Base::destroyed == 1);
    int deleted = 0;
    {
        stdEx::unique_ptr<Derived, Deleter> pointer(new Derived, Deleter{&deleted});
        Require(pointer != nullptr);
    }
    Require(deleted == 1 && Base::destroyed == 2);
    auto array = stdEx::make_unique_ex<int[]>(2);
    array[0] = 7;
    Require(array && array[0] == 7);

    // A successful shared cast retains the control block and the original deleter.
    int sharedDeleted = 0;
    {
        stdEx::shared_ptr<Base> pointer(new Derived, [&](Base* object) {
            ++sharedDeleted;
            delete object;
        });
        Require(pointer.Is<Derived>() && !pointer.Is<Other>());
        Require(!pointer.As<Other>());
        RequireThrows<std::bad_cast>([&] { pointer.Cast<Other>(); });
        Require(pointer.use_count() == 1);
        auto derived = pointer.Cast<Derived>();
        Require(!pointer.owner_before(derived) && !derived.owner_before(pointer));
        Require(pointer.use_count() == 2);
        pointer.reset();
        Require(derived && sharedDeleted == 0);
    }
    Require(sharedDeleted == 1);
    stdEx::shared_ptr<Base> emptyShared;
    Require(!emptyShared.As<Derived>());
    RequireThrows<std::bad_cast>([&] { emptyShared.Cast<Derived>(); });
    stdEx::unique_ptr<Base> emptyUnique;
    Require(!std::move(emptyUnique).As<Derived>());
    RequireThrows<std::bad_cast>([&] { std::move(emptyUnique).Cast<Derived>(); });
    auto observed = stdEx::make_unique_ex<Derived>();
    Require(observed.Is<Base>() && observed.AsView<Base>() == observed.get());
}

void CheckFiles() {
    const std::filesystem::path path("std-contract.tmp");
    struct Cleanup {
        const std::filesystem::path& path;
        ~Cleanup() { std::filesystem::remove(path); }
    } cleanup{path};
    auto write = [&](const std::vector<char>& bytes) {
        std::ofstream output(path, std::ios::binary | std::ios::trunc);
        output.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
        Require(output.good());
    };

    // Short reads preserve position and state even with failbit/eofbit exceptions enabled.
    for (const auto& bytes : std::vector<std::vector<char>>{{}, {'a'}, {'a', 'b'}, {'a', 'b', 'c'}, {'a', '\n'}}) {
        write(bytes);
        stdEx::ifstream input(path, std::ios::binary);
        input.exceptions(std::ios::badbit | std::ios::failbit | std::ios::eofbit);
        Require(!input.DetectUTFByteOrderMark());
        Require(input.tellg() == 0 && input.good());
        Require(input.ReadData().byteArray == bytes);
    }

    for (const auto& [bomType, signature] : stdEx::ifstream::KnownUTFByteOrderMarks) {
        for (bool payload : {false, true}) {
            std::vector<char> bytes(signature.begin(), signature.end());
            if (payload) {
                bytes.push_back('x');
            }
            write(bytes);
            stdEx::ifstream input(path, std::ios::binary);
            Require(input.DetectUTFByteOrderMark() == bomType);
            Require(input.tellg() == 0 && input.good());
            auto data = input.ReadData();
            Require(data.byteArray == (payload ? std::vector<char>{'x'} : std::vector<char>{}));
        }
    }

    for (const std::string text : {"CodePage=65001", "CodePage=65001\npayload", "unchanged", "unchanged\nrest"}) {
        std::vector<char> bytes{char(0xEF), char(0xBB), char(0xBF)};
        bytes.insert(bytes.end(), text.begin(), text.end());
        write(bytes);
        stdEx::ifstream input(path, std::ios::binary);
        auto data = input.ReadData();
        const bool header = text.starts_with("CodePage");
        Require(data.codePage.has_value() == header);
        if (header) {
            Require(*data.codePage == 65001);
        }
        const auto expected = header ? (text.find('\n') == std::string::npos ? std::string{} : text.substr(text.find('\n') + 1)) : text;
        Require(std::string(data.byteArray.begin(), data.byteArray.end()) == expected);
    }
}

void CheckRanges() {
    std::vector<int> source{1, 2, 3};
    auto trimmed = source | stdEx::views::drop_last(1);
    static_assert(std::ranges::forward_range<decltype(trimmed)>);
    Require(trimmed.size() == 2);
    source.push_back(4);
    Require(trimmed.size() == 3);
    Require((trimmed | stdEx::views::to<std::vector<int>>()) == std::vector<int>({1, 2, 3}));
    auto owned = std::vector<int>{1, 2, 3} | stdEx::views::drop_last(1);
    Require((owned | stdEx::views::to<std::vector<int>>()) == std::vector<int>({1, 2}));
    auto none = source | stdEx::views::drop_last(std::numeric_limits<std::size_t>::max());
    Require(none.begin() == none.end());
    auto all = source | stdEx::views::drop_last(0);
    Require((all | stdEx::views::to<std::vector<int>>()) == source);
    std::forward_list<int> unsized{1, 2, 3};
    Require((unsized | stdEx::views::drop_last(2) | stdEx::views::to<std::vector<int>>()) == std::vector<int>{1});
    auto infinite = std::views::iota(0) | stdEx::views::drop_last(2) | std::views::take(3);
    Require((infinite | stdEx::views::to<std::vector<int>>()) == std::vector<int>({0, 1, 2}));

    // istream_view has a move-only input iterator in C++20.
    std::istringstream input("5 6");
    auto concatenated = stdEx::views::concat(std::ranges::istream_view<int>(input), std::vector<int>{7});
    static_assert(std::ranges::input_range<decltype(concatenated)>);
    Require((concatenated | stdEx::views::to<std::vector<int>>()) == std::vector<int>({5, 6, 7}));
    auto closure = stdEx::views::concat(std::vector<int>{9});
    auto moved = std::vector<int>{8} | std::move(closure);
    Require((moved | stdEx::views::to<std::vector<int>>()) == std::vector<int>({8, 9}));
    auto empty = stdEx::views::concat(std::vector<int>{}, std::vector<int>{});
    Require(empty.begin() == empty.end());
    auto fromEmpty = stdEx::views::concat(std::vector<int>{}, std::vector<int>{7});
    Require((fromEmpty | stdEx::views::to<std::vector<int>>()) == std::vector<int>{7});
    auto reusable = stdEx::views::concat(source);
    auto reusedConcat = source | reusable;
    Require((reusedConcat | stdEx::views::to<std::vector<int>>()).size() == source.size() * 2);

    std::vector<std::unique_ptr<int>> pointers;
    pointers.push_back(std::make_unique<int>(42));
    auto transferred = pointers | stdEx::views::to<std::vector<std::unique_ptr<int>>>(stdEx::views::move_elements);
    Require(!pointers[0] && *transferred[0] == 42);
    Require((source | stdEx::views::to<std::set<int>>()).size() == 4);
    std::array<std::pair<int, int>, 1> pairs{{{1, 2}}};
    Require((pairs | stdEx::views::to<std::map<int, int>>()).at(1) == 2);

    // Numeric zero is a real node; callbacks may be mutable, move-only or return a reference.
    auto callback = [state = std::make_unique<int>(0)](int node) mutable {
        ++*state;
        return node == 0 ? std::vector<int>{1, 2} : std::vector<int>{};
    };
    auto tree = stdEx::views::flatten_tree(std::vector<int>{0}, std::move(callback));
    static_assert(std::ranges::input_range<decltype(tree)>);
    Require((tree | stdEx::views::to<std::vector<int>>()) == std::vector<int>({0, 1, 2}));
    auto reused = stdEx::views::flatten_tree([](int) { return std::vector<int>{}; });
    Require((source | reused | stdEx::views::to<std::vector<int>>()) == source);
    struct Node { std::vector<Node*> children; };
    Node leaf;
    Node root{{nullptr, &leaf}};
    auto pointerTree = std::vector<Node*>{nullptr, &root} | stdEx::views::flatten_tree([](Node* node) -> const auto& { return node->children; });
    Require((pointerTree | stdEx::views::to<std::vector<Node*>>()) == std::vector<Node*>({&root, &leaf}));
    auto emptyTree = std::vector<Node*>{nullptr} | stdEx::views::flatten_tree([](Node* node) -> const auto& { return node->children; });
    Require(emptyTree.begin() == emptyTree.end());
    struct ValueNode {
        int value;
        explicit ValueNode(int value)
            : value{value} {
        }
    };
    auto values = stdEx::views::flatten_tree(std::vector<ValueNode>{ValueNode{0}}, [](const ValueNode&) { return std::vector<ValueNode>{}; });
    Require(values.begin()->value == 0);
    auto booleans = stdEx::views::flatten_tree(std::array{false}, [](bool) { return std::array<bool, 0>{}; });
    Require((booleans | stdEx::views::to<std::vector<bool>>()) == std::vector<bool>{false});
}

int main() {
    CheckReferencesAndPointers();
    CheckFiles();
    CheckRanges();
}