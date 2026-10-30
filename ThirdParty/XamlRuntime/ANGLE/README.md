# Рецепт ANGLE

Рецепт перенесён из `UtilityHelpersLib/NugetProjects/XamlRuntime/Nuget/XamlRuntime.Package/ThirdParty/ANGLE`. Он описывает внешнюю зависимость OpenGLESRenderer для Windows. Каталог пока сохраняет расположение первоначального импорта XamlRuntime; сборка пакета UDK ещё не подключена к этому рецепту.

## Закреплённые источники

- `vcpkg.json`: baseline `30ef65cad98f08e7197c9a1656fbd871bcb72f2d`, зависимость `angle`.
- `CustomRecipes/angle/vcpkg.json`: overlay-порт `chromium_7258`, port-version `2`.
- `CustomRecipes/angle/portfile.cmake`: ANGLE commit `d9fc4a372074b1079c193c422fc4a180e79b6636`; архив проверяется закреплённым SHA512.
- Там же закреплены WebKit buildsystem (`0742522b24152262b04913242cb0b3c48de92ba0`) и Chromium zlib (`4028ebf8710ee39d2286cb0f847f9b95c59f84d8`); загружаемые файлы WebKit проверяются SHA512.

Manifest должен использоваться вместе с overlay `CustomRecipes`: один baseline без overlay не выбирает наш исправленный рецепт ANGLE. Сохранены вспомогательные CMake-файлы, шаблоны заголовков и конфигурация `unofficial-angle`.

## Патчи

Порт применяет только два патча из списка `PATCHES`:

- `001-fix-builder-error.patch`: подключение `windows.h` перед внутренними заголовками в `SystemInfo_win.cpp`.
- `004-fix-uniform-sort-comparator.patch`: исправление порядка сравнения precision, структур и массивов uniform-переменных в компиляторе шейдеров.

Остальные три patch-файла сохранены из исходного overlay, но не включены в `PATCHES` и не применяются автоматически.

Пробел в начале пустой контекстной строки unified diff является частью формата patch. Его нельзя удалять при форматировании. Репозиторий хранит файлы без завершающего CR/LF; перед применением патчей подготовщик должен создать рабочую копию overlay и добавить в ней завершающий LF к `.patch`, как делал старый упаковщик. Исходный рецепт при этом не изменяется.

Получение инструментов, короткий рабочий путь для Windows, кеширование, вызов vcpkg и передача результата в сборку UDK будут подключены отдельным шагом.