#pragma once
#if defined(_WIN32) && defined(UNIVERSALDEVKIT_EXAMPLE_DYNAMIC)
#if defined(UNIVERSALDEVKIT_EXAMPLE_EXPORTS)
#define EXAMPLE_API __declspec(dllexport)
#else
#define EXAMPLE_API __declspec(dllimport)
#endif
#else
#define EXAMPLE_API
#endif

EXAMPLE_API int CommonValue();