#include <UniversalDevKit/DiagnosticTest/Logging.h>

int main() {
    return universaldevkit::diagnostictest::TryLog("Binary compatibility consumer") ? 0 : 1;
}