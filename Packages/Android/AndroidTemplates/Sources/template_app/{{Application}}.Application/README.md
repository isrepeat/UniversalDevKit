# Application framework

Каркас общий для Android host и PreviewPlugin. ApplicationSession владеет хранилищем состояния, репозиторием и PageManager. Хост передаёт размер поверхности, ввод и render backend; Kotlin не создаёт страницы и не хранит историю навигации.

## Навигация

- PageManager владеет PageRegistry, lifecycle страниц, input/animation controllers и историей. Зарегистрированные страницы и их bindings сохраняются до уничтожения сессии.
- Маршруты объявляются в PageManager::Routes(). Для перехода используются Trigger и типизированный NavigationState<T>.
- Main передаёт GreetingNavigationState.Message из ApplicationRepository. Settings требует этот payload и публикует Message в XAML binding.
- Перед активацией вызываются OnNavigatingFrom и OnNavigatingTo; контракт проверяет обязательность данных и TypeId. Отклонённый переход не меняет текущую страницу и историю.
- previousPage берётся из фактической истории. Загрузка уже активной страницы не сбрасывает стек.
- preview_Routes() публикует граф. Previewer передаёт в xp_navigate только transitionIds, а native создаёт и проверяет hasPreviewDefaultNavigationState. Весь путь проверяется до начала переходов; lifecycle может отклонить отдельный шаг.
- Reload разметки сохраняет экземпляр view model, payload и историю. Runtime bindings используют те же команды и свойства.

## Анимации переходов

PageManager подключает все страницы к одному AnimationController. При навигации изменение visibility запускает Show/Hide и ParentShow/ParentHide. Группа визуальных состояний NavigationDirection получает Idle, затем Forward для обычного маршрута или Backward для previousPage. Эту группу можно не объявлять.

Пока анимации входящей и исходящей страниц не завершены, обе страницы участвуют в рендеринге, а ввод и повторная навигация блокируются. Без анимаций переход заканчивается сразу. Android и PreviewPlugin используют ApplicationSession::Render; Root() остаётся корнем текущей страницы для инспекции и ввода.

Пример появления и скрытия страницы:

```xml
<Page.Storyboards>
    <Storyboard trigger="Show">
        <FloatAnimation property="opacity" from="0" to="1" duration="180" easing="CubicOut"/>
    </Storyboard>
    <Storyboard trigger="Hide">
        <FloatAnimation property="opacity" from="Current" to="0" duration="180" easing="CubicOut"/>
    </Storyboard>
</Page.Storyboards>
```

В Storyboard визуального состояния указывайте targetName с id элемента. ColorAnimation меняет цвет и альфу background, foreground, borderBrush или tint; from="Current" начинает переход с текущего цвета. Для изменения только прозрачности фона анимируйте background: opacity всей Page затрагивает также текст и кнопки. Эффективный opacity каждого элемента ограничен диапазоном 0…1. Именованные пользовательские Animation требуют регистрации реализации в runtime.

Первоначальная загрузка и hot reload не проигрывают переход. Reload завершает текущий переход и переподключает деревья, сохраняя view model и историю. В пути графа preview промежуточные анимации доводятся до конца сразу, последний переход проигрывается в цикле кадров.

## Состояние и хост

ApplicationStateStore принимает callback сохранения документа. При ошибке сохранения прежний документ остаётся активным. В preview доступен отдельный документ в памяти и явный экспорт. AppRepositoryBase не зависит от предметной области. AppSessionController передаёт платформенные события через callback.

Android использует GLSurfaceView и JNI. ApplicationSession сохраняется при pause/resume; OpenGL renderer освобождается на GL-потоке. При уничтожении Activity сессия уничтожается. Постоянное хранение включается передачей callback в ApplicationSession.