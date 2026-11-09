using ICSharpCode.AvalonEdit.Folding;
using ICSharpCode.AvalonEdit.Document;

namespace AndroidAppPreviewer {
    internal sealed class XmlFoldingStrategy {
        private readonly record struct OpenTag(string Name, int StartOffset, int EndOffset);

        public IEnumerable<NewFolding> CreateNewFoldings(TextDocument document) {
            var foldings = new List<NewFolding>();
            var openTags = new Stack<OpenTag>();
            var text = document.Text;
            var offset = 0;

            while (offset < text.Length) {
                if (text[offset] != '<') {
                    ++offset;
                    continue;
                }

                if (XmlFoldingStrategy.StartsWith(text, offset, "<!--")) {
                    offset = XmlFoldingStrategy.SkipTo(text, offset + 4, "-->");
                    continue;
                }
                if (XmlFoldingStrategy.StartsWith(text, offset, "<![CDATA[")) {
                    offset = XmlFoldingStrategy.SkipTo(text, offset + 9, "]]>");
                    continue;
                }
                if (XmlFoldingStrategy.StartsWith(text, offset, "<?")) {
                    offset = XmlFoldingStrategy.SkipTo(text, offset + 2, "?>");
                    continue;
                }
                if (XmlFoldingStrategy.StartsWith(text, offset, "<!")) {
                    offset = XmlFoldingStrategy.FindTagEnd(text, offset + 2) + 1;
                    continue;
                }

                var tagEnd = XmlFoldingStrategy.FindTagEnd(text, offset + 1);
                if (tagEnd >= text.Length) {
                    break;
                }
                var position = offset + 1;
                bool isClosing = position < tagEnd && text[position] == '/';
                if (isClosing) {
                    ++position;
                }
                while (position < tagEnd && char.IsWhiteSpace(text[position])) {
                    ++position;
                }
                var nameStart = position;
                while (position < tagEnd && XmlFoldingStrategy.IsNameCharacter(text[position])) {
                    ++position;
                }
                if (nameStart == position) {
                    offset = tagEnd + 1;
                    continue;
                }

                var name = text[nameStart..position];
                if (isClosing) {
                    if (openTags.TryPeek(out var openTag) && openTag.Name == name) {
                        openTags.Pop();
                        if (document.GetLineByOffset(openTag.StartOffset).LineNumber
                            < document.GetLineByOffset(offset).LineNumber) {
                            foldings.Add(new NewFolding(openTag.StartOffset, offset) {
                                Name = text[openTag.StartOffset..openTag.EndOffset].Trim() + " …",
                            });
                        }
                    }
                }
                else if (!XmlFoldingStrategy.IsSelfClosing(text, tagEnd)) {
                    openTags.Push(new OpenTag(name, offset, tagEnd + 1));
                }
                offset = tagEnd + 1;
            }

            return foldings.OrderBy(folding => folding.StartOffset);
        }

        private static int FindTagEnd(string text, int offset) {
            char quote = '\0';
            for (var position = offset; position < text.Length; ++position) {
                var character = text[position];
                if (quote != '\0') {
                    if (character == quote) {
                        quote = '\0';
                    }
                    continue;
                }
                if (character is '\'' or '"') {
                    quote = character;
                }
                else if (character == '>') {
                    return position;
                }
            }
            return text.Length;
        }

        private static bool IsNameCharacter(char character) {
            return char.IsLetterOrDigit(character) || character is '_' or ':' or '-' or '.';
        }

        private static bool IsSelfClosing(string text, int tagEnd) {
            for (var position = tagEnd - 1; position >= 0; --position) {
                if (char.IsWhiteSpace(text[position])) {
                    continue;
                }
                return text[position] == '/';
            }
            return false;
        }

        private static int SkipTo(string text, int offset, string terminator) {
            var end = text.IndexOf(terminator, offset, StringComparison.Ordinal);
            return end < 0 ? text.Length : end + terminator.Length;
        }

        private static bool StartsWith(string text, int offset, string value) {
            return offset + value.Length <= text.Length
                && text.AsSpan(offset, value.Length).SequenceEqual(value);
        }
    }
}