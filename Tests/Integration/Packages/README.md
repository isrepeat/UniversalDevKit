# Проверки доставки пакетов

Результаты и binlogs сохраняются под !artifacts/tests. Рабочие пакеты проверяются отдельно от synthetic-fixtures.

| Сценарий | Что проверяет |
|---|---|
| NuGet.PackageReference.Tests.ps1 | Helpers/Diagnostic по умолчанию, явно выбранные XAML-компоненты, restore и запуск |
| NuGet.Registry.Tests.ps1 | HeaderProbe → HeaderLeaf: независимость упаковщика от рабочего реестра |
| ../Cmake/Diamond.Tests.ps1 | CMake и NuGet, public/private графы, варианты и доставка DLL |
| AndroidPrefab.Tests.ps1 | APK, Prefab и SO рабочих Android-компонентов |
| AndroidKotlin.Tests.ps1 | Kotlin AAR, Maven и транзитивные зависимости |
| PackageDelivery.Tests.ps1 | Механизмы доставки на изолированных fixtures |
| PackageTools.Migration.Tests.ps1 | Все Package.xml версии 2, 13 доставок, отсутствие старых упаковщиков; BaselineDirectory сверяет файлы и NuGet-зависимости, CheckMaven — Android-публикации |
| PackageComposition.Tests.ps1 | JSON-граф смешанных проектов, установленный PackageTools, точные NuGet-зависимости, состав пакета и ошибки контрактов |
| PackageContents.Tests.ps1 | Источники project/root/path и source, маски include/exclude, rename, сохранение и уплощение дерева, отклонение устаревших полей и конфликтов; UdkCliDirectory проверяет скрипты из поставки UdkCli |

Общий Windows component-шаблон для synthetic-fixtures находится в ../../Fixtures/Packages/NativeComponent. Он не регистрируется и не выпускается как рабочий компонент.

См. [Windows NuGet](../../../Packages/Build/NuGet/README.md), [Android AAR/Prefab](../../../Packages/Build/Android/README.md) и [общие проверки](../../README.md).