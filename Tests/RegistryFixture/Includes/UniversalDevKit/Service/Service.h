#pragma once
#if defined(_WIN32)
#if defined(UNIVERSALDEVKIT_SERVICE_EXPORTS)
#define SERVICE_API __declspec(dllexport)
#else
#define SERVICE_API __declspec(dllimport)
#endif
#else
#define SERVICE_API __attribute__((visibility("default")))
#endif

SERVICE_API int IncrementCounter();