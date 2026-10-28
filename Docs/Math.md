# Math: первоначальный перенос

Header-only компонент C++20 перенесён из UtilityHelpersLib/Helpers/Helpers.Shared/Helpers/Math без исправления алгоритмов и поведения. Публичные include начинаются с UniversalDevKit/Math/, основной namespace — universaldevkit::math. Math публично зависит от Meta, предоставляющего __requires_expr.

Сохранены исходные файлы Differentation.h, Function1D.h, Rect.h, Size.h и Tensor.h, включая старое написание Differentation, числовые типы алиасов и встроенные compile-time тесты. Сохранены вспомогательные details и исходные комментарии-разделители. Исправления и упорядочение внутренней архитектуры относятся к следующему отдельному изменению.

Адаптация переноса ограничена удалением Helpers/common.h, заменой Meta include, HELPERS_NS/H::Math на namespace UDK и снятием платформенного _HAS_CXX20 wrapper: минимальный стандарт UDK уже C++20, а _HAS_CXX20 является внутренним макросом MSVC STL. Алиасы Rect/Size размещены в namespace компонента math. Исходная UtilityHelpersLib не меняется.

CMake предоставляет UniversalDevKit::Math.Headers; NuGet — UniversalDevKit.Math с linkage Shared; Android — universaldevkit-math-shared-release и udk_math_shared::Math. Реестр и проекты Shared/HeaderCheck создаются штатным генератором. Helpers/Math.h не изменён.

Tests/Fixtures/Consumers/MathPackage — независимый smoke consumer установленного CMake-пакета. Проверки исходного поведения не являются подтверждением исправления известных недостатков.

Первичная проверка: MSVC HeaderCheck и установленный CMake consumer прошли. Android Clang отклоняет Rect.h и Size.h из-за повторного имени T у шаблона класса и шаблона оператора преобразования. Эта исходная ошибка намеренно сохранена для следующего коммита; наличие Android delivery ещё не подтверждает пригодность всех заголовков Math для Android.

Следующим отдельным изменением нужно рассмотреть: возврат ссылок при многомерной индексации Tensor, Vec/Mat-алиасы с суффиксом f и типом double, написание Differentiation, контракт rank-0 и границ Tensor, а также требования к скалярным типам DifferentialVar. Исходный DifferentialVar хранит и накапливает градиент; автоматический вывод производных не реализован.