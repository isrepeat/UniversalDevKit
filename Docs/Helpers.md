# Helpers

Helpers — header-only компонент C++20 с двумя разделами: Meta и Math. Исходники находятся в Includes/Helpers/UniversalDevKit/Helpers/Meta и Math; namespace повторяют структуру: universaldevkit::helpers::meta и universaldevkit::helpers::math. Публичные пути начинаются с UniversalDevKit/Helpers/Meta/ и UniversalDevKit/Helpers/Math/.

CMake предоставляет только UniversalDevKit::Helpers.Headers. В MSBuild доступны Helpers.Shared и проверочное приложение Helpers.HeaderCheck; Static/Dynamic вариантов нет. NuGet UniversalDevKit.Helpers использует linkage Shared. Android AAR: org.universaldevkit:universaldevkit-helpers-shared-release:<version>, Prefab target udk_helpers_shared::Helpers. Собственной .lib/.dll/.a/.so у Helpers нет.

Старый compiled-компонент переименован именно в HeleprsTest. Его API находится в UniversalDevKit/HeleprsTest/, namespace — universaldevkit::heleprstest::math и universaldevkit::heleprstest::text. Сохранены GUID прежних проектов, Static/Dynamic/Shared и пакеты UniversalDevKit.HeleprsTest. DiagnosticTest пока использует его как private/static тестовую зависимость; новый Helpers от HeleprsTest и DiagnosticTest не зависит.

Независимые компоненты Meta и Math, их проекты и пакетные адаптеры удалены. Совместимых обёрток для старых include/namespace не добавлено. Подробности API разделов — Meta.md и Math.md. Имена каталогов consumer-тестов MetaPackage и MathPackage сохраняются как названия тестовых наборов, оба используют Helpers.Headers.

Header-only не гарантирует единственный экземпляр скрытого static-состояния во всём процессе. Для общих сервисов используется явное владение либо отдельный динамический компонент со stateScope=process; см. StateScope.md.