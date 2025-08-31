import 'package:flutter_test/flutter_test.dart';
import 'package:md_single_block_renderer/md_single_block_renderer.dart';

String _inlineToPlainText(List<BlockInlineNode> nodes) {
  final buf = StringBuffer();
  void walk(BlockInlineNode n) {
    if (n.text != null) buf.write(n.text);
    for (final c in n.children) walk(c);
  }

  for (final n in nodes) walk(n);
  return buf.toString();
}

void main() {
  test('markdownToBlocks splits into leaf blocks', () {
    const source = '# Title\n\n> quote line with `code`\n\nParagraph **bold** text';
    final blocks = markdownToBlocks(source);
    // Debug: print summary of all blocks
    // ignore: avoid_print
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final text = b.isCodeBlock
          ? '[code:${b.rawCode?.length} chars]'
          : _inlineToPlainText(b.inlines);
      print(
        '[B#$i] tag=${b.blockTag} path=${b.path.map((e) => e.tag).join('>')} meta=${b.meta} text="$text"',
      );
    }
    expect(blocks.length >= 3, true);
    expect(blocks.any((b) => b.blockTag == 'h1'), true);
  });

  test('markdownToBlocksAsync returns same or more blocks', () async {
    const source = '# Title\n\nParagraph **bold** text';
    final syncBlocks = markdownToBlocks(source);
    final asyncBlocks = await markdownToBlocksAsync(source);
    // ignore: avoid_print
    print('Async blocks: ${asyncBlocks.map((b) => b.blockTag).toList()}');
    expect(asyncBlocks.length, syncBlocks.length);
    expect(asyncBlocks.first.blockTag, 'h1');
  });

  test('list items become li blocks with meta', () {
    const source = '''
1. First item
2. Second item
   - nested a
   - nested b
3. Third item
''';
    final blocks = markdownToBlocks(source);
    final liBlocks = blocks.where((b) => b.blockTag == 'li').toList();
    // Now nested unordered items become their own li blocks: 3 ordered + 2 nested unordered = 5
    expect(liBlocks.length, 5);
    // ignore: avoid_print
    for (final b in liBlocks) {
      print(
        'LI tag=${b.blockTag} meta=${b.meta} text="${_inlineToPlainText(b.inlines)}"',
      );
    }
    final ordered = liBlocks.where((b) => b.meta?['listType'] == 'ol').toList();
    final orders = ordered.map((b) => b.meta?['order']).whereType<int>().toList();
    expect(orders, [1, 2, 3]);
  });

  test('tables become table_row blocks with cell metadata', () {
    const source = '''
| H1 | H2 |
|----|----|
| C1 | C2 |
| C3 | C4 |
''';
    final blocks = markdownToBlocks(source);
    final rows = blocks.where((b) => b.blockTag == 'table_row').toList();
    // Expect 3 rows (1 header + 2 body)
    // ignore: avoid_print
    for (final r in rows) {
      final cellsText = (r.tableCells ?? [])
          .map((cell) => _inlineToPlainText(cell))
          .toList();
      print('TR meta=${r.meta} cells=$cellsText');
    }
    expect(rows.length, 3);
    final header = rows.first;
    expect(header.meta?['isHeader'], true);
    expect(header.tableCells?.length, 2);
    final firstBody = rows[1];
    expect(firstBody.meta?['isHeader'], false);
    expect(firstBody.tableCells?.length, 2);
  });

  test('inline math with \\ce macro preprocesses', () {
    final md = '公式：\$\\ce{Hg^2+ ->[I-] HgI2 ->[I-] [Hg^{II}I4]^2-}\$';
    final blocks = markdownToBlocks(md);
    final p = blocks.firstWhere((b) => b.blockTag == 'p');
    final hasMath = p.inlines.any((n) => n.type == 'math');
    expect(hasMath, true);
  });
}
