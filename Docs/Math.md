# Math

Раздел Math единого header-only компонента Helpers C++20 из UtilityHelpersLib/Helpers/Helpers.Shared/Helpers/Math. Публичные include начинаются с UniversalDevKit/Helpers/Math/, основной namespace — universaldevkit::helpers::math. Math использует соседний раздел Meta, предоставляющего __requires_expr.

Первоначальный перенос без исправления алгоритмов сохранён отдельным коммитом 9fd59e2. Текущие исправления:

- Differentation.h переименован в Differentiation.h без совместимой обёртки.
- Многомерная индексация Tensor возвращает T& для изменяемого объекта и const T& для const-объекта. Присваивание и составные операции через tensor[i][j] изменяют хранилище.
- Vec2f/Vec3f/Vec4f и Mat1x1f/Mat2x2f/Mat3x3f/Mat4x4f используют float. Для double добавлены соответствующие алиасы с суффиксом d. Это изменение типа и размера объектов: существующий код, которому нужен double, должен перейти на d-алиасы или Tensor<double, ...>.
- В Rect/Size параметр шаблона оператора преобразования переименован в TTarget, устраняя ошибку Clang. Преобразование доступно и для const-объектов.

Function1D — нешаблонный header-only класс с std::function, std::any и таблицами явно заданных производных/первообразных. Пользователь сам передаёт эти функции; класс не выводит их автоматически. Нешаблонный класс может оставаться header-only, поскольку его методы определены внутри класса и являются inline.

DifferentialVar хранит value и grad. AccumulateGrad прибавляет явно переданный градиент, ResetGrad обнуляет только градиент, Reset обнуляет оба поля. Это контейнер данных, а не граф вычислений или механизм автоматического дифференцирования. Скалярная специализация по-прежнему принимает арифметические типы, тензорная — Tensor; контракт типов в этом исправлении не сужается.

CMake: UniversalDevKit::Helpers.Headers. NuGet: UniversalDevKit.Helpers с linkage Shared. Android: universaldevkit-helpers-shared-release и udk_helpers_shared::Helpers. Реестр и проекты Shared/HeaderCheck создаются штатным генератором. HeleprsTest/Math.h не изменён.

AndroidPrefab.Tests.ps1 -Components Helpers -SkipDevice собирает отдельный JNI/APK consumer из AAR; без устройства это не подтверждает runtime.

Контракт rank-0 и проверка границ Tensor остаются отдельными задачами. Исходные вспомогательные details и встроенные compile-time тесты пока сохранены.