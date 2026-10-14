# Пакеты UniversalDevKit

Тестовые заглушки разных способов доставки находятся в Tests/Fixtures/Packages. Команда Tests/Infrastructure/BuildTestPackages.ps1 выпускает их в явно указанный временный каталог; Android Maven собирается отдельным Gradle-сценарием теста. Это не новые продуктовые записи Package.json. Матрица покрытия существующих NugetProjects и Android AAR описана в [проверках доставки](../Tests/Integration/Packages/README.md).

Для выпуска конкретного NuGet-пакета запускайте Scripts/Packages/CrossPlatform/Pack.Helpers.cmd или Pack.Diagnostic.cmd. Helpers выпускает только Helpers; Diagnostic выпускает Diagnostic и обязательный Helpers. Общей CMD-команды выпуска всех пакетов нет. Обёртки передают MIT LICENSE из корня репозитория, принимают дополнительные параметры упаковщика и завершаются паузой с сохранением кода операции.

Пакеты группируются по назначению: CrossPlatform, Windows и Android. Каждый пакет содержит Package.json и Delivery/<способ>/ с описаниями доставки. Категория CrossPlatform обозначает назначение продукта; фактически проверенные платформы перечисляются в Delivery.json.

Helpers и Diagnostic находятся в CrossPlatform и ссылаются на компоненты UDK без копирования исходников. Sources и Projects внутри пакета создаются только для дополнительных исходников и проектов. Пустые каталоги не создаются.

Общий NuGet-упаковщик и шаблоны находятся в Packages/Build/NuGet. Текущий адаптер component связывает пакет с одним компонентом, а его package ID читается из Delivery.json. Другие адаптеры для шаблонов, инструментов и составных пакетов будут добавляться отдельно. Версия компонентных пакетов читается через versionSource из Version.json. Готовые пакеты и промежуточные файлы — в !artifacts.

Собственные nuspec, targets и при необходимости props находятся непосредственно в Delivery/NuGet каждого пакета. Они перечислены в Delivery.json: nuspec и integration. Props/targets копируются без подстановок и могут содержать индивидуальную логику. Общий упаковщик генерирует данные выпуска и рассчитанные настройки графа в Generated/Settings.props и Settings.targets; пакет подключает их явными imports.