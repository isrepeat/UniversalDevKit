# Подключение компонентов через Connect

**Навигация:** [Главная](../README.md) → [Документация](README.md) → Connect

Connect подключает компоненты UDK к C++-проекту Visual Studio и рассчитывает зависимости, include-пути, import-макросы и DLL. Запуск: `Scripts/Connect.cmd`. Перед записью проверяется актуальность реестра и сгенерированных проектов; обновление — `Scripts/GenerateComponentProjects.cmd`.

## Выбор режима

| Компонент | Допустимые режимы |
|---|---|
| Helpers | Shared: только заголовки, отдельной библиотеки нет |
| Diagnostic | Dynamic: общий process-state сервис DLL/SO |
| XamlRuntime, OpenGLESRenderer | Shared, Static, Dynamic |
| AndroidAppPreviewerPluginSdk | Shared, Static, Dynamic; только Windows |

Shared компилирует реализацию внутри consumer, Static связывает отдельную .lib, Dynamic — импортную .lib и доставляет DLL. Header-only зависимости остаются заголовочными независимо от режима корня. Process-state зависимости подключаются через общий Dynamic-компонент даже при Shared-корне.

```powershell
./Scripts/PowerShell/Connect.ps1 -SolutionPath C:/Projects/App/App.sln -ProjectPath C:/Projects/App/App.vcxproj -Components Helpers,Diagnostic -ComponentModes @{ Helpers = 'Shared'; Diagnostic = 'Dynamic' }
```

ProjectOnly не меняет solution и поддерживает только Shared-корни. Для header-only Helpers:

```powershell
./Scripts/PowerShell/Connect.ps1 -ProjectOnly -ProjectPath C:/Projects/App/App.vcxproj -Components Helpers
```

## Граф зависимостей

Каждая связь в Projects/Components/*.json задаёт component, visibility и linkage. Списки файлов принадлежат компонентам, а не копируются в проект приложения.

- public передаёт публичные требования зависимости потребителю; private оставляет её деталью реализации.
- same выбирает режим родительского бинарного компонента; static и dynamic фиксируют режим зависимости.
- Private Static-зависимость DLL включается в её код при линковке. Для Static-корня необходимые .lib должны дойти до финального линкера; архивы автоматически не сливаются.
- Транзитивные DLL доставляются к consumer, даже если зависимость private.
- Несовместимые режимы одного компонента отклоняются до записи файлов.

Например, XamlRuntime использует Helpers.Headers и Diagnostic.Dynamic. Native Preview SDK использует статические XamlRuntime/OpenGLESRenderer и динамический Diagnostic. Отдельный выбор XamlRuntime.Dynamic одновременно с таким SDK конфликтует со статическим требованием.

## Изменение подключения

В меню стрелки выбирают строку, Space меняет отметку, Enter на Apply применяет выбор. Недоступные варианты помечаются причиной; проверка учитывает существующие подключения и ожидающие изменения. Повторный Apply не должен дублировать управляемые imports или проекты.

```powershell
./Scripts/PowerShell/Connect.ps1 -SolutionPath C:/Projects/App/App.sln -ProjectPath C:/Projects/App/App.vcxproj -Disconnect -Components Diagnostic
```

Без Components интерактивный Disconnect показывает выбор; в неинтерактивном режиме отключает все управляемые компоненты. Файлы проекта вне управляемых блоков сохраняются. Для проверки плана используйте Preview; подробности параметров — [инструменты](Tools.md).

## Файлы и проверка

Режимы сохраняются в свойствах UniversalDevKit<Имя>Linkage. Публичные пути — Includes/Core и include-корни рассчитанного графа, включая платформенные корни. Shared-проекты предоставляют .vcxitems; библиотечные варианты — ProjectReference. Connect также хранит отпечатки реестра и останавливает сборку при устаревшем подключении.

[Diamond-fixture](../Tests/Fixtures/Libraries/Diamond) проверяет Shared/Static/Dynamic, private/static и public-цепочки независимо от набора рабочих компонентов. Export-fixture проверяет таблицу экспортов; [Diagnostic](Diagnostic.md) имеет отдельные проверки process-state и логирования.