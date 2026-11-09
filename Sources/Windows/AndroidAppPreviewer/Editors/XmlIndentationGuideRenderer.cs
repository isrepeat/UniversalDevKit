using System.Windows;
using System.Windows.Media;
using System.Windows.Controls;

using ICSharpCode.AvalonEdit;
using ICSharpCode.AvalonEdit.Document;
using ICSharpCode.AvalonEdit.Rendering;

namespace AndroidAppPreviewer {
    internal sealed class XmlIndentationGuideRenderer : IBackgroundRenderer {
        private const double BaseFontSize = 14.0;
        private const double DashLength = 10.0;
        private const double DashGap = 10.0;
        private const int IndentationSize = 4;
        private readonly Brush brush;

        public KnownLayer Layer => KnownLayer.Background;

        public XmlIndentationGuideRenderer() {
            this.brush = new SolidColorBrush(Color.FromArgb(105, 150, 150, 150));
            this.brush.Freeze();
        }

        public void Draw(TextView textView, DrawingContext drawingContext) {
            if (!textView.VisualLinesValid || textView.Document is null) {
                return;
            }

            var dashScale = TextBlock.GetFontSize(textView) / XmlIndentationGuideRenderer.BaseFontSize;
            var pen = new Pen(this.brush, 1.0) {
                DashStyle = new DashStyle([
                    XmlIndentationGuideRenderer.DashLength * dashScale,
                    XmlIndentationGuideRenderer.DashGap * dashScale,
                ], 0.0),
            };
            foreach (var visualLine in textView.VisualLines) {
                var line = visualLine.FirstDocumentLine;
                var indentationLength = this.GetIndentationLength(textView.Document, line);
                for (var guideOffset = XmlIndentationGuideRenderer.IndentationSize;
                     guideOffset <= indentationLength;
                     guideOffset += XmlIndentationGuideRenderer.IndentationSize) {
                    var position = textView.GetVisualPosition(
                        new TextViewPosition(new TextLocation(
                            line.LineNumber,
                            guideOffset - XmlIndentationGuideRenderer.IndentationSize + 1)),
                        VisualYPosition.LineTop);
                    var visualTop = visualLine.VisualTop - textView.VerticalOffset;
                    drawingContext.DrawLine(
                        pen,
                        new Point(position.X, visualTop),
                        new Point(position.X, visualTop + visualLine.Height));
                }
            }
        }

        private int GetIndentationLength(TextDocument document, DocumentLine line) {
            var length = 0;
            while (length < line.Length) {
                var character = document.GetCharAt(line.Offset + length);
                if (character == ' ') {
                    ++length;
                    continue;
                }
                if (character == '\t') {
                    length += XmlIndentationGuideRenderer.IndentationSize;
                    continue;
                }
                break;
            }
            return length;
        }
    }
}