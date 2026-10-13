// Сгенерировано GenerateComponentProjects.ps1. Общие атрибуты экспорта; изменяйте шаблон.
#pragma once

// Общие атрибуты; компонент выбирает экспорт, импорт или статическое подключение.
#if defined(_WIN32)
#define UNIVERSALDEVKIT_API_EXPORT __declspec(dllexport)
#define UNIVERSALDEVKIT_API_IMPORT __declspec(dllimport)
#define UNIVERSALDEVKIT_API_LOCAL
#elif defined(__GNUC__) || defined(__clang__)
#define UNIVERSALDEVKIT_API_EXPORT __attribute__((visibility("default")))
#define UNIVERSALDEVKIT_API_IMPORT __attribute__((visibility("default")))
#define UNIVERSALDEVKIT_API_LOCAL __attribute__((visibility("hidden")))
#else
#define UNIVERSALDEVKIT_API_EXPORT
#define UNIVERSALDEVKIT_API_IMPORT
#define UNIVERSALDEVKIT_API_LOCAL
#endif