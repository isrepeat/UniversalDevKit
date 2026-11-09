using System.IO;
using System.Text.RegularExpressions;
using System.Windows.Threading;

namespace AndroidAppPreviewer {
    internal sealed record WorkspaceControl(string Name, string Path, string? Id);

    internal sealed class WorkspaceController : IDisposable {
        private readonly PreviewFileWatchController fileWatchController;

        public WorkspaceController(Dispatcher dispatcher, Action refresh) {
            this.fileWatchController = new PreviewFileWatchController(dispatcher, refresh);
        }

        public IReadOnlyList<string> DiscoverPages(string xamlDirectory) {
            return Directory.Exists(xamlDirectory)
                ? Directory.GetFiles(xamlDirectory, "*.xaml", SearchOption.AllDirectories)
                    .Select(path => Path.GetRelativePath(xamlDirectory, path))
                    .Where(path => !path.StartsWith("Pages\\backup\\", StringComparison.OrdinalIgnoreCase))
                    .Order()
                    .ToArray()
                : [];
        }

        public string? GetPagePath(string xamlDirectory, string? pageName) {
            return string.IsNullOrEmpty(pageName) ? null : Path.GetFullPath(Path.Combine(xamlDirectory, pageName));
        }

        public IReadOnlyList<WorkspaceControl> DiscoverControls(string pagePath, string controlsDirectory) {
            if (!File.Exists(pagePath)) {
                return [];
            }
            var controlPaths = Directory.Exists(controlsDirectory)
                ? Directory.GetFiles(controlsDirectory, "*.xaml", SearchOption.AllDirectories).ToDictionary(path => Path.GetFileNameWithoutExtension(path), StringComparer.Ordinal)
                : new Dictionary<string, string>(StringComparer.Ordinal);
            var result = new List<WorkspaceControl>();
            var visitedPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { pagePath };
            var pathsToInspect = new Queue<string>();
            pathsToInspect.Enqueue(pagePath);
            var controlPattern = new Regex("<\\w+:(?<name>[A-Za-z][A-Za-z0-9]*)\\b(?<attributes>[^>]*)>", RegexOptions.CultureInvariant);
            var idPattern = new Regex("\\bid\\s*=\\s*\"(?<id>[^\"]+)\"", RegexOptions.CultureInvariant);
            while (pathsToInspect.TryDequeue(out var sourcePath)) {
                foreach (Match match in controlPattern.Matches(File.ReadAllText(sourcePath))) {
                    var name = match.Groups["name"].Value;
                    if (!controlPaths.TryGetValue(name, out var controlPath)) {
                        continue;
                    }
                    var idMatch = idPattern.Match(match.Groups["attributes"].Value);
                    result.Add(new WorkspaceControl(name, controlPath, idMatch.Success ? idMatch.Groups["id"].Value : null));
                    if (visitedPaths.Add(controlPath)) {
                        pathsToInspect.Enqueue(controlPath);
                    }
                }
            }
            return result;
        }

        public string ResolveResourcesDirectory(string xamlDirectory) {
            for (var directory = Directory.Exists(xamlDirectory) ? new DirectoryInfo(xamlDirectory) : null; directory is not null; directory = directory.Parent) {
                var resourcesDirectory = Path.Combine(directory.FullName, "Resources");
                if (Directory.Exists(Path.Combine(resourcesDirectory, "Icons"))) {
                    return resourcesDirectory;
                }
            }
            return string.Empty;
        }

        public void ConfigureWatchers(string? markupPath, string? scenarioPath, PreviewerSettings settings) {
            this.fileWatchController.Configure(markupPath, scenarioPath, settings.FilePath, settings.XamlDirectory, settings.ControlsDirectory);
        }

        public void Dispose() {
            this.fileWatchController.Dispose();
        }
    }
}