#include <UniversalDevKit/Helpers/StdExt/Extensions/optional_ref.h>
#include <UniversalDevKit/Helpers/StdExt/Extensions/fstreamEx.h>
#include <UniversalDevKit/Helpers/StdExt/Extensions/memoryEx.h>
#include <UniversalDevKit/Helpers/StdExt/Extensions/rangesEx.h>
#include <UniversalDevKit/Helpers/StdExt/FormatSpecializations.h>
#include <UniversalDevKit/Helpers/Stream/StreamLineReader.h>
#include <UniversalDevKit/Helpers/Stream/StreamLineViewer.h>
#include <UniversalDevKit/Helpers/Regex/Regex.h>

#include <stdexcept>
#include <sstream>
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
    Require(unique && *unique == 11);
    auto shared = stdEx::make_shared_ex<int>(13);
    stdEx::weak_ptr<int> weak(shared);
    auto locked = weak.lock();
    Require(locked && *locked == 13);
    Require(shared && *shared == 13);

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
    const auto path = universaldevkit::helpers::stdext::Path(std::filesystem::path(u8"sample-\u00e9.txt"));
    Require(std::format("{}", path) == "sample-\xc3\xa9.txt");
    Require(std::format(L"{}", path) == L"sample-\u00e9.txt");
    Require(stdEx::ifstream::KnownUTFByteOrderMarks.at(stdEx::UTFByteOrderMark::UTF8).size() == 3);

    // Reader peeking preserves logical position and history tracks consumed lines.
    std::istringstream input("first\r\nsecond\nthird");
    universaldevkit::helpers::stream::StreamLineReader reader(input, 2);
    Require(reader.PeekLine().value() == "first");
    Require(reader.PeekLine().value() == "first");
    int historyIndex = -1;
    Require(reader.ReadLine(historyIndex).value() == "first" && historyIndex == 0);
    Require(reader.ReadLine(historyIndex).value() == "second" && historyIndex == 1);
    Require(reader.GetHistoryLine(0).value() == "second");
    Require(reader.ReadLine(historyIndex).value() == "third" && historyIndex == 1);
    Require(reader.GetHistoryLine(1).value() == "second");
    Require(!reader.ReadLine());

    // Viewer owns the text buffer and exposes views into its lines.
    std::istringstream text("first\r\n\nthird");
    universaldevkit::helpers::stream::StreamLineViewer viewer(text);
    Require(viewer.GetAllLines().size() == 3);
    Require(viewer.GetLine(0) == "first");
    Require(viewer.GetLine(1).empty());
    Require(viewer.GetLinesSpan(1, 3).size() == 2);

    // Check owning and observing regex results through the public helper API.
    auto matches = universaldevkit::helpers::regex::GetRegexMatches<char, std::string>("x=7 y=13", std::regex("(\\w+)=(\\d+)"));
    Require(matches.size() == 2);
    Require(matches[1].capturedGroups[2] == "13");
    auto match = universaldevkit::helpers::regex::GetRegexMatch<char>("code=42", std::regex("code=(\\d+)"));
    Require(match.has_value() && match->capturedGroups[1] == "42");
    Require(!universaldevkit::helpers::regex::GetRegexMatch<char>("no match", std::regex("\\d+")));
    auto owningMatch = universaldevkit::helpers::regex::GetRegexMatch<char, std::string>(std::string("code=42"), std::regex("code=(\\d+)"));
    Require(owningMatch.has_value() && owningMatch->capturedGroups[1] == "42");

    // fstreamEx now uses the shared Stream and Regex implementations.
    const std::filesystem::path filePath("std-package-encoding.tmp");
    {
        std::ofstream output(filePath, std::ios::binary);
        output << "CodePage=65001\npayload";
    }
    {
        stdEx::ifstream file(filePath, std::ios::binary);
        auto data = file.ReadData();
        Require(data.codePage.value() == 65001);
        Require(std::string(data.byteArray.begin(), data.byteArray.end()) == "payload");
    }
    std::filesystem::remove(filePath);
}