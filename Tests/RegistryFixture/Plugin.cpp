int CommonValue();

#if defined(_WIN32)
#define PLUGIN_API __declspec(dllexport)
#else
#define PLUGIN_API __attribute__((visibility("default")))
#endif

#if defined(PLUGIN_A)
extern "C" PLUGIN_API int RunPluginA() { return CommonValue(); }
#else
extern "C" PLUGIN_API int RunPluginB() { return CommonValue(); }
#endif