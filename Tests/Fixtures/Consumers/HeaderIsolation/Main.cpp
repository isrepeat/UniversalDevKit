#include <UniversalDevKit/HeleprsTest/Math.h>
#include <UniversalDevKit/Export.h>
#include <UniversalDevKit/Version.h>

// Подключение HeleprsTest не должно открывать заголовки независимого DiagnosticTest.
#if __has_include(<UniversalDevKit/DiagnosticTest/Logging.h>)
#error DiagnosticTest headers must not be accessible through HeleprsTest.Headers
#endif

static_assert(universaldevkit::heleprstest::math::Square(5) == 25);

int main() { return 0; }