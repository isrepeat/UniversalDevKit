using System.Windows;
using System.Windows.Controls;

namespace AndroidAppPreviewer {
    public sealed class HorizontalSplitter : GridSplitter {
        // Колонка разделителя имеет Width="Auto", поэтому её ширину задаёт только этот thumb.
        public static readonly DependencyProperty ThumbWidthProperty = DependencyProperty.Register(
            nameof(ThumbWidth),
            typeof(double),
            typeof(HorizontalSplitter),
            new PropertyMetadata(12.0, ThumbWidthChanged));

        public HorizontalSplitter() {
            this.ResizeDirection = GridResizeDirection.Columns;
            this.ResizeBehavior = GridResizeBehavior.PreviousAndNext;
            this.HorizontalAlignment = HorizontalAlignment.Stretch;
            this.VerticalAlignment = VerticalAlignment.Stretch;
            this.Cursor = System.Windows.Input.Cursors.SizeWE;
            this.Width = this.ThumbWidth;
        }

        public double ThumbWidth {
            get => (double)this.GetValue(ThumbWidthProperty);
            set => this.SetValue(ThumbWidthProperty, value);
        }

        private static void ThumbWidthChanged(DependencyObject dependencyObject, DependencyPropertyChangedEventArgs eventArgs) {
            if (dependencyObject is HorizontalSplitter horizontalSplitter
                && eventArgs.NewValue is double thumbWidth
                && double.IsFinite(thumbWidth)
                && thumbWidth > 0.0) {
                horizontalSplitter.Width = thumbWidth;
            }
        }
    }
}