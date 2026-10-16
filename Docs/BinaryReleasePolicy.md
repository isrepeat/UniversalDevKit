# Поддерживаемый бинарный выпуск

BinaryReleasePolicy.json задаёт первый поддерживаемый выпуск: Windows x64, MSVC 19.51.36260.0, v145, Debug/Release, MD/MT и Static/Dynamic компонентов. Для Debug используются MDd/MTd и стандартный _ITERATOR_DEBUG_LEVEL=2; Release использует уровень 0. Версия компилятора является версией cl.exe, а не VCToolsVersion. Обновление списка поддерживаемых компиляторов требует проверки матрицы.

NuGet-упаковщик обязательно включает UniversalDevKit_ENFORCE_RELEASE_POLICY. Для собственного выпуска через CMake задайте -DUniversalDevKit_ENFORCE_RELEASE_POLICY=ON и -DCMAKE_CONFIGURATION_TYPES=Debug;Release. Для single-config генератора задайте Debug либо Release через CMAKE_BUILD_TYPE. Неподдерживаемая ОС, архитектура, версия компилятора, toolset, CRT или конфигурация отклоняются до сборки пакета.

Без этого флага сборки остаются экспериментальными: новые архитектуры и Linux/Android можно проверять, но метаданные помечаются releasePolicy=Experimental. Header-only пакеты освобождены от ограничений бинарной матрицы; Shared компилируется в контексте consumer.

Выпуск сохраняет фактические параметры сборки отдельно от политики и устанавливает копию BinaryReleasePolicy.json. Существующая ExactCompilerV1-проверка пакета сравнивает consumer с фактическими compiler/toolset/архитектурой; проверки CRT и STL ABI выполняются для каждого MSVC target. Политика выпуска не является обещанием совместимости разных компиляторов.

Проверка TestBinaryReleasePolicy.ps1 использует синтетические значения и проверяет отказы для всех полей матрицы и изменений compiler path/version, архитектуры и CRT в общем build identity guard. Она не заменяет реальную матрицу: TestBinaryCompatibility.ps1 выполняет сборку, установку и запуск Static/Dynamic MD/MT Debug/Release; NuGet.Tests.ps1 дополнительно проверяет restore и пакетного consumer.