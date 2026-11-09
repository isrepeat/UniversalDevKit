using System.Xml.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Controls;

namespace AndroidAppPreviewer {
    internal sealed class SvgIconControl : Viewbox {
        public static readonly DependencyProperty SourceProperty = DependencyProperty.Register(
            nameof(Source),
            typeof(string),
            typeof(SvgIconControl),
            new PropertyMetadata(string.Empty, SvgIconControl.OnSourceChanged));

        public static readonly DependencyProperty StrokeProperty = DependencyProperty.Register(
            nameof(Stroke),
            typeof(Brush),
            typeof(SvgIconControl),
            new PropertyMetadata(Brushes.Transparent, SvgIconControl.OnAppearanceChanged));

        public static readonly DependencyProperty StrokeThicknessProperty = DependencyProperty.Register(
            nameof(StrokeThickness),
            typeof(double),
            typeof(SvgIconControl),
            new PropertyMetadata(1.0, SvgIconControl.OnAppearanceChanged));

        private readonly Canvas canvas;
        private readonly Path path;

        public SvgIconControl() {
            this.Stretch = Stretch.Uniform;
            this.StretchDirection = StretchDirection.Both;
            this.UseLayoutRounding = true;
            this.path = new Path {
                StrokeEndLineCap = PenLineCap.Round,
                StrokeLineJoin = PenLineJoin.Round,
                StrokeStartLineCap = PenLineCap.Round,
            };
            this.canvas = new Canvas {
                Height = 24,
                Width = 24,
            };
            this.canvas.Children.Add(this.path);
            this.Child = this.canvas;
        }

        public string Source {
            get => (string)this.GetValue(SvgIconControl.SourceProperty);
            set => this.SetValue(SvgIconControl.SourceProperty, value);
        }

        public Brush Stroke {
            get => (Brush)this.GetValue(SvgIconControl.StrokeProperty);
            set => this.SetValue(SvgIconControl.StrokeProperty, value);
        }

        public double StrokeThickness {
            get => (double)this.GetValue(SvgIconControl.StrokeThicknessProperty);
            set => this.SetValue(SvgIconControl.StrokeThicknessProperty, value);
        }

        private static void OnAppearanceChanged(DependencyObject dependencyObject, DependencyPropertyChangedEventArgs eventArgs) {
            ((SvgIconControl)dependencyObject).ApplyAppearance();
        }

        private static void OnSourceChanged(DependencyObject dependencyObject, DependencyPropertyChangedEventArgs eventArgs) {
            ((SvgIconControl)dependencyObject).LoadGeometry();
        }

        private void ApplyAppearance() {
            this.path.Stroke = this.Stroke;
            this.path.StrokeThickness = this.StrokeThickness;
        }

        private void LoadGeometry() {
            if (string.IsNullOrWhiteSpace(this.Source)) {
                this.path.Data = null;
                return;
            }

            var resource = Application.GetResourceStream(new Uri(this.Source, UriKind.Relative));
            if (resource is null) {
                this.path.Data = null;
                return;
            }

            using (resource.Stream) {
                var document = XDocument.Load(resource.Stream);
                var pathData = document
                    .Descendants()
                    .FirstOrDefault(element => element.Name.LocalName == "path")
                    ?.Attribute("d")
                    ?.Value;
                this.path.Data = string.IsNullOrWhiteSpace(pathData) ? null : Geometry.Parse(pathData);
            }
        }
    }
}