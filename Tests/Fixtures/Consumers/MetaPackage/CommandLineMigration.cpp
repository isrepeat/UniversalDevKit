#include "Migration/CommandLineParser.h"

namespace {
    using Parser = universaldevkit::migration::CommandLineParserA;

    struct Options {
        static std::vector<Parser::FlagDesc> Description() {
            return {{ "-name", Parser::ExpectedValuesCount::Single, true }};
        }

        static void MapParsedResults(const Parser& parser, Options& options) {
            options.name = parser.Get("-name").value();
        }

        void Validate() const {
            if (name.empty()) {
                throw std::runtime_error("Empty name");
            }
        }

        std::string name;
    };
}

int main() {
    char executable[] = "consumer";
    char flag[] = "-name";
    char value[] = "Meta";
    char* arguments[] = { executable, flag, value };
    const auto options = Parser::ParseTo<Options>(3, arguments);
    return options.name == "Meta" ? 0 : 1;
}