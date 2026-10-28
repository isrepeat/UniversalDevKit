# Helpers

Helpers — header-only компонент C++20 с разделами Meta, Math, Patterns и Std. Исходники находятся в Includes/Helpers/UniversalDevKit/Helpers/. Meta, Math и Patterns используют namespace universaldevkit::helpers::meta, universaldevkit::helpers::math и universaldevkit::helpers::patterns. Std пока сохраняет старый API std::ex; ограничения первоначального переноса описаны в [Std.md](Std.md). Публичные пути начинаются с UniversalDevKit/Helpers/.

CMake предоставляет только UniversalDevKit::Helpers.Headers. В MSBuild доступны Helpers.Shared и проверочное приложение Helpers.HeaderCheck; Static/Dynamic вариантов нет. NuGet UniversalDevKit.Helpers использует linkage Shared. Android AAR: org.universaldevkit:universaldevkit-helpers-shared-release:<version>, Prefab target udk_helpers_shared::Helpers. Собственной .lib/.dll/.a/.so у Helpers нет.

Старый compiled-компонент переименован именно в HeleprsTest. Его API находится в UniversalDevKit/HeleprsTest/, namespace — universaldevkit::heleprstest::math и universaldevkit::heleprstest::text. Сохранены GUID прежних проектов, Static/Dynamic/Shared и пакеты UniversalDevKit.HeleprsTest. DiagnosticTest пока использует его как private/static тестовую зависимость; новый Helpers от HeleprsTest и DiagnosticTest не зависит.

Независимые компоненты Meta и Math, их проекты и пакетные адаптеры удалены. Совместимых обёрток для старых include/namespace не добавлено. Подробности API разделов — Meta.md и Math.md. Имена каталогов consumer-тестов MetaPackage и MathPackage сохраняются как названия тестовых наборов, оба используют Helpers.Headers.

Header-only не гарантирует единственный экземпляр скрытого static-состояния во всём процессе. Для общих сервисов используется явное владение либо отдельный динамический компонент со stateScope=process; см. StateScope.md.

Patterns/Singleton.h переносит Singleton, SingletonUnique, SingletonShared и SingletonUnscoped из UtilityHelpersLib. GetInstance создаёт объект без аргументов; если конструктора по умолчанию нет, сначала нужен CreateInstance(args...). Повторный CreateInstance возвращает уже созданный объект. Копирование Singleton запрещено. Варианты с указателями защищают создание и получение mutex; это не синхронизирует методы самого объекта. SingletonUnscoped требует явного DeleteInstance и внешнего согласования удаления со всеми пользователями указателя. Как и в исходном API, циклическая инициализация и обращения после уничтожения singleton не поддерживаются.

Consumer-тест Tests/Fixtures/Consumers/PatternsPackage проверяет параллельное первое обращение, повторное создание, передачу аргументов и удаление/повторное создание Unscoped.