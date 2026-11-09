using System.IO;
using System.Xml;

using ICSharpCode.AvalonEdit.Highlighting;
using ICSharpCode.AvalonEdit.Highlighting.Xshd;

namespace AndroidAppPreviewer {
    internal static class MarkupSyntaxHighlighter {
        public static IHighlightingDefinition Create() {
            const string definition = """
                <SyntaxDefinition name="Previewer XML" xmlns="http://icsharpcode.net/sharpdevelop/syntaxdefinition/2008">
                    <Color name="Comment" foreground="#6A9955" />
                    <Color name="Declaration" foreground="#C586C0" />
                    <Color name="Tag" foreground="#569CD6" />
                    <Color name="Attribute" foreground="#9CDCFE" />
                    <Color name="Value" foreground="#CE9178" />
                    <Color name="Entity" foreground="#DCDCAA" />
                    <RuleSet>
                        <Span color="Comment" multiline="true">
                            <Begin>&lt;!--</Begin>
                            <End>--&gt;</End>
                        </Span>
                        <Span color="Declaration" multiline="true">
                            <Begin>&lt;\?</Begin>
                            <End>\?&gt;</End>
                        </Span>
                        <Span color="Tag" multiline="true">
                            <Begin>&lt;</Begin>
                            <End>&gt;</End>
                            <RuleSet>
                                <Span color="Value" multiline="true">
                                    <Begin>"</Begin>
                                    <End>"|(?=&lt;)</End>
                                </Span>
                                <Span color="Value" multiline="true">
                                    <Begin>'</Begin>
                                    <End>'|(?=&lt;)</End>
                                </Span>
                                <Rule color="Attribute">[\d\w_\-\.]+(?=\s*=)</Rule>
                            </RuleSet>
                        </Span>
                        <Rule color="Entity">&amp;[\w\d\#]+;</Rule>
                    </RuleSet>
                </SyntaxDefinition>
                """;
            return MarkupSyntaxHighlighter.Load(definition);
        }

        public static IHighlightingDefinition CreateJson() {
            const string definition = """
                <SyntaxDefinition name="Previewer JSON" xmlns="http://icsharpcode.net/sharpdevelop/syntaxdefinition/2008">
                    <Color name="Property" foreground="#9CDCFE" />
                    <Color name="String" foreground="#CE9178" />
                    <Color name="Number" foreground="#B5CEA8" />
                    <Color name="Keyword" foreground="#C586C0" />
                    <RuleSet>
                        <Rule color="Property">"[^"\\]*(?:\\.[^"\\]*)*"(?=\s*:)</Rule>
                        <Span color="String" multiline="true">
                            <Begin>"</Begin>
                            <End>"</End>
                        </Span>
                        <Rule color="Number">-?\b\d+(\.\d+)?([eE][+-]?\d+)?\b</Rule>
                        <Keywords color="Keyword">
                            <Word>true</Word>
                            <Word>false</Word>
                            <Word>null</Word>
                        </Keywords>
                    </RuleSet>
                </SyntaxDefinition>
                """;
            return MarkupSyntaxHighlighter.Load(definition);
        }

        private static IHighlightingDefinition Load(string definition) {
            using var reader = XmlReader.Create(new StringReader(definition));
            return HighlightingLoader.Load(reader, HighlightingManager.Instance);
        }
    }
}