using System.Windows;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Controls;

using ICSharpCode.AvalonEdit;
using ICSharpCode.AvalonEdit.Editing;
using ICSharpCode.AvalonEdit.Document;
using ICSharpCode.AvalonEdit.CodeCompletion;

using PreviewRenderer = AndroidAppPreviewer.PreviewBrushes;

namespace AndroidAppPreviewer {
    internal sealed class XamlCompletionController {
        private readonly TextEditor editor;
        private CompletionWindow? completionWindow;

        public XamlCompletionController(TextEditor editor) {
            this.editor = editor;
            this.editor.TextArea.TextEntered += this.TextAreaTextEntered;
        }

        public bool HandlePreviewKeyDown(KeyEventArgs eventArgs) {
            if (eventArgs.Key == Key.Enter && this.completionWindow is not null) {
                this.completionWindow.CompletionList.RequestInsertion(eventArgs);
                eventArgs.Handled = true;
                return true;
            }

            if (eventArgs.Key != Key.Space
                || (Keyboard.Modifiers & (ModifierKeys.Control | ModifierKeys.Shift)) == ModifierKeys.None) {
                return false;
            }

            if (!this.TryShowExplicitCompletion()) {
                return false;
            }

            eventArgs.Handled = true;
            return true;
        }

        private void TextAreaTextEntered(object? sender, TextCompositionEventArgs eventArgs) {
            if (eventArgs.Text == "<") {
                this.ShowCompletion(XamlCompletionController.GetElementNames().Select(
                    name => new XamlCompletionData(name, "Элемент XAML")), this.editor.TextArea.Caret.Offset);
                return;
            }

            if (eventArgs.Text == " " || eventArgs.Text == "\t") {
                this.completionWindow?.Close();
                return;
            }

            if (eventArgs.Text == ">") {
                this.InsertClosingTag();
            }
        }

        private void ShowCompletion(IEnumerable<XamlCompletionData> completionData, int completionStartOffset) {
            this.completionWindow?.Close();
            var window = new CompletionWindow(this.editor.TextArea) {
                Background = PreviewRenderer.ParseBrush("#252525"),
                BorderBrush = PreviewRenderer.ParseBrush("#4A4A4A"),
                Foreground = PreviewRenderer.ParseBrush("#E6E6E6"),
                MaxHeight = 520,
                MinWidth = 360,
                ResizeMode = ResizeMode.NoResize,
                SizeToContent = SizeToContent.Height,
                Width = 360,
            };
            window.StartOffset = completionStartOffset;
            window.EndOffset = this.editor.TextArea.Caret.Offset;
            window.Resources[SystemColors.ActiveBorderBrushKey] = PreviewRenderer.ParseBrush("#4A4A4A");
            window.Resources[SystemColors.InactiveBorderBrushKey] = PreviewRenderer.ParseBrush("#4A4A4A");
            window.Resources[SystemColors.ControlBrushKey] = PreviewRenderer.ParseBrush("#252525");
            window.Resources[SystemColors.ControlTextBrushKey] = PreviewRenderer.ParseBrush("#E6E6E6");
            window.Resources[SystemColors.HighlightBrushKey] = PreviewRenderer.ParseBrush("#5A4D26");
            window.Resources[SystemColors.HighlightTextBrushKey] = PreviewRenderer.ParseBrush("#FFFFFF");
            window.Resources[SystemColors.WindowBrushKey] = PreviewRenderer.ParseBrush("#252525");
            window.Resources[SystemColors.WindowTextBrushKey] = PreviewRenderer.ParseBrush("#E6E6E6");
            window.CompletionList.MinHeight = 0;
            window.CompletionList.Template = this.CreateCompletionListTemplate();
            foreach (var item in completionData) {
                window.CompletionList.CompletionData.Add(item);
            }
            var typedPrefix = this.editor.Document.GetText(
                completionStartOffset,
                this.editor.TextArea.Caret.Offset - completionStartOffset);
            window.CompletionList.SelectItem(typedPrefix);
            window.Closed += (_, _) => {
                if (ReferenceEquals(this.completionWindow, window)) {
                    this.completionWindow = null;
                }
            };
            window.Loaded += (_, _) => this.ApplyCompletionTheme(window);
            this.completionWindow = window;
            window.Show();
        }

        private void ApplyCompletionTheme(CompletionWindow window) {
            var listBox = window.CompletionList.ListBox;
            listBox.Background = PreviewRenderer.ParseBrush("#252525");
            listBox.BorderBrush = PreviewRenderer.ParseBrush("#626262");
            listBox.BorderThickness = new Thickness(0);
            listBox.Foreground = PreviewRenderer.ParseBrush("#E6E6E6");
            listBox.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            var itemStyle = new Style(typeof(ListBoxItem));
            itemStyle.Setters.Add(new Setter(Control.BackgroundProperty, Brushes.Transparent));
            itemStyle.Setters.Add(new Setter(Control.ForegroundProperty, PreviewRenderer.ParseBrush("#E6E6E6")));
            itemStyle.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(7, 4, 7, 4)));
            var selectedTrigger = new Trigger {
                Property = ListBoxItem.IsSelectedProperty,
                Value = true,
            };
            selectedTrigger.Setters.Add(new Setter(Control.BackgroundProperty, PreviewRenderer.ParseBrush("#5A4D26")));
            selectedTrigger.Setters.Add(new Setter(Control.ForegroundProperty, PreviewRenderer.ParseBrush("#FFF3BF")));
            itemStyle.Triggers.Add(selectedTrigger);
            listBox.ItemContainerStyle = itemStyle;
        }

        private ControlTemplate CreateCompletionListTemplate() {
            var template = new ControlTemplate(typeof(CompletionList));
            var border = new FrameworkElementFactory(typeof(Border));
            border.SetValue(Border.BackgroundProperty, PreviewRenderer.ParseBrush("#252525"));
            border.SetValue(Border.BorderBrushProperty, PreviewRenderer.ParseBrush("#4A4A4A"));
            border.SetValue(Border.BorderThicknessProperty, new Thickness(1));
            var listBox = new FrameworkElementFactory(typeof(CompletionListBox));
            listBox.Name = "PART_ListBox";
            listBox.SetValue(Control.BackgroundProperty, PreviewRenderer.ParseBrush("#252525"));
            listBox.SetValue(Control.BorderThicknessProperty, new Thickness(0));
            listBox.SetValue(Control.TemplateProperty, this.CreateCompletionListBoxTemplate());
            var itemTemplate = new DataTemplate(typeof(ICompletionData));
            var content = new FrameworkElementFactory(typeof(ContentPresenter));
            content.SetBinding(ContentPresenter.ContentProperty, new Binding("Content"));
            itemTemplate.VisualTree = content;
            listBox.SetValue(ItemsControl.ItemTemplateProperty, itemTemplate);
            border.AppendChild(listBox);
            template.VisualTree = border;
            return template;
        }

        private ControlTemplate CreateCompletionListBoxTemplate() {
            var template = new ControlTemplate(typeof(CompletionListBox));
            var border = new FrameworkElementFactory(typeof(Border));
            border.SetValue(Border.BackgroundProperty, PreviewRenderer.ParseBrush("#252525"));
            var itemsPresenter = new FrameworkElementFactory(typeof(ItemsPresenter));
            itemsPresenter.Name = "PART_ItemsPresenter";
            border.AppendChild(itemsPresenter);
            template.VisualTree = border;
            return template;
        }

        private void InsertClosingTag() {
            var caretOffset = this.editor.TextArea.Caret.Offset;
            var text = this.editor.Document.Text;
            var openingStart = text.LastIndexOf('<', Math.Max(0, caretOffset - 1));
            if (openingStart < 0) {
                return;
            }

            var openingTag = text[openingStart..caretOffset];
            if (openingTag.StartsWith("</", StringComparison.Ordinal)
                || openingTag.EndsWith("/>", StringComparison.Ordinal)
                || openingTag[..^1].Contains('>')
                || !this.TryGetElementName(openingTag, out var elementName)) {
                return;
            }

            var closingTag = $"</{elementName}>";
            if (text.AsSpan(caretOffset).TrimStart().StartsWith(closingTag, StringComparison.Ordinal)) {
                return;
            }

            var line = this.editor.Document.GetLineByOffset(caretOffset);
            var lineText = this.editor.Document.GetText(line.Offset, line.Length);
            var indentation = new string(lineText.TakeWhile(character => character is ' ' or '\t').ToArray());
            var contentIndentation = indentation + new string(' ', this.editor.Options.IndentationSize);
            var insertion = Environment.NewLine + contentIndentation
                + Environment.NewLine + indentation + closingTag;
            this.editor.Document.Insert(caretOffset, insertion);
            this.editor.TextArea.Caret.Offset = caretOffset + Environment.NewLine.Length + contentIndentation.Length;
        }

        private bool TryShowExplicitCompletion() {
            var caretOffset = this.editor.TextArea.Caret.Offset;
            var text = this.editor.Document.Text;
            var openingStart = text.LastIndexOf('<', Math.Max(0, caretOffset - 1));
            if (openingStart < 0) {
                return false;
            }

            var openingTag = text[openingStart..caretOffset];
            if (openingTag.Contains('>') || openingTag.StartsWith("</", StringComparison.Ordinal)) {
                return false;
            }

            var tagContent = openingTag[1..];
            var attributeSeparator = tagContent.LastIndexOfAny([' ', '\t', '\r', '\n']);
            if (attributeSeparator < 0) {
                this.ShowCompletion(XamlCompletionController.GetElementNames().Select(
                    name => new XamlCompletionData(name, "Элемент XAML")), openingStart + 1);
                return true;
            }

            if (!this.TryGetElementName(openingTag, out var elementName)) {
                return false;
            }

            var completionStartOffset = openingStart + attributeSeparator + 2;
            this.ShowCompletion(XamlCompletionController.GetAttributes(elementName).Select(
                name => new XamlCompletionData($"{name}=\"\"", "Атрибут XAML", name.Length + 2)), completionStartOffset);
            return true;
        }

        private bool TryGetElementName(string tag, out string elementName) {
            var span = tag.AsSpan().TrimStart('<').Trim();
            var end = span.IndexOfAny(' ', '/', '>');
            elementName = end < 0 ? span.ToString() : span[..end].ToString();
            return elementName.Length > 0 && !elementName.StartsWith('/');
        }

        private static IEnumerable<string> GetAttributes(string elementName) {
            var count = AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.XamlCompletion.xp_xaml_supported_attribute_count(elementName);
            if (count > 0) {
                return Enumerable.Range(0, count)
                    .Select(index => AndroidAppPreviewerPluginSDK.NativeRuntime.XamlCompletion.GetSupportedAttributeName(elementName, index))
                    .Where(name => !string.IsNullOrEmpty(name));
            }
            return [];
        }

        private static IEnumerable<string> GetElementNames() {
            return Enumerable.Range(0, AndroidAppPreviewerPluginSDK.NativeRuntime.Methods.XamlCompletion.xp_xaml_supported_element_count())
                .Select(AndroidAppPreviewerPluginSDK.NativeRuntime.XamlCompletion.GetSupportedElementName)
                .Where(name => !string.IsNullOrEmpty(name));
        }
    }

    internal sealed class XamlCompletionData : ICompletionData {
        private readonly int? caretOffset;
        private readonly string description;

        public XamlCompletionData(string text, string description, int? caretOffset = null) {
            this.Text = text;
            this.description = description;
            this.caretOffset = caretOffset;
        }

        public ImageSource? Image => null;
        public string Text { get; }
        public object Content => this.CreateContent();
        public object Description => null!;
        public double Priority => 0.0;

        public void Complete(TextArea textArea, ISegment completionSegment, EventArgs insertionRequestEventArgs) {
            textArea.Document.Replace(completionSegment, this.Text);
            textArea.Caret.Offset = completionSegment.Offset + (this.caretOffset ?? this.Text.Length);
        }

        private Grid CreateContent() {
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.0, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var icon = new TextBlock {
                Foreground = PreviewRenderer.ParseBrush("#D5BD7D"),
                Text = "◇",
                Width = 18,
            };
            var name = new TextBlock {
                Text = this.Text,
            };
            var detail = new TextBlock {
                Foreground = PreviewRenderer.ParseBrush("#A8A8A8"),
                Margin = new Thickness(18, 0, 0, 0),
                Text = this.description,
            };
            Grid.SetColumn(name, 1);
            Grid.SetColumn(detail, 2);
            grid.Children.Add(icon);
            grid.Children.Add(name);
            grid.Children.Add(detail);
            return grid;
        }
    }
}