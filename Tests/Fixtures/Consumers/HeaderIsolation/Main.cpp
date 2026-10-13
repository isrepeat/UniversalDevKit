#include <UniversalDevKit/Helpers/Math.h>
#include <UniversalDevKit/Export.h>
#include <UniversalDevKit/Version.h>

// Подключение Helpers не должно открывать заголовки независимого Diagnostic.
#if __has_include(<UniversalDevKit/Diagnostic/Logging.h>)
#error Diagnostic headers must not be accessible through Helpers.Headers
#endif

static_assert(universaldevkit::math::Square(5) == 25);

int main() { return 0; }