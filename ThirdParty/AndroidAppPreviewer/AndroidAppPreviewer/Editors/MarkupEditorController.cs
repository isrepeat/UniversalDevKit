using System.Windows;
using System.Windows.Input;
using System.Windows.Media;

using ICSharpCode.AvalonEdit;
using ICSharpCode.AvalonEdit.Folding;

namespace AndroidAppPreviewer {
    internal sealed class MarkupEditorController {
        private const double FoldingMarkerSizeMultiplier = 1.25;
        private readonly TextEditor editor;
        private readonly FoldingManager foldingManager;
        private readonly XmlFoldingMargin foldingMargin;
        private readonly XmlFoldingStrategy foldingStrategy = new();
        private readonly XmlIndentationGuideRenderer indentationGuideRenderer = new();
        private int[] foldedOffsets = [];
        private bool isCommentShortcutPending;
        private bool isUpdating;

        public string Text => this.editor.Text;
        public bool HasFoldedSections => this.foldedOffsets.Length != 0;

        public event EventHandler? FoldingStateChanged;

        public MarkupEditorController(TextEditor editor) {
            this.editor = editor;
            this.editor.Options.ConvertTabsToSpaces = false;
            this.editor.Options.IndentationSize = 4;
            this.editor.Options.EnableTextDragDrop = true;
            this.foldingManager = FoldingManager.Install(this.editor.TextArea);
            var defaultFoldingMargin = this.editor.TextArea.LeftMargins.OfType<FoldingMargin>().First();
            this.editor.TextArea.LeftMargins.Remove(defaultFoldingMargin);
            this.foldingMargin = new XmlFoldingMargin(this.foldingManager);
            this.editor.TextArea.LeftMargins.Add(this.foldingMargin);
            this.ConfigureFoldingMargin();
            this.editor.TextArea.TextView.BackgroundRenderers.Add(this.indentationGuideRenderer);
            this.editor.Document.Changed += this.DocumentChanged;
            this.editor.TextArea.PreviewMouseUp += this.TextAreaPreviewMouseUp;
            this.UpdateFoldings();
        }

        public bool HandleTextChanged() {
            return !this.isUpdating;
        }

        public void Dispose() {
            this.editor.Document.Changed -= this.DocumentChanged;
            this.editor.TextArea.PreviewMouseUp -= this.TextAreaPreviewMouseUp;
            this.editor.TextArea.TextView.BackgroundRenderers.Remove(this.indentationGuideRenderer);
            this.editor.TextArea.LeftMargins.Remove(this.foldingMargin);
            FoldingManager.Uninstall(this.foldingManager);
        }

        public void HandlePreviewKeyDown(KeyEventArgs eventArgs) {
            var key = eventArgs.Key == Key.System ? eventArgs.SystemKey : eventArgs.Key;
            if (this.isCommentShortcutPending) {
                this.isCommentShortcutPending = false;
                if (Keyboard.Modifiers == ModifierKeys.Control && key == Key.C) {
                    this.CommentSelection();
                    eventArgs.Handled = true;
                    return;
                }
                if (Keyboard.Modifiers == ModifierKeys.Control && key == Key.U) {
                    this.UncommentSelection();
                    eventArgs.Handled = true;
                    return;
                }
            }

            if (Keyboard.Modifiers == ModifierKeys.Control && key == Key.K) {
                this.isCommentShortcutPending = true;
                eventArgs.Handled = true;
            }
            else if (this.TryCollapseSelectionForNavigation(key)) {
                eventArgs.Handled = true;
            }
            else if (this.TryPasteXaml(key)) {
                eventArgs.Handled = true;
            }
            else if (Keyboard.Modifiers == ModifierKeys.Control && key == Key.W) {
                this.SelectWord();
                eventArgs.Handled = true;
            }
            else if (Keyboard.Modifiers == ModifierKeys.Control && key == Key.D) {
                this.DuplicateLine();
                eventArgs.Handled = true;
            }
            else if (Keyboard.Modifiers == ModifierKeys.Alt && key is Key.Up or Key.Down) {
                this.MoveLine(key == Key.Up ? -1 : 1);
                eventArgs.Handled = true;
            }
            else if (key == Key.Enter) {
                this.InsertNewLine();
                eventArgs.Handled = true;
            }
        }

        public void SetText(string text) {
            this.isUpdating = true;
            try {
                this.editor.Text = text;
                var offset = Math.Min(text.Length, this.editor.Document.TextLength);
                this.editor.CaretOffset = offset;
                this.editor.SelectionStart = offset;
                this.editor.SelectionLength = 0;
                this.editor.Document.UndoStack.ClearAll();
            }
            finally {
                this.isUpdating = false;
            }
        }

        public void SetFoldedOffsets(IEnumerable<int> offsets) {
            var collapsedOffsets = offsets.ToHashSet();
            foreach (var folding in this.foldingManager.AllFoldings) {
                folding.IsFolded = collapsedOffsets.Contains(folding.StartOffset);
            }
            this.UpdateFoldingState();
        }

        public void ExpandAll() {
            foreach (var folding in this.foldingManager.AllFoldings) {
                folding.IsFolded = false;
            }
            this.UpdateFoldingState();
        }

        public int[] GetFoldedOffsets() {
            return this.foldedOffsets;
        }

        public void UpdateFoldingMarkerSize() {
            this.foldingMargin.SetMarkerSize(this.editor.FontSize * MarkupEditorController.FoldingMarkerSizeMultiplier);
        }

        private void InsertNewLine() {
            var indentation = this.GetNewLineIndentation(this.editor.CaretOffset);
            var selectionStart = this.editor.SelectionStart;
            this.editor.Document.Replace(
                selectionStart,
                this.editor.SelectionLength,
                Environment.NewLine + indentation);
            this.editor.CaretOffset = selectionStart + Environment.NewLine.Length + indentation.Length;
            this.editor.SelectionLength = 0;
        }

        private void UncommentSelection() {
            if (this.TryGetTouchedComment(out var commentStart, out var commentEnd)) {
                this.Uncomment(commentStart, commentEnd);
            }
        }

        private bool TryGetTouchedComment(out int commentStart, out int commentEnd) {
            var text = this.editor.Text;
            var selectionStart = this.editor.SelectionStart;
            var selectionEnd = selectionStart + this.editor.SelectionLength;
            var searchStart = 0;
            while (searchStart < text.Length) {
                var start = text.IndexOf("<!--", searchStart, StringComparison.Ordinal);
                if (start < 0) {
                    break;
                }

                var endStart = text.IndexOf("-->", start + 4, StringComparison.Ordinal);
                if (endStart < 0) {
                    break;
                }

                var end = endStart + 3;
                var touchesComment = this.editor.SelectionLength == 0
                    ? selectionStart >= start && selectionStart <= end
                    : selectionStart < end && selectionEnd > start;
                if (touchesComment) {
                    commentStart = start;
                    commentEnd = end;
                    return true;
                }

                searchStart = end;
            }

            commentStart = 0;
            commentEnd = 0;
            return false;
        }

        private void Uncomment(int commentStart, int commentEnd) {
            var commentText = this.editor.Document.GetText(commentStart, commentEnd - commentStart);
            var uncommentedText = commentText[4..^3];
            var caretOffset = this.editor.CaretOffset;
            var hasSelection = this.editor.SelectionLength != 0;
            this.editor.Document.Replace(commentStart, commentText.Length, uncommentedText);
            if (hasSelection) {
                this.editor.Select(commentStart, uncommentedText.Length);
                return;
            }

            this.editor.CaretOffset = Math.Clamp(caretOffset - 4, commentStart, commentStart + uncommentedText.Length);
            this.editor.SelectionLength = 0;
        }

        private void CommentSelection() {
            var selectionStart = this.editor.SelectionStart;
            var selectedText = this.editor.SelectedText;
            if (selectedText.Length == 0) {
                if (this.TryGetContainingOpeningTag(selectionStart, out var tagStart, out var tagEnd)) {
                    var tagText = this.editor.Document.GetText(tagStart, tagEnd - tagStart);
                    this.editor.Document.Replace(tagStart, tagText.Length, "<!--" + tagText + "-->");
                    this.editor.CaretOffset = selectionStart + 4;
                    this.editor.SelectionLength = 0;
                    return;
                }

                const string emptyComment = "<!-- -->";
                this.editor.Document.Insert(selectionStart, emptyComment);
                this.editor.CaretOffset = selectionStart + 5;
                this.editor.SelectionLength = 0;
                return;
            }

            this.editor.Document.Replace(selectionStart, selectedText.Length, "<!--" + selectedText + "-->");
            this.editor.Select(selectionStart + 4, selectedText.Length);
        }

        private bool TryGetContainingOpeningTag(int caretOffset, out int tagStart, out int tagEnd) {
            var text = this.editor.Text;
            tagStart = text.LastIndexOf('<', Math.Max(0, caretOffset - 1));
            if (tagStart < 0
                || tagStart + 1 >= text.Length
                || text[tagStart + 1] is '/' or '!' or '?') {
                tagEnd = 0;
                return false;
            }

            var quote = '\0';
            for (var offset = tagStart + 1; offset < text.Length; ++offset) {
                var character = text[offset];
                if (quote != '\0') {
                    if (character == quote) {
                        quote = '\0';
                    }
                    continue;
                }

                if (character is '\'' or '"') {
                    quote = character;
                    continue;
                }
                if (character != '>') {
                    continue;
                }

                tagEnd = offset + 1;
                return caretOffset > tagStart && caretOffset < tagEnd;
            }

            tagEnd = 0;
            return false;
        }

        private bool TryPasteXaml(Key key) {
            const string newline = "\n";
            if ((key != Key.V || Keyboard.Modifiers != ModifierKeys.Control)
                && (key != Key.Insert || Keyboard.Modifiers != ModifierKeys.Shift)
                || !Clipboard.ContainsText()) {
                return false;
            }
            var text = Clipboard.GetText().Replace("\r\n", newline).Replace('\r', '\n').TrimEnd('\n');
            if (!text.Contains(newline, StringComparison.Ordinal) || !text.Contains('<')) {
                return false;
            }

            var lines = text.Split(newline);
            var commonIndentation = lines
                .Where(line => !string.IsNullOrWhiteSpace(line))
                .Select(MarkupEditorController.LeadingWhitespaceLength)
                .DefaultIfEmpty(0)
                .Min();
            var indentation = this.GetContentIndentation(this.editor.CaretOffset);
            var normalizedLines = lines.Select(line => line.Length >= commonIndentation
                ? line[commonIndentation..]
                : line);
            var insertedText = string.Join(Environment.NewLine + indentation, normalizedLines);
            var selectionStart = this.editor.SelectionStart;
            this.editor.Document.Replace(selectionStart, this.editor.SelectionLength, insertedText);
            this.editor.CaretOffset = selectionStart + insertedText.Length;
            this.editor.SelectionLength = 0;
            return true;
        }

        private void DocumentChanged(
            object? sender,
            ICSharpCode.AvalonEdit.Document.DocumentChangeEventArgs eventArgs) {
            this.UpdateFoldings();
        }

        private void TextAreaPreviewMouseUp(object sender, MouseButtonEventArgs eventArgs) {
            this.editor.TextArea.Dispatcher.BeginInvoke(new Action(this.UpdateFoldingState));
        }

        private bool TryCollapseSelectionForNavigation(Key key) {
            if (key is not (Key.Left or Key.Right or Key.Up or Key.Down)) {
                return false;
            }
            if (this.editor.SelectionLength == 0 || Keyboard.Modifiers != ModifierKeys.None) {
                return false;
            }

            var anchorOffset = this.editor.Document.GetOffset(
                this.editor.TextArea.Selection.StartPosition.Location);
            this.editor.Select(anchorOffset, 0);
            return true;
        }

        private void ConfigureFoldingMargin() {
            this.foldingMargin.SetMarkerSize(this.editor.FontSize * MarkupEditorController.FoldingMarkerSizeMultiplier);
            this.foldingMargin.MarkerBackgroundBrush = MarkupEditorController.CreateBrush("#FF25282C");
            this.foldingMargin.MarkerBrush = MarkupEditorController.CreateBrush("#FF9FA7AE");
            this.foldingMargin.SelectedMarkerBackgroundBrush = MarkupEditorController.CreateBrush("#FF3A4046");
            this.foldingMargin.SelectedMarkerBrush = MarkupEditorController.CreateBrush("#FFF2F4F5");
        }

        private void UpdateFoldings() {
            this.foldingManager.UpdateFoldings(this.foldingStrategy.CreateNewFoldings(this.editor.Document), -1);
            this.UpdateFoldingState();
        }

        private void UpdateFoldingState() {
            var offsets = this.foldingManager.AllFoldings
                .Where(folding => folding.IsFolded)
                .Select(folding => folding.StartOffset)
                .Order()
                .ToArray();
            if (this.foldedOffsets.SequenceEqual(offsets)) {
                return;
            }
            this.foldedOffsets = offsets;
            this.FoldingStateChanged?.Invoke(this, EventArgs.Empty);
        }

        private void SelectWord() {
            var text = this.editor.Text;
            if (text.Length == 0) {
                return;
            }

            var position = Math.Min(this.editor.CaretOffset, text.Length - 1);
            if (!MarkupEditorController.IsWordCharacter(text[position])
                && position > 0
                && MarkupEditorController.IsWordCharacter(text[position - 1])) {
                --position;
            }
            if (!MarkupEditorController.IsWordCharacter(text[position])) {
                return;
            }

            var start = position;
            while (start > 0 && MarkupEditorController.IsWordCharacter(text[start - 1])) {
                --start;
            }
            var end = position + 1;
            while (end < text.Length && MarkupEditorController.IsWordCharacter(text[end])) {
                ++end;
            }
            this.editor.Select(start, end - start);
        }

        private void DuplicateLine() {
            var line = this.editor.Document.GetLineByOffset(this.editor.CaretOffset);
            var lineEnd = line.Offset + line.TotalLength;
            var lineText = this.editor.Document.GetText(line.Offset, line.TotalLength);
            if (!lineText.EndsWith("\n", StringComparison.Ordinal)) {
                lineText = Environment.NewLine + lineText;
            }
            this.editor.Document.Insert(lineEnd, lineText);
            this.editor.CaretOffset = lineEnd + lineText.Length;
            this.editor.SelectionLength = 0;
        }

        private void MoveLine(int lineDelta) {
            if (this.TryMoveSelectedLines(lineDelta)) {
                return;
            }

            var currentLine = this.editor.Document.GetLineByOffset(this.editor.CaretOffset);
            var targetLineNumber = currentLine.LineNumber + lineDelta;
            if (targetLineNumber < 1 || targetLineNumber > this.editor.Document.LineCount) {
                return;
            }

            var targetLine = this.editor.Document.GetLineByNumber(targetLineNumber);
            var regionStart = Math.Min(currentLine.Offset, targetLine.Offset);
            var regionEnd = Math.Max(
                currentLine.Offset + currentLine.TotalLength,
                targetLine.Offset + targetLine.TotalLength);
            var currentText = this.editor.Document.GetText(currentLine.Offset, currentLine.TotalLength);
            var targetText = this.editor.Document.GetText(targetLine.Offset, targetLine.TotalLength);
            var column = Math.Min(this.editor.CaretOffset - currentLine.Offset, currentLine.Length);
            this.editor.Document.Replace(
                regionStart,
                regionEnd - regionStart,
                lineDelta < 0 ? currentText + targetText : targetText + currentText);

            var newOffset = lineDelta < 0
                ? targetLine.Offset + column
                : currentLine.Offset + targetText.Length + column;
            this.editor.CaretOffset = newOffset;
            this.editor.SelectionLength = 0;
        }

        private bool TryMoveSelectedLines(int lineDelta) {
            if (this.editor.SelectionLength == 0) {
                return false;
            }

            var document = this.editor.Document;
            var selectionStart = this.editor.SelectionStart;
            var selectionEnd = selectionStart + this.editor.SelectionLength;
            var firstLine = document.GetLineByOffset(selectionStart);
            var lastOffset = selectionEnd;
            if (selectionEnd > selectionStart
                && selectionEnd == document.GetLineByOffset(selectionEnd).Offset) {
                --lastOffset;
            }
            var lastLine = document.GetLineByOffset(lastOffset);
            if (firstLine.LineNumber == lastLine.LineNumber) {
                return false;
            }

            var targetLineNumber = lineDelta < 0
                ? firstLine.LineNumber - 1
                : lastLine.LineNumber + 1;
            if (targetLineNumber < 1 || targetLineNumber > document.LineCount) {
                return true;
            }

            var targetLine = document.GetLineByNumber(targetLineNumber);
            var blockStart = firstLine.Offset;
            var blockEnd = lastLine.Offset + lastLine.TotalLength;
            var blockText = document.GetText(blockStart, blockEnd - blockStart);
            var targetText = document.GetText(targetLine.Offset, targetLine.TotalLength);
            var regionStart = Math.Min(blockStart, targetLine.Offset);
            var regionEnd = Math.Max(blockEnd, targetLine.Offset + targetLine.TotalLength);
            document.Replace(
                regionStart,
                regionEnd - regionStart,
                lineDelta < 0 ? blockText + targetText : targetText + blockText);

            var newSelectionStart = lineDelta < 0
                ? regionStart
                : blockStart + targetText.Length;
            this.editor.Select(newSelectionStart, blockText.Length);
            return true;
        }

        private string GetIndentation(int offset) {
            var line = this.editor.Document.GetLineByOffset(offset);
            var lineText = this.editor.Document.GetText(line.Offset, line.Length);
            return new string(lineText.TakeWhile(character => character is ' ' or '\t').ToArray());
        }

        private string GetTagIndentation(int offset) {
            var text = this.editor.Document.Text;
            var tagOffset = text.LastIndexOf('<', Math.Min(offset - 1, text.Length - 1));
            return tagOffset >= 0 ? this.GetIndentation(tagOffset) : this.GetIndentation(offset);
        }

        private string GetNewLineIndentation(int offset) {
            var line = this.editor.Document.GetLineByOffset(offset);
            var lineText = this.editor.Document.GetText(line.Offset, line.Length);
            var caretColumn = Math.Clamp(offset - line.Offset, 0, lineText.Length);
            var textBeforeCaret = lineText[..caretColumn];
            var trimmedBeforeCaret = textBeforeCaret.Trim();
            if (trimmedBeforeCaret.EndsWith("/>")) {
                return this.GetTagIndentation(offset);
            }
            if (trimmedBeforeCaret.StartsWith("</") && trimmedBeforeCaret.EndsWith('>')) {
                return this.GetIndentation(offset);
            }
            var tagStart = lineText.LastIndexOf('<', Math.Max(0, caretColumn - 1));
            if (tagStart < 0 || tagStart + 1 >= lineText.Length
                || lineText[tagStart + 1] is '/' or '?' or '!') {
                if (this.TryGetClosingTagIndentation(offset, out var closingTagIndentation)) {
                    return closingTagIndentation;
                }
                return this.GetIndentation(offset);
            }
            var beforeCaret = textBeforeCaret.TrimEnd();
            if (beforeCaret.EndsWith('>') && !beforeCaret.EndsWith("/>")) {
                if (this.editor.Document.Text.AsSpan(offset).StartsWith("</", StringComparison.Ordinal)) {
                    return this.GetIndentation(offset);
                }
                return this.GetIndentation(offset)
                    + new string(' ', this.editor.Options.IndentationSize);
            }

            var tagNameEnd = tagStart + 1;
            while (tagNameEnd < lineText.Length && !char.IsWhiteSpace(lineText[tagNameEnd])
                && lineText[tagNameEnd] is not '>' and not '/') {
                ++tagNameEnd;
            }
            var attributeStart = tagNameEnd;
            while (attributeStart < lineText.Length && char.IsWhiteSpace(lineText[attributeStart])) {
                ++attributeStart;
            }
            if (attributeStart >= caretColumn || attributeStart >= lineText.Length
                || lineText[attributeStart] is '>' or '/') {
                if (this.TryGetClosingTagIndentation(offset, out var closingTagIndentation)) {
                    return closingTagIndentation;
                }
                return this.GetIndentation(offset);
            }
            return new string(' ', attributeStart);
        }

        private bool TryGetClosingTagIndentation(int offset, out string indentation) {
            var text = this.editor.Document.Text;
            var tagOffset = offset;
            while (tagOffset < text.Length && char.IsWhiteSpace(text[tagOffset])) {
                ++tagOffset;
            }
            if (tagOffset + 2 <= text.Length && text.AsSpan(tagOffset).StartsWith("</", StringComparison.Ordinal)) {
                indentation = this.GetIndentation(tagOffset);
                return true;
            }
            indentation = string.Empty;
            return false;
        }

        private string GetContentIndentation(int offset) {
            var line = this.editor.Document.GetLineByOffset(offset);
            var lineText = this.editor.Document.GetText(line.Offset, line.Length);
            var indentation = this.GetIndentation(offset);
            var beforeCaret = lineText[..Math.Clamp(offset - line.Offset, 0, lineText.Length)];
            if (!string.IsNullOrWhiteSpace(beforeCaret)) {
                return indentation;
            }

            for (var lineNumber = line.LineNumber - 1; lineNumber >= 1; --lineNumber) {
                var previousLine = this.editor.Document.GetLineByNumber(lineNumber);
                var previousText = this.editor.Document.GetText(previousLine.Offset, previousLine.Length);
                if (string.IsNullOrWhiteSpace(previousText)) {
                    continue;
                }
                var trimmed = previousText.Trim();
                if (trimmed.StartsWith('<') && !trimmed.StartsWith("</")
                    && trimmed.EndsWith('>') && !trimmed.EndsWith("/>")) {
                    return this.GetIndentation(previousLine.Offset)
                        + new string(' ', this.editor.Options.IndentationSize);
                }
                break;
            }
            return indentation;
        }

        private static int LeadingWhitespaceLength(string value) {
            var length = 0;
            while (length < value.Length && value[length] is ' ' or '\t') {
                ++length;
            }
            return length;
        }

        private static bool IsWordCharacter(char character) {
            return char.IsLetterOrDigit(character) || character is '_' or ':' or '-' or '.';
        }

        private static SolidColorBrush CreateBrush(string value) {
            var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(value));
            brush.Freeze();
            return brush;
        }

    }
}