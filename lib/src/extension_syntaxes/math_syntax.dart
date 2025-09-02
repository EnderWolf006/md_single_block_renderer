import 'package:markdown/markdown.dart' as md;

/// Inline math: $...$ using a markdown InlineSyntax instead of manual scanning.
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax() : super(r'(?<!\\)\$(?!\$)(.+?)(?<!\\)\$(?!\$)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match.group(1)!;
    if (content.trim().isEmpty) return false;
    parser.addNode(md.Element('math_inline', [md.Text(content)]));
    return true;
  }
}

/// Block math: lines fenced by $$ ... $$ handled as a custom BlockSyntax.
class MathBlockSyntax extends md.BlockSyntax {
  const MathBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*\$\$');

  @override
  bool canEndBlock(md.BlockParser parser) => false;

  @override
  bool canParse(md.BlockParser parser) => pattern.hasMatch(parser.current.content);

  @override
  md.Node parse(md.BlockParser parser) {
    final startLine = parser.current.content.trimRight();
    // Single line $$ ... $$
    if (RegExp(r'^\s*\$\$.*\$\$\s*$').hasMatch(startLine) &&
        startLine.replaceAll('\n', '').length > 4) {
      final inner = startLine
          .replaceFirst(RegExp(r'^\s*\$\$'), '')
          .replaceFirst(RegExp(r'\$\$\s*$'), '')
          .trim();
      parser.advance();
      return md.Element('math_block', [md.Text(inner)]);
    }
    // Multi-line
    parser.advance();
    final buffer = <String>[];
    while (!parser.isDone) {
      final line = parser.current.content.trimRight();
      if (RegExp(r'^\s*\$\$\s*$').hasMatch(line.trim())) {
        parser.advance();
        break;
      }
      buffer.add(line);
      parser.advance();
    }
    final content = buffer.join('\n').trim();
    return md.Element('math_block', [md.Text(content)]);
  }
}
