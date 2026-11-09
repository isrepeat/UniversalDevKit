using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Controls;

using Polygon = System.Windows.Shapes.Polygon;
using ShapePath = System.Windows.Shapes.Path;

namespace AndroidAppPreviewer {
    internal sealed class NavigationGraphController {
        private const double CardWidth = 176.0;
        private const double CardHeight = 74.0;
        private const double CardHorizontalSpacing = 48.0;
        private const double LayerSpacing = 154.0;
        private readonly Canvas graph;
        private readonly NavigationGraphControl navigationGraphControl;
        private readonly Action<string> reportInformation;
        // Для каждой цели хранится последний выбранный вариант, чтобы возврат к узлу не сбрасывал ветку.
        private readonly Dictionary<string, IReadOnlyList<string>> lastPathByTarget = new(StringComparer.Ordinal);
        private readonly Dictionary<string, Button> nodes = [];
        private readonly Dictionary<string, RouteSlot> routeSlots = new(StringComparer.Ordinal);
        private IReadOnlyList<PreviewRoute> routes = [];
        private IReadOnlyDictionary<string, string> pageTitles = new Dictionary<string, string>(StringComparer.Ordinal);
        private IReadOnlyList<PreviewRoute> selectedPath = [];
        private IReadOnlyList<IReadOnlyList<PreviewRoute>> pathCandidates = [];
        // Это множество используется только для пунктирных продолжений после выбранной цели.
        private IReadOnlySet<string> reachablePagesFromSelectedTarget = new HashSet<string>(StringComparer.Ordinal);
        private string? selectedTarget;
        private string? currentPage;
        private string? layoutRootPage;

        public event Action<string>? ActivePageChanged;
        public event Action<IReadOnlyList<string>>? RouteConfirmed;

        public string? CurrentPage => this.currentPage;

        public NavigationGraphController(
            NavigationGraphControl navigationGraphControl,
            Action<string> reportInformation) {
            this.navigationGraphControl = navigationGraphControl;
            this.graph = navigationGraphControl.Graph;
            this.reportInformation = reportInformation;
            navigationGraphControl.GraphBackgroundPressed += this.GraphBackgroundPressed;
            navigationGraphControl.PathCandidatePressed += this.PathCandidatePressed;
        }

        public void SetRoutes(
            IReadOnlyList<PreviewRoute> routes,
            IReadOnlyDictionary<string, string> pageTitles,
            string currentPage,
            string layoutRootPage) {
            this.routes = routes;
            this.pageTitles = pageTitles;
            this.layoutRootPage = layoutRootPage;
            this.lastPathByTarget.Clear();
            this.ResetSelection();
            this.Synchronize(currentPage, true);
        }

        public void SetGraph(PreviewNavigationGraph graph) {
            this.SetRoutes(graph.Routes, graph.PageTitles, graph.CurrentPageId, graph.LayoutRootPageId);
        }

        public void Synchronize(string currentPage, bool force = false) {
            if (!force && string.Equals(this.currentPage, currentPage, StringComparison.Ordinal)) {
                return;
            }
            var isPageChange = this.currentPage is not null
                && !string.Equals(this.currentPage, currentPage, StringComparison.Ordinal);
            if (isPageChange) {
                this.ResetSelection();
            }
            this.currentPage = currentPage;
            this.Render();
            if (isPageChange) {
                this.ActivePageChanged?.Invoke(currentPage);
            }
        }

        public void CompleteNavigation(string currentPage) {
            this.ResetSelection();
            this.Synchronize(currentPage, true);
        }

        public void Clear() {
            this.routes = [];
            this.pageTitles = new Dictionary<string, string>(StringComparer.Ordinal);
            this.currentPage = null;
            this.layoutRootPage = null;
            this.lastPathByTarget.Clear();
            this.ResetSelection();
            this.graph.Children.Clear();
            this.navigationGraphControl.SetPathCandidates([]);
        }

        private void NavigationNodeMouseLeftButtonDown(object sender, MouseButtonEventArgs eventArgs) {
            if (sender is not Button { Tag: string target } || this.currentPage is null) {
                return;
            }
            if (eventArgs.ClickCount == 2
                && string.Equals(target, this.selectedTarget, StringComparison.Ordinal)
                && this.selectedPath.Count > 0) {
                this.ConfirmSelectedPath();
                eventArgs.Handled = true;
                return;
            }
            this.SelectTarget(target);
            eventArgs.Handled = true;
        }

        private void GraphBackgroundPressed() {
            if (this.selectedTarget is null) {
                return;
            }
            // Узлы помечают событие обработанным, поэтому сюда попадает только клик по свободному фону.
            this.ResetSelection();
            this.Render();
        }

        private void SelectTarget(string target) {
            if (this.currentPage is null) {
                return;
            }
            if (string.Equals(target, this.currentPage, StringComparison.Ordinal)) {
                this.ResetSelection();
                this.Render();
                return;
            }
            var paths = this.FindPaths(this.currentPage, target);
            if (paths.Count == 0) {
                this.reportInformation($"Нет маршрута из {this.currentPage} в {target}.");
                return;
            }
            this.selectedTarget = target;
            this.pathCandidates = paths;
            this.reachablePagesFromSelectedTarget = this.FindReachablePages(target);
            // При выборе следующей цели продолжаем уже выбранную ветку, если она к ней ведёт.
            var continuation = this.FindPathWithLongestCommonPrefix(paths, this.selectedPath);
            var previous = this.lastPathByTarget.GetValueOrDefault(target);
            this.selectedPath = continuation
                ?? (previous is null
                    ? paths[0]
                    : paths.FirstOrDefault(candidate => candidate.Select(route => route.Id).SequenceEqual(previous)) ?? paths[0]);
            this.lastPathByTarget[target] = this.selectedPath.Select(route => route.Id).ToArray();
            AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Logging.xp_log_info($"Preview graph selected route: {string.Join('>', this.selectedPath.Select(route => route.Id))}; candidates={paths.Count}");
            this.Render();
        }

        private IReadOnlyList<IReadOnlyList<PreviewRoute>> FindPaths(string source, string target) {
            var result = new List<IReadOnlyList<PreviewRoute>>();
            var path = new List<PreviewRoute>();
            var visited = new HashSet<string>(StringComparer.Ordinal) { source };
            void Visit(string page) {
                if (page == target) {
                    result.Add(path.ToArray());
                    return;
                }
                foreach (var route in this.routes.Where(route => route.Source == page)) {
                    if (!visited.Add(route.Target)) {
                        continue;
                    }
                    path.Add(route);
                    Visit(route.Target);
                    path.RemoveAt(path.Count - 1);
                    visited.Remove(route.Target);
                }
            }
            Visit(source);
            return result
                .OrderBy(candidate => candidate.Count)
                .ThenByDescending(candidate => candidate.Count(route => route.IsDefault))
                .ThenBy(candidate => string.Join('/', candidate.Select(route => route.Id)), StringComparer.Ordinal)
                .ToArray();
        }

        private IReadOnlyList<PreviewRoute>? FindPathWithLongestCommonPrefix(
            IReadOnlyList<IReadOnlyList<PreviewRoute>> candidates,
            IReadOnlyList<PreviewRoute> previousPath) {
            if (previousPath.Count == 0) {
                return null;
            }
            var candidate = candidates
                .Select(candidate => new {
                    Path = candidate,
                    CommonPrefixLength = candidate
                        .Zip(previousPath)
                        .TakeWhile(pair => string.Equals(pair.First.Id, pair.Second.Id, StringComparison.Ordinal))
                        .Count(),
                })
                .OrderByDescending(item => item.CommonPrefixLength)
                .First();
            return candidate.CommonPrefixLength == 0 ? null : candidate.Path;
        }

        private void Render() {
            this.graph.Children.Clear();
            this.nodes.Clear();
            // Страницы без переходов тоже являются вершинами графа: например,
            // стартовое приложение с единственной MainPage.
            var pages = this.pageTitles.Keys
                .Concat(this.routes.SelectMany(route => new[] { route.Source, route.Target }))
                .Append(this.currentPage)
                .Append(this.layoutRootPage)
                .Where(page => !string.IsNullOrWhiteSpace(page))
                .Select(page => page!)
                .Distinct()
                .Order()
                .ToArray();
            if (pages.Length == 0) {
                return;
            }
            var graphWidth = this.CalculateGraphWidth(pages);
            var positions = this.CalculateNodePositions(pages, graphWidth);
            this.graph.Width = graphWidth;
            this.graph.Height = Math.Max(this.graph.MinHeight, positions.Values.Max(point => point.Y) + CardHeight + 56.0);
            var routeGroups = this.routes
                .GroupBy(route => PagePair.Create(route.Source, route.Target))
                .ToArray();
            this.AssignRouteSlots(routeGroups, positions);
            foreach (var group in routeGroups) {
                this.DrawRouteGroup(group.Key, group.ToArray(), positions);
            }
            foreach (var page in pages) {
                var position = positions[page];
                var isCurrent = string.Equals(page, this.currentPage, StringComparison.Ordinal);
                var isTarget = string.Equals(page, this.selectedTarget, StringComparison.Ordinal);
                var button = new Button {
                    Width = CardWidth,
                    Height = CardHeight,
                    Tag = page,
                    Content = this.PageTitle(page),
                    Background = new SolidColorBrush(isTarget ? Color.FromRgb(61, 72, 45) : Color.FromRgb(54, 54, 54)),
                    BorderBrush = new SolidColorBrush(isCurrent || isTarget
                        ? isCurrent ? Color.FromRgb(239, 191, 65) : Color.FromRgb(169, 204, 105)
                        : Color.FromRgb(89, 89, 89)),
                    Foreground = new SolidColorBrush(Color.FromRgb(242, 242, 242)),
                    FontSize = 17,
                    FontWeight = FontWeights.SemiBold,
                    Template = this.navigationGraphControl.NavigationNodeButtonTemplate,
                    ToolTip = "Один клик выбирает маршрут; двойной клик подтверждает переход.",
                };
                button.PreviewMouseLeftButtonDown += this.NavigationNodeMouseLeftButtonDown;
                Canvas.SetLeft(button, position.X);
                Canvas.SetTop(button, position.Y);
                this.nodes.Add(page, button);
                this.graph.Children.Add(button);
            }
            this.RenderBranchPanel();
            this.UpdateStatus();
        }

        private void ResetSelection() {
            this.selectedPath = [];
            this.pathCandidates = [];
            this.reachablePagesFromSelectedTarget = new HashSet<string>(StringComparer.Ordinal);
            this.selectedTarget = null;
        }

        private double CalculateGraphWidth(IReadOnlyList<string> pages) {
            var largestLayer = this.GetPageDepths(pages)
                .GroupBy(pair => pair.Value)
                .Max(layer => layer.Count());
            return Math.Max(this.graph.MinWidth, largestLayer * CardWidth + (largestLayer + 1) * CardHorizontalSpacing);
        }

        private Dictionary<string, Point> CalculateNodePositions(IReadOnlyList<string> pages, double width) {
            var depths = this.GetPageDepths(pages);
            var result = new Dictionary<string, Point>(StringComparer.Ordinal);
            foreach (var layer in pages.GroupBy(page => depths[page]).OrderBy(group => group.Key)) {
                var items = layer.OrderBy(this.PageTitle, StringComparer.Ordinal).ToArray();
                var gap = (width - items.Length * CardWidth) / (items.Length + 1);
                for (var index = 0; index < items.Length; ++index) {
                    result.Add(items[index], new Point(gap + index * (CardWidth + gap), 34.0 + layer.Key * LayerSpacing));
                }
            }
            return result;
        }

        private Dictionary<string, int> GetPageDepths(IReadOnlyList<string> pages) {
            var root = this.layoutRootPage is not null && pages.Contains(this.layoutRootPage, StringComparer.Ordinal)
                ? this.layoutRootPage
                : pages.Contains("MainPage", StringComparer.Ordinal) ? "MainPage" : pages[0];
            var depths = new Dictionary<string, int>(StringComparer.Ordinal) { [root] = 0 };
            for (var depth = 0; depth < pages.Count; ++depth) {
                foreach (var route in this.routes.Where(route => depths.TryGetValue(route.Source, out var sourceDepth) && sourceDepth == depth)) {
                    if (!depths.ContainsKey(route.Target)) {
                        depths.Add(route.Target, depth + 1);
                    }
                }
            }
            foreach (var page in pages.Where(page => !depths.ContainsKey(page))) {
                depths.Add(page, depths.Values.DefaultIfEmpty().Max() + 1);
            }
            return depths;
        }

        private void DrawRouteGroup(PagePair pair, IReadOnlyList<PreviewRoute> routes, IReadOnlyDictionary<string, Point> positions) {
            var (firstPage, secondPage) = this.GetOrderedEndpoints(pair, positions);
            var forwardRoutes = routes.Where(route => route.Source == firstPage && route.Target == secondPage).ToArray();
            var backwardRoutes = routes.Where(route => route.Source == secondPage && route.Target == firstPage).ToArray();
            var visibleRoutes = this.GetVisibleRoutes(firstPage, secondPage, routes);
            var selectedBackwardRoute = backwardRoutes.FirstOrDefault(route => this.selectedPath.Any(item => item.Id == route.Id));
            var selectedBackwardOfRouteId = selectedBackwardRoute?.BackwardOfTransitionId;
            for (var index = 0; index < visibleRoutes.Count; ++index) {
                var route = visibleRoutes[index];
                var connection = this.CreateConnectionGeometry(
                    positions[firstPage],
                    positions[secondPage],
                    this.routeSlots[route.Id]);
                var isSelectedRoute = this.selectedPath.Any(item => item.Id == route.Id);
                var isSelectedBackwardRoute = selectedBackwardRoute is not null
                    && string.Equals(route.Id, selectedBackwardOfRouteId, StringComparison.Ordinal);
                var isSelected = isSelectedRoute || isSelectedBackwardRoute;
                var isPotential = this.IsPotentialRoute(route);
                var isReachableFromSelectedTarget = !isSelected && !isPotential && this.IsReachableFromSelectedTarget(route);
                var brush = isSelected ? Brushes.Gold : isPotential || isReachableFromSelectedTarget ? Brushes.SlateGray : Brushes.DimGray;
                var opacity = this.selectedTarget is null || isPotential || isReachableFromSelectedTarget || isSelectedBackwardRoute ? 1.0 : 0.22;
                this.graph.Children.Add(new ShapePath {
                    Data = connection.Data,
                    Stroke = brush,
                    StrokeThickness = isSelected ? 4.0 : isPotential ? 2.0 : 1.5,
                    StrokeDashArray = isReachableFromSelectedTarget ? new DoubleCollection([6.0, 4.0]) : null,
                    Opacity = opacity,
                    IsHitTestVisible = false,
                });
                if (isSelectedRoute) {
                    var isForward = route.Source == firstPage;
                    var arrowTip = isForward ? connection.SecondPoint : connection.FirstPoint;
                    var arrowTail = isForward ? connection.SecondPreviousPoint : connection.FirstNextPoint;
                    this.graph.Children.Add(this.CreateRouteArrow(arrowTip, arrowTail, brush, opacity));
                    this.graph.Children.Add(this.CreateRouteStepBadge(arrowTip, arrowTail, this.GetPathStep(route.Id)));
                }
                if (isSelectedBackwardRoute && selectedBackwardRoute is not null) {
                    this.graph.Children.Add(this.CreateRouteArrow(connection.FirstPoint, connection.FirstNextPoint, brush, opacity));
                    this.graph.Children.Add(this.CreateRouteStepBadge(
                        connection.FirstPoint,
                        connection.FirstNextPoint,
                        this.GetPathStep(selectedBackwardRoute.Id)));
                }
            }
        }

        private void AssignRouteSlots(
            IReadOnlyList<IGrouping<PagePair, PreviewRoute>> routeGroups,
            IReadOnlyDictionary<string, Point> positions) {
            this.routeSlots.Clear();
            var routedRoutes = routeGroups
                .SelectMany(group => {
                    var (firstPage, secondPage) = this.GetOrderedEndpoints(group.Key, positions);
                    return this.GetVisibleRoutes(firstPage, secondPage, group.ToArray())
                        .Select(route => new RoutedRoute(route, this.GetRouteLaneKey(positions[firstPage], positions[secondPage], group.Key)));
                })
                .ToArray();
            foreach (var lane in routedRoutes.GroupBy(route => route.LaneKey)) {
                var routes = lane.OrderBy(route => route.Route.Id, StringComparer.Ordinal).ToArray();
                for (var index = 0; index < routes.Length; ++index) {
                    this.routeSlots.Add(routes[index].Route.Id, new RouteSlot(index, routes.Length));
                }
            }
        }

        private IReadOnlyList<PreviewRoute> GetVisibleRoutes(string firstPage, string secondPage, IReadOnlyList<PreviewRoute> routes) {
            var forwardRoutes = routes.Where(route => route.Source == firstPage && route.Target == secondPage).ToArray();
            if (forwardRoutes.Length > 0) {
                return forwardRoutes;
            }
            return [routes.Single(route => route.Source == secondPage && route.Target == firstPage)];
        }

        private string GetRouteLaneKey(Point first, Point second, PagePair pair) {
            if (Math.Abs(second.Y - first.Y) > 0.01) {
                return $"vertical:{first.Y}:{second.Y}";
            }
            var distance = Math.Abs(second.X - first.X);
            return distance <= CardWidth + CardHorizontalSpacing * 1.5
                ? $"direct:{pair.FirstPage}:{pair.SecondPage}"
                : $"bypass:{first.Y}";
        }

        private ConnectionGeometry CreateConnectionGeometry(Point first, Point second, RouteSlot routeSlot) {
            var firstCenter = new Point(first.X + CardWidth / 2.0, first.Y + CardHeight / 2.0);
            var secondCenter = new Point(second.X + CardWidth / 2.0, second.Y + CardHeight / 2.0);
            var portOffset = (routeSlot.Index + 1.0) / (routeSlot.Count + 1.0);
            if (Math.Abs(secondCenter.Y - firstCenter.Y) > 0.01) {
                var firstPoint = new Point(first.X + CardWidth * portOffset, first.Y + CardHeight);
                var secondPoint = new Point(second.X + CardWidth * portOffset, second.Y);
                var laneY = firstPoint.Y + (secondPoint.Y - firstPoint.Y) * portOffset;
                return this.CreateOrthogonalConnection([
                    firstPoint,
                    new Point(firstPoint.X, laneY),
                    new Point(secondPoint.X, laneY),
                    secondPoint,
                ]);
            }
            var horizontalDistance = Math.Abs(secondCenter.X - firstCenter.X);
            if (horizontalDistance <= CardWidth + CardHorizontalSpacing * 1.5) {
                return this.CreateOrthogonalConnection([
                    new Point(first.X + CardWidth, first.Y + CardHeight * portOffset),
                    new Point(second.X, second.Y + CardHeight * portOffset),
                ]);
            }
            var firstBottom = new Point(first.X + CardWidth * portOffset, first.Y + CardHeight);
            var secondBottom = new Point(second.X + CardWidth * portOffset, second.Y + CardHeight);
            var bypassLaneY = Math.Max(firstBottom.Y, secondBottom.Y) + 20.0 + routeSlot.Index * 12.0;
            return this.CreateOrthogonalConnection([
                firstBottom,
                new Point(firstBottom.X, bypassLaneY),
                new Point(secondBottom.X, bypassLaneY),
                secondBottom,
            ]);
        }

        private ConnectionGeometry CreateOrthogonalConnection(IReadOnlyList<Point> points) {
            var routePoints = points.Where((point, index) => index == 0 || point != points[index - 1]).ToArray();
            var segments = routePoints.Skip(1).Select(point => (PathSegment)new LineSegment(point, true)).ToArray();
            return new ConnectionGeometry(
                new PathGeometry([new PathFigure(routePoints[0], segments, false)]),
                routePoints[0],
                routePoints[1],
                routePoints[^2],
                routePoints[^1]);
        }

        private bool IsPotentialRoute(PreviewRoute route) {
            return this.pathCandidates.Any(path => path.Any(item => item.Id == route.Id));
        }

        private bool IsReachableFromSelectedTarget(PreviewRoute route) {
            return this.reachablePagesFromSelectedTarget.Contains(route.Source);
        }

        private IReadOnlySet<string> FindReachablePages(string source) {
            // Обходим ориентированный граф: пунктир показывает все возможные действия после цели,
            // а не только её непосредственные исходящие переходы.
            var reachablePages = new HashSet<string>(StringComparer.Ordinal) { source };
            var pagesToVisit = new Queue<string>([source]);
            while (pagesToVisit.TryDequeue(out var page)) {
                foreach (var route in this.routes.Where(route => route.Source == page)) {
                    if (reachablePages.Add(route.Target)) {
                        pagesToVisit.Enqueue(route.Target);
                    }
                }
            }
            return reachablePages;
        }

        private (string FirstPage, string SecondPage) GetOrderedEndpoints(PagePair pair, IReadOnlyDictionary<string, Point> positions) {
            var first = positions[pair.FirstPage];
            var second = positions[pair.SecondPage];
            if (first.Y < second.Y || (Math.Abs(first.Y - second.Y) < 0.01 && first.X <= second.X)) {
                return (pair.FirstPage, pair.SecondPage);
            }
            return (pair.SecondPage, pair.FirstPage);
        }

        private Polygon CreateRouteArrow(Point tip, Point tail, Brush fill, double opacity) {
            var direction = tip - tail;
            direction.Normalize();
            var normal = new Vector(-direction.Y, direction.X);
            return new Polygon {
                Points = new PointCollection {
                    tip,
                    tip - direction * 11.0 + normal * 5.0,
                    tip - direction * 11.0 - normal * 5.0,
                },
                Fill = fill,
                Opacity = opacity,
                IsHitTestVisible = false,
            };
        }

        private Border CreateRouteStepBadge(Point tip, Point tail, int step) {
            var direction = tip - tail;
            var isVertical = Math.Abs(direction.Y) >= Math.Abs(direction.X);
            var badge = new Border {
                Width = 20.0,
                Height = 20.0,
                Background = new SolidColorBrush(Color.FromRgb(78, 65, 28)),
                BorderBrush = Brushes.Gold,
                BorderThickness = new Thickness(1.0),
                Child = new TextBlock {
                    Text = step.ToString(),
                    FontSize = 11.0,
                    FontWeight = FontWeights.SemiBold,
                    Foreground = Brushes.White,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                },
                IsHitTestVisible = false,
            };
            Canvas.SetLeft(badge, isVertical ? tip.X + 8.0 : tip.X - 10.0);
            Canvas.SetTop(badge, isVertical ? tip.Y - 10.0 : tip.Y - 28.0);
            Panel.SetZIndex(badge, 100);
            return badge;
        }

        private int GetPathStep(string routeId) {
            return this.selectedPath
                .Select((route, index) => new { route.Id, Step = index + 1 })
                .Single(item => item.Id == routeId)
                .Step;
        }

        private string PageTitle(string page) {
            return this.pageTitles.GetValueOrDefault(page, page);
        }

        private void RenderBranchPanel() {
            if (this.selectedTarget is null) {
                this.navigationGraphControl.SetPathCandidates([]);
                return;
            }
            var candidates = this.pathCandidates
                .Select((path, index) => new PathCandidate(
                    path,
                    $"Путь {index + 1}",
                    path.Select(route => $"{this.PageTitle(route.Source)}: {route.Title}").ToArray(),
                    path.Select(route => route.Id).SequenceEqual(this.selectedPath.Select(route => route.Id))))
                .Cast<object>()
                .ToArray();
            this.navigationGraphControl.SetPathCandidates(candidates);
        }

        private void PathCandidatePressed(object candidate, int clickCount) {
            if (candidate is not PathCandidate pathCandidate || this.selectedTarget is null) {
                return;
            }
            var isAlreadySelected = pathCandidate.Routes.Select(route => route.Id).SequenceEqual(this.selectedPath.Select(route => route.Id));
            this.selectedPath = pathCandidate.Routes;
            this.lastPathByTarget[this.selectedTarget] = this.selectedPath.Select(route => route.Id).ToArray();
            if (clickCount == 2 && isAlreadySelected) {
                this.ConfirmSelectedPath();
                return;
            }
            this.Render();
        }

        private void ConfirmSelectedPath() {
            var transitionIds = this.selectedPath.Select(route => route.Id).ToArray();
            AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.Logging.xp_log_info($"Preview graph confirmed transitions: {string.Join('>', transitionIds)}");
            this.RouteConfirmed?.Invoke(transitionIds);
        }

        private void UpdateStatus() {
            if (this.currentPage is null) {
                return;
            }
            if (this.selectedTarget is null) {
                this.reportInformation($"Активная страница: {this.PageTitle(this.currentPage)}. Выберите страницу, чтобы увидеть пути к ней.");
                return;
            }
            this.reportInformation($"Выбран путь «{string.Join(" → ", this.selectedPath.Select(route => route.Title))}». Выберите другую ветку слева или дважды нажмите целевую страницу.");
        }

        private sealed record ConnectionGeometry(
            PathGeometry Data,
            Point FirstPoint,
            Point FirstNextPoint,
            Point SecondPreviousPoint,
            Point SecondPoint);

        private sealed record RouteSlot(int Index, int Count);

        private sealed record RoutedRoute(PreviewRoute Route, string LaneKey);

        private sealed record PathCandidate(
            IReadOnlyList<PreviewRoute> Routes,
            string Title,
            IReadOnlyList<string> Steps,
            bool IsSelected);

        private sealed record PagePair(string FirstPage, string SecondPage) {
            public static PagePair Create(string sourcePage, string targetPage) {
                return string.CompareOrdinal(sourcePage, targetPage) <= 0
                    ? new PagePair(sourcePage, targetPage)
                    : new PagePair(targetPage, sourcePage);
            }
        }
    }
}