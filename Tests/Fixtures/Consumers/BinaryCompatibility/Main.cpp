#include <UniversalDevKit/Diagnostic/Logging.h>

int main() {
    return universaldevkit::diagnostic::TryLog("Binary compatibility consumer") ? 0 : 1;
}