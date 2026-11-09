using System.Windows;
using System.Windows.Controls;

namespace AndroidAppPreviewer {
    internal sealed class WindowLayoutController {
        private const double MinimumEditorPaneRatio = 0.2;
        private const double MaximumEditorPaneRatio = 0.8;
        private readonly ColumnDefinition editorColumn;
        private readonly ColumnDefinition workspaceColumn;

        public WindowLayoutController(ColumnDefinition editorColumn, ColumnDefinition workspaceColumn) {
            this.editorColumn = editorColumn;
            this.workspaceColumn = workspaceColumn;
        }

        public double GetEditorPaneRatio(PreviewerSettings settings) {
            var panesWidth = this.editorColumn.ActualWidth + this.workspaceColumn.ActualWidth;
            return panesWidth <= 0.0 ? settings.EditorPaneRatio : Math.Clamp(this.editorColumn.ActualWidth / panesWidth, MinimumEditorPaneRatio, MaximumEditorPaneRatio);
        }

        public void ApplyEditorPreviewSplit(PreviewerSettings settings) {
            var ratio = Math.Clamp(settings.EditorPaneRatio, MinimumEditorPaneRatio, MaximumEditorPaneRatio);
            settings.EditorPaneRatio = ratio;
            this.editorColumn.Width = new GridLength(ratio, GridUnitType.Star);
            this.workspaceColumn.Width = new GridLength(1.0 - ratio, GridUnitType.Star);
        }
    }
}