# Вызовы Kotlin из C++

```cpp
jni::Object target(environment, kotlinObject);
auto dispatch = target.GetMethod<void(jint, jni::Utf8Bytes, jni::Utf8Bytes)>("dispatch");
dispatch.Call(target, 1, "message", "details");

auto enabled = target.GetMethod<bool()>("isEnabled");
bool value = enabled.Call(target);

auto setTitle = target.GetMethod<void(jni::String)>("setTitle");
setTitle.Call(target, u"Заголовок");
```

Сигнатура строится по типам: `void` → `V`, `bool` → `Z`, `jint` → `I`,
`jlong` → `J`, `String` → `Ljava/lang/String;`, `Utf8Bytes` → `[B`.
`String` принимает `std::u16string_view`, сохраняя UTF-16, включая NUL и суррогатные пары.
`Utf8Bytes` принимает `std::string_view`; Kotlin декодирует полученный `ByteArray` как UTF-8.
Возвращаемые типы первой версии: `void`, `bool`, `jint`, `jlong`.

`GetMethod` ищет instance-метод один раз. Имя и сигнатура проверяются JVM во время
выполнения; неподдерживаемые C++-типы отклоняются при компиляции.
Метод связан с исходным объектом: передача другого объекта в `Call` вызывает исключение.
`Object` допускает перемещение, но не копирование. Метод удерживает общую global reference,
поэтому её время жизни покрывает все сохранённые методы. Освобождать объекты нужно до остановки JVM.

Для каждого вызова берётся `JNIEnv*` текущего потока. Если поток не подключён к JVM,
`Environment` подключает его и отключает после вызова. Временные аргументы удаляются
через local frame, в том числе при исключении. `LocalRef` предназначен для отдельной
локальной ссылки и должен уничтожаться на создавшем её потоке до отключения от JVM.

Java-исключения записываются в logcat через `ExceptionDescribe`, очищаются и переводятся
в `std::runtime_error` с контекстом операции. На границе JNI C++-исключение обязательно
перехватывается; `Native.cpp` передаёт его Kotlin как `IllegalStateException`.
В собственном native-потоке вызывающий код также обязан перехватить исключение.

Этот слой не переключает выполнение на Android UI-поток. За это отвечает Kotlin
`NativeCommandDispatcher`. Методы, вызываемые по имени, сохраняются через
`@androidx.annotation.Keep`. Одновременный вызов поддерживается на уровне JNI-ссылок,
но потокобезопасность самого Kotlin-объекта обеспечивает его реализация.