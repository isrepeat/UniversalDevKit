using System.IO;
using System.Xml;
using System.Xml.Linq;

namespace AndroidAppPreviewer {
    internal static class MarkupValidator {
        public static void Validate(XDocument document) {
            var root = document.Root
                ?? throw new InvalidDataException("Разметка не содержит корневого элемента.");
            if (root.Name.LocalName != "Page") {
                throw new InvalidDataException(
                    "Рендер поддерживает только страницы с корневым элементом <Page>.");
            }
            foreach (var textNode in document.DescendantNodes().OfType<XText>()) {
                if (!string.IsNullOrWhiteSpace(textNode.Value)) {
                    MarkupValidator.ThrowInvalidTextNode(textNode);
                }
            }
        }

        private static void ThrowInvalidTextNode(XText textNode) {
            var lineInfo = (IXmlLineInfo)textNode;
            var location = lineInfo.HasLineInfo()
                ? $"Строка {lineInfo.LineNumber}, позиция {lineInfo.LinePosition}."
                : "Расположение в документе не определено.";
            throw new InvalidDataException($"Недопустимый текст вне элемента. {location}");
        }
    }
}