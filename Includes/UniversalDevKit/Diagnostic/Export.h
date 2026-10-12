// Сгенерировано GenerateComponentProjects.ps1. API-макрос компонента; изменяйте шаблон.
#pragma once
#include "../Export.h"

#if defined(UNIVERSALDEVKIT_DIAGNOSTIC_DYNAMIC)
#if defined(UNIVERSALDEVKIT_DIAGNOSTIC_EXPORTS)
#define UNIVERSALDEVKIT_DIAGNOSTIC_API UNIVERSALDEVKIT_API_EXPORT
#else
#define UNIVERSALDEVKIT_DIAGNOSTIC_API UNIVERSALDEVKIT_API_IMPORT
#endif
#else
#define UNIVERSALDEVKIT_DIAGNOSTIC_API
#endif