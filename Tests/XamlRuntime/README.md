# Проверка ColorAnimation

ColorAnimationTests.cpp сравнивает скомпилированную страницу и дерево RuntimeTreeBuilder: начало, середину и завершение Show, визуальное состояние с from="Current", интерполяцию RGBA и отказ при ошибочной разметке. Отдельно проверяет ограничение каждого opacity до композиции с родителем и альфой цвета.

Временный проект Projects/Cmake/XamlRuntime автоматически собирает host-компилятор, генерирует страницу и линкует тест с перенесённым runtime и приватным legacy-логгером. Команды конфигурации приведены в [описании переноса](../../Docs/XamlRuntime.md). После сборки запускайте:

```text
ctest --test-dir !artifacts/Windows-x64/cmake/XamlRuntimeTmp -C Debug --output-on-failure
```