# Каталоги артефактов

В корне `!artifacts` допускаются только `projects`, `packages`, `tests` и `cache`. Логи размещаются внутри соответствующей сборки или теста. Каталоги запусков с GUID и датой не создаются; одинаковые рабочие каталоги нельзя использовать параллельно.

```text
!tools/
!artifacts/
  projects/<platform>/<build-system>/<project>/
  packages/nuget/
    build-<runtime>/
    install-<runtime>/
    dependencies/<component>/<runtime>/
    staging/<component>/payload/
    <package-files>
  packages/maven/
    build-native/
    build-gradle/<package>/
    staging/<artifact>/
    <group-path>/<artifact>/<version>/
  tests/<test-name>/
  cache/vcpkg/downloads/
  cache/vcpkg/binaries/
```

## Обычные проекты

`platform` содержит ОС и архитектуру, например `Windows-x64`; `build-system` — `msbuild` или `cmake`. MSBuild разделяет внутри проекта toolset, версию компилятора, CRT, конфигурацию и `bin`/`obj`. CMake presets выделяют отдельное дерево для toolset и CRT; Debug/Release выбираются при сборке.

## Пакеты

NuGet собирает выбранные компоненты совместно в `build-Dynamic` и `build-Static`, где суффикс обозначает CRT. `cmake --install` формирует `install-*`, после чего упаковщик копирует файлы каждого компонента в его `staging/<component>/payload`. Перед новой упаковкой staging компонента и дерево установки очищаются; рабочая сборка сохраняется для инкрементальной компиляции. Готовые `.nupkg` находятся непосредственно в `packages/nuget` и заменяются при повторной упаковке той же версии.

Рабочая сборка ANGLE принадлежит подготовщику OpenGLESRenderer и располагается в `packages/nuget/dependencies/OpenGLESRenderer/Dynamic`. Там находятся подготовленный рецепт, исходники, промежуточные файлы и установленная зависимость. Нужные библиотеки используются при сборке и копируются в payload согласно правилам пакета. Исходники spdlog входят в Diagnostic напрямую и отдельной сборки зависимости не требуют.

Android использует `packages/maven/build-native` для нативной сборки, `build-gradle/<package>` для Kotlin/Java и `staging/<artifact>` для подготовки AAR. Готовые AAR/POM располагаются по стандартным Maven-координатам. Параметры OutputDirectory и BuildRoot позволяют тесту направить всю упаковку внутрь своего стенда.

## Тесты

Каждый тест использует постоянный каталог в `tests`, очищая свой стенд перед повторным запуском. Сценарии MSBuild разделяются по имени сценария и WorkingTree/Submodule. Вложенные копии репозитория, потребители, сборки, feeds и отчёты остаются внутри стенда. Отчёты общих запусков находятся в `tests/RunTests` и `tests/RunAllTests`.

## Кеш и инструменты

Используется vcpkg, установленный в Visual Studio; копия vcpkg в `!tools` не создаётся. `downloads` содержит скачанные исходные архивы, `binaries` — бинарные архивы зависимостей с учётом ABI, рецепта и патчей. vcpkg самостоятельно восстанавливает их в рабочее дерево зависимости и сохраняет результаты сборки в бинарный кеш. VCPKG_BINARY_SOURCES позволяет изменить или отключить бинарный кеш.

Загружаемые инструменты хранятся в `!tools`, а не в `!artifacts`. Пользовательские установки SDK, NDK и JDK не перемещаются.