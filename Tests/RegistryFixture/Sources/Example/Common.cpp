#include <winsock2.h>

#include <UniversalDevKit/Example/Example.h>
#include <UniversalDevKit/Service/Service.h>

#include <span>

int WindowsValue();

int CommonValue() {
    if (WindowsValue() != 2) {
        return -1;
    }
    WSADATA wsaData{};
    if (::WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        return -1;
    }
    ::WSACleanup();
    const int values[] = {IncrementCounter()};
    const std::span<const int> result(values);
    return result.front();
}