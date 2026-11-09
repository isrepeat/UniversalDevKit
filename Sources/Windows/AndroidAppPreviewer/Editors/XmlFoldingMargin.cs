using System.Windows;
using System.Windows.Input;
using System.Windows.Media;

using ICSharpCode.AvalonEdit.Editing;
using ICSharpCode.AvalonEdit.Folding;
using ICSharpCode.AvalonEdit.Document;
using ICSharpCode.AvalonEdit.Rendering;

namespace AndroidAppPreviewer {
    internal sealed class XmlFoldingMargin : AbstractMargin {
        private readonly FoldingManager foldingManager;
        private readonly List<Marker> markers = [];
        private double markerSize = 18.0;
        private FoldingSection? hoveredFolding;

        public Brush MarkerBackgroundBrush { get; set; } = Brushes.Transparent;
        public Brush MarkerBrush { get; set; } = Brushes.Gray;
        public Brush SelectedMarkerBackgroundBrush { get; set; } = Brushes.Transparent;
        public Brush SelectedMarkerBrush { get; set; } = Brushes.White;

        public XmlFoldingMargin(FoldingManager foldingManager) {
            this.foldingManager = foldingManager;
        }

        public void SetMarkerSize(double value) {
            if (this.markerSize == value) {
                return;
            }
            this.markerSize = value;
            this.InvalidateMeasure();
            this.InvalidateVisual();
        }

        protected override Size MeasureOverride(Size availableSize) {
            return new Size(this.markerSize + 6.0, 0.0);
        }

        protected override void OnTextViewChanged(TextView oldTextView, TextView newTextView) {
            if (oldTextView is not null) {
                oldTextView.VisualLinesChanged -= this.VisualLinesChanged;
                oldTextView.ScrollOffsetChanged -= this.ScrollOffsetChanged;
            }
            base.OnTextViewChanged(oldTextView, newTextView);
            if (newTextView is not null) {
                newTextView.VisualLinesChanged += this.VisualLinesChanged;
                newTextView.ScrollOffsetChanged += this.ScrollOffsetChanged;
            }
        }

        protected override void OnRender(DrawingContext drawingContext) {
            this.markers.Clear();
            if (this.TextView is null || !this.TextView.VisualLinesValid) {
                return;
            }

            this.DrawFoldingLines(drawingContext);
            foreach (var visualLine in this.TextView.VisualLines) {
                var folding = this.foldingManager.GetNextFolding(visualLine.FirstDocumentLine.Offset);
                if (folding is null || folding.StartOffset > visualLine.LastDocumentLine.EndOffset) {
                    continue;
                }

                var visualColumn = visualLine.GetVisualColumn(
                    folding.StartOffset - visualLine.FirstDocumentLine.Offset);
                var visualPosition = visualLine.GetVisualPosition(visualColumn, VisualYPosition.TextMiddle);
                var bounds = new Rect(
                    (this.RenderSize.Width - this.markerSize) / 2.0,
                    visualPosition.Y - this.TextView.VerticalOffset - this.markerSize / 2.0,
                    this.markerSize,
                    this.markerSize);
                this.markers.Add(new Marker(folding, bounds));
                var isSelected = ReferenceEquals(folding, this.hoveredFolding);
                this.DrawMarker(drawingContext, bounds, folding.IsFolded, isSelected);
            }
        }

        protected override void OnMouseDown(MouseButtonEventArgs eventArgs) {
            base.OnMouseDown(eventArgs);
            if (eventArgs.ChangedButton != MouseButton.Left) {
                return;
            }
            var position = eventArgs.GetPosition(this);
            var marker = this.markers.FirstOrDefault(candidate => candidate.Bounds.Contains(position));
            if (marker is null) {
                return;
            }
            marker.Folding.IsFolded = !marker.Folding.IsFolded;
            this.InvalidateVisual();
            eventArgs.Handled = true;
        }

        protected override void OnMouseMove(MouseEventArgs eventArgs) {
            base.OnMouseMove(eventArgs);
            var hoveredMarker = this.markers.FirstOrDefault(marker => marker.Bounds.Contains(eventArgs.GetPosition(this)));
            var folding = hoveredMarker?.Folding;
            if (ReferenceEquals(this.hoveredFolding, folding)) {
                return;
            }
            this.hoveredFolding = folding;
            this.InvalidateVisual();
        }

        protected override void OnMouseLeave(MouseEventArgs eventArgs) {
            base.OnMouseLeave(eventArgs);
            if (this.hoveredFolding is null) {
                return;
            }
            this.hoveredFolding = null;
            this.InvalidateVisual();
        }

        private void VisualLinesChanged(object? sender, EventArgs eventArgs) {
            this.InvalidateVisual();
        }

        private void ScrollOffsetChanged(object? sender, EventArgs eventArgs) {
            this.InvalidateVisual();
        }

        private void DrawMarker(
            DrawingContext drawingContext,
            Rect bounds,
            bool isFolded,
            bool isSelected) {
            var background = isSelected ? this.SelectedMarkerBackgroundBrush : this.MarkerBackgroundBrush;
            var brush = isSelected ? this.SelectedMarkerBrush : this.MarkerBrush;
            var pen = new Pen(brush, 1.0);
            drawingContext.DrawRectangle(background, pen, bounds);
            var inset = Math.Max(3.0, this.markerSize / 4.0);
            var middleX = bounds.Left + bounds.Width / 2.0;
            var middleY = bounds.Top + bounds.Height / 2.0;
            drawingContext.DrawLine(pen, new Point(bounds.Left + inset, middleY), new Point(bounds.Right - inset, middleY));
            if (isFolded) {
                drawingContext.DrawLine(pen, new Point(middleX, bounds.Top + inset), new Point(middleX, bounds.Bottom - inset));
            }
        }

        private void DrawFoldingLines(DrawingContext drawingContext) {
            if (this.TextView is null || this.TextView.VisualLines.Count == 0) {
                return;
            }

            var firstOffset = this.TextView.VisualLines[0].FirstDocumentLine.Offset;
            var lastOffset = this.TextView.VisualLines[^1].LastDocumentLine.EndOffset;
            var x = this.RenderSize.Width / 2.0;
            foreach (var folding in this.foldingManager.AllFoldings) {
                if (folding.IsFolded || folding.EndOffset < firstOffset || folding.StartOffset > lastOffset) {
                    continue;
                }

                var start = folding.StartOffset < firstOffset
                    ? 0.0
                    : this.GetFoldingPosition(folding.StartOffset) + this.markerSize / 2.0;
                var end = folding.EndOffset > lastOffset
                    ? this.RenderSize.Height
                    : this.GetFoldingPosition(folding.EndOffset);
                var pen = new Pen(
                    ReferenceEquals(folding, this.hoveredFolding) ? this.SelectedMarkerBrush : this.MarkerBrush,
                    1.0);
                if (end > start) {
                    drawingContext.DrawLine(pen, new Point(x, start), new Point(x, end));
                }
                if (folding.EndOffset <= lastOffset) {
                    drawingContext.DrawLine(pen, new Point(x, end), new Point(this.RenderSize.Width, end));
                }
            }
        }

        private double GetFoldingPosition(int offset) {
            var line = this.TextView!.Document.GetLineByOffset(offset);
            var visualLine = this.TextView.GetVisualLine(line.LineNumber)!;
            var visualColumn = visualLine.GetVisualColumn(offset - visualLine.FirstDocumentLine.Offset);
            return visualLine.GetVisualPosition(visualColumn, VisualYPosition.TextMiddle).Y
                - this.TextView.VerticalOffset;
        }

        private sealed class Marker {
            public FoldingSection Folding { get; }
            public Rect Bounds { get; }

            public Marker(FoldingSection folding, Rect bounds) {
                this.Folding = folding;
                this.Bounds = bounds;
            }
        }
    }
}