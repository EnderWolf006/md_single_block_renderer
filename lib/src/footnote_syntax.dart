import 'package:markdown/markdown.dart' as md;

/// Matches footnote references like [^id].
class FootnoteRefSyntax extends md.InlineSyntax {
  FootnoteRefSyntax() : super(r'\[\^([A-Za-z0-9_-]+)\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final id = match.group(1)!;
    parser.addNode(md.Element('footnote_ref', [md.Text(id)]));
    return true;
  }
}

/// Footnote definition block: lines starting with "[^id]:".
class FootnoteBlockSyntax extends md.BlockSyntax {
  const FootnoteBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^\[\^([A-Za-z0-9_-]+)\]:\s+');

  @override
  bool canParse(md.BlockParser parser) => pattern.hasMatch(parser.current.content);

  @override
  md.Node parse(md.BlockParser parser) {
    final line = parser.current.content;
    final match = pattern.firstMatch(line)!;
    final id = match.group(1)!;
    var content = line.substring(match.end).trimRight();
    parser.advance();
    // Collect indented continuation lines (4 spaces or tab)
    final buffer = StringBuffer(content);
    while (!parser.isDone) {
      final next = parser.current.content;
      if (next.startsWith('    ') || next.startsWith('\t')) {
        buffer.write('\n');
        buffer.write(next.replaceFirst(RegExp(r'^(    |\t)'), ''));
        parser.advance();
      } else {
        break;
      }
    }
    return md.Element('footnote_def', [
      md.Element.text('id', id),
      md.Text(buffer.toString()),
    ]);
  }
}
