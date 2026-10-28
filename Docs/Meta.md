# Meta

Header-only компонент C++20 без бинарников и платформенных зависимостей. Основной namespace — universaldevkit::meta; классы из папки Utilities находятся в universaldevkit::meta::utilities согласно иерархии каталогов. В Visual Studio исходники представлены Meta.Shared; Meta.HeaderCheck компилирует каждый зарегистрированный заголовок в общем проверочном приложении и предоставляет контекст IntelliSense.

## Структура

- Concepts.h: Dereferenceable, IteratorOf и ErasableContainer.
- FunctionTraits.h: сигнатуры функций, методов и объектов с operator().
- Logic.h: IF_value_c выбирает compile-time значение вместе с его типом.
- TypeTraits.h: ExtractUnderlyingType и ExtractUnderlyingType_t извлекают первый аргумент типа шаблонного контейнера; обычный тип остаётся неизменным. Это не аналог std::underlying_type для enum и не рекурсивное раскрытие контейнеров.
- Diagnostics.h: dependent_false_v для зависимых static_assert.
- Tags.h: пустой маркер nothing.
- Utilities/PointerGetter.h: адрес объекта, сырой указатель или указатель из unique_ptr/shared_ptr.
- Utilities/ValueExtractor.h: рекурсивное разыменование до конечного объекта; входные указатели должны быть действительны, а разыменование должно приводить к объекту с достаточным временем жизни.
- Utilities/TypeErasedDeleter.h: удаление одиночного объекта через void*. Make<T> использует delete T*, не delete[]; вызов должен происходить с допустимым для исходного объекта allocator/CRT и до выгрузки содержащего deleter модуля.

Пути Pointer.h, Value.h и TypeErasedDeleter.h из первого переноса заменены точными именами в Utilities без совместимых обёрток.

## FunctionTraits

```cpp
#include <UniversalDevKit/Meta/FunctionTraits.h>

using Traits = universaldevkit::meta::FunctionTraits<int(*)(double) noexcept>;
static_assert(Traits::ArgumentCount == 1);
static_assert(Traits::IsNoexcept);
using Result = Traits::Ret;
using FirstArgument = Traits::arg<0>::type;
```

Ret, Arguments и arg<I>::type сохраняют типы сигнатуры. arg_val<I>::type снимает ссылку и один уровень указателя, сохраняя cv-квалификаторы оставшегося типа. Class содержит тип класса для метода/функтора и void для свободной функции. Signature содержит указатель на функцию или метод. Kind различает CstyleFunc, ClassMember и Functor. IsConst, IsVolatile, IsNoexcept и Ref описывают квалификаторы функции/метода. Верхнеуровневые cv/ref самого переданного типа нормализуются.

Поддерживаются функции, указатели и ссылки на функции, указатели на методы со всеми cv/ref/noexcept-комбинациями, функторы и лямбды с единственным доступным operator(). C-style variadic-функции и специфичные calling conventions вне штатного профиля Windows x64/Android не входят в контракт. Конструкторы, деструкторы и поля не являются функциями этого API.

Для перегруженного или шаблонного operator() требуется явная сигнатура с нужными квалификаторами:

```cpp
auto identity = [](auto value) { return value; };
using Traits = universaldevkit::meta::FunctionTraitsWithSignature<
    decltype(identity), int(int) const>;
```

concepts::has_call_op_with_signature<T, Signature> проверяет возможность такого выбора. Signature в результате соответствует выбранному указателю на метод, Kind остаётся Functor. Это исправляет старую классификацию FunctionTraitsWithSignature как ClassMember.

concepts::has_method, has_method_with_signature, has_static_function и has_static_function_with_signature сохраняют имена, используемые старым CommandLineParser. Проверки неподдерживаемого типа возвращают false; доступ к отсутствующим членам FunctionTraits даёт ошибку компиляции. Старые C++17 fallback, v1/vLatest и дублирующие переменные has_*_v не переносятся. Старый has_type не перенесён: проверка typename T не задавала полезного требования к содержимому T.

Макрос __requires_expr(...) разворачивается в requires (...) для читаемого форматирования ограничений в Visual Studio; минимальный стандарт остаётся C++20.

## Подключение и проверки

CMake: UniversalDevKit::Meta.Headers. NuGet: UniversalDevKit.Meta, linkage Shared. Android: universaldevkit-meta-shared-release через udk_meta_shared::Meta и штатный udk_android_link; подробнее в Packages/Build/Android/README.md.

Tests/Fixtures/Consumers/MetaPackage проверяет utilities, матрицу FunctionTraits, выбор типов в Logic и concepts. Migration/CommandLineParser.h — изолированный перенос реального старого consumer с заменой namespace, include и requires; исходный UtilityHelpersLib не меняется. Его методы Description, MapParsedResults и Validate проверяются новыми traits при сборке, разбор аргументов выполняется при запуске.

Эти три CTest-сценария входят в TestCMakePackage.ps1. AndroidPrefab.Tests.ps1 -Components Meta -SkipDevice собирает независимый JNI/APK consumer из AAR; для runtime необходим выбранный adb Serial и запуск без SkipDevice.