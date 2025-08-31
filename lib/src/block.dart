import 'dart:async';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter/foundation.dart';

/// Represents one leaf block extracted from the markdown AST.
/// A leaf block is a block level node that has no block children (only inline
/// content or raw text). Examples: paragraph, header, blockquote paragraph leaf,
/// list item paragraph, code block, horizontal rule.
///
/// We store the path from root to this leaf so styling/context (e.g. inside
/// blockquote > listItem > paragraph) can be derived.
class BlockPathEntry {
  final String tag; // e.g. 'blockquote', 'li', 'ol', 'ul', 'p', 'h1'
  final Map<String, dynamic>? attributes; // potential attributes (id, etc.)
  const BlockPathEntry(this.tag, [this.attributes]);
}

class BlockInlineNode {
  final String type; // 'text', 'em', 'strong', 'code', 'link', 'image', 'math'
  final String? text; // for text/code/math raw content
  final Map<String, dynamic>? data; // href, title, alt, etc.
  final List<BlockInlineNode> children;
  const BlockInlineNode(this.type, {this.text, this.data, this.children = const []});
}

class Block {
  final String id; // stable id for keys
  final List<BlockPathEntry> path; // root->leaf
  final String blockTag; // leaf tag (p, h1, code, li, table_row ...)
  final List<BlockInlineNode>
  inlines; // inline rich text (paragraph-like, list item aggregated, heading)
  final String? rawCode; // code block content
  final String? codeLanguage; // code block language if any
  final bool isCodeBlock;
  final Map<String, dynamic>?
  meta; // extra info (listType, order, depth, isHeader, rowIndex, columnCount)
  final List<List<BlockInlineNode>>?
  tableCells; // for table_row blocks: each cell's inline nodes
  final String? math; // for block math (between $$ $$)

  const Block({
    required this.id,
    required this.path,
    required this.blockTag,
    required this.inlines,
    required this.rawCode,
    required this.codeLanguage,
    required this.isCodeBlock,
    this.meta,
    this.tableCells,
    this.math,
  });

  @override
  String toString() =>
      'Block(tag: $blockTag, meta: $meta, path: ${path.map((e) => e.tag).join('>')})';
}

/// Convert markdown string into list of leaf [Block]s.
List<Block> markdownToBlocks(String markdownSource) {
  // Preprocess block math ($$...$$)
  const placeholderPrefix = '§§MATHBLOCK§§';
  final lines = markdownSource.split('\n');
  final mathBlocks = <String>[]; // store raw math content
  final processed = <String>[];
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    // Multi-line block math start/stop lines containing only $$
    if (trimmed == r'$$') {
      final buffer = <String>[];
      i++;
      while (i < lines.length) {
        final inner = lines[i];
        if (inner.trim() == r'$$') {
          break;
        }
        buffer.add(inner);
        i++;
      }
      final content = buffer.join('\n').trim();
      final id = mathBlocks.length;
      mathBlocks.add(content);
      processed.add('$placeholderPrefix$id');
      continue;
    } else if (trimmed.length > 4 &&
        trimmed.startsWith(r'$$') &&
        trimmed.endsWith(r'$$')) {
      // Single-line $$...$$
      final content = trimmed.substring(2, trimmed.length - 2).trim();
      final id = mathBlocks.length;
      mathBlocks.add(content);
      processed.add('$placeholderPrefix$id');
      continue;
    }
    processed.add(line);
  }
  final preprocessedSource = processed.join('\n');
  final doc = md.Document(encodeHtml: false, extensionSet: md.ExtensionSet.gitHubWeb);
  final nodes = doc.parseLines(preprocessedSource.split('\n'));
  final blocks = <Block>[];
  int autoId = 0;
  final List<int?> _listStack = []; // null for unordered, int counter for ordered

  void visit(md.Node node, List<BlockPathEntry> path) {
    if (node is md.Element) {
      final tag = node.tag;
      final newPath = [
        ...path,
        BlockPathEntry(tag, node.attributes.isEmpty ? null : node.attributes),
      ];
      final children = node.children ?? const <md.Node>[];
      // Enter/exit lists
      if (tag == 'ol') {
        _listStack.add(0); // start counter
        for (final c in children) visit(c, newPath);
        _listStack.removeLast();
        return;
      }
      if (tag == 'ul') {
        _listStack.add(null); // unordered
        for (final c in children) visit(c, newPath);
        _listStack.removeLast();
        return;
      }
      if (tag == 'li') {
        final listType = path
            .lastWhere(
              (e) => e.tag == 'ul' || e.tag == 'ol',
              orElse: () => const BlockPathEntry('ul'),
            )
            .tag;
        int? order;
        if (listType == 'ol' && _listStack.isNotEmpty) {
          final topIdx = _listStack.length - 1;
          final next = (_listStack[topIdx] ?? 0) + 1;
          _listStack[topIdx] = next;
          order = next;
        }
        final inlinePart = <md.Node>[];
        final nestedLists = <md.Element>[];
        for (final c in children) {
          if (c is md.Element && (c.tag == 'ul' || c.tag == 'ol')) {
            nestedLists.add(c);
          } else {
            inlinePart.add(c);
          }
        }
        final aggregated = _gatherListItemInline(inlinePart);
        blocks.add(
          Block(
            id: 'b${autoId++}',
            path: newPath,
            blockTag: 'li',
            inlines: aggregated,
            rawCode: null,
            codeLanguage: null,
            isCodeBlock: false,
            meta: {
              'listType': listType,
              if (order != null) 'order': order,
              'depth': path.where((p) => p.tag == 'ul' || p.tag == 'ol').length,
            },
            math: null,
          ),
        );
        for (final nl in nestedLists) {
          visit(nl, newPath);
        }
        return;
      }

      // Table into rows
      if (tag == 'table') {
        final rowElements = <md.Element>[];
        for (final c in children) {
          if (c is md.Element && (c.tag == 'thead' || c.tag == 'tbody')) {
            final rows =
                c.children?.whereType<md.Element>().where((e) => e.tag == 'tr') ??
                const Iterable<md.Element>.empty();
            rowElements.addAll(rows);
          } else if (c is md.Element && c.tag == 'tr') {
            rowElements.add(c);
          }
        }
        int rowIndex = 0;
        for (final tr in rowElements) {
          final cells = <List<BlockInlineNode>>[];
          bool isHeaderRow = false;
          for (final cc in tr.children ?? const <md.Node>[]) {
            if (cc is md.Element && (cc.tag == 'td' || cc.tag == 'th')) {
              if (cc.tag == 'th') isHeaderRow = true;
              cells.add(_extractInlineNodes(cc));
            }
          }
          blocks.add(
            Block(
              id: 'b${autoId++}',
              path: [...newPath, const BlockPathEntry('tr')],
              blockTag: 'table_row',
              inlines: const [],
              rawCode: null,
              codeLanguage: null,
              isCodeBlock: false,
              meta: {
                'isHeader': isHeaderRow,
                'rowIndex': rowIndex++,
                'columnCount': cells.length,
              },
              tableCells: cells,
              math: null,
            ),
          );
        }
        return;
      }

      final hasBlockChildren = children.any((c) => c is md.Element && _isBlockTag(c.tag));
      if (!hasBlockChildren && _isBlockTag(tag)) {
        if (tag == 'pre') {
          final codeEl = children.whereType<md.Element>().firstWhere(
            (e) => e.tag == 'code',
            orElse: () => md.Element.text('code', ''),
          );
          blocks.add(
            Block(
              id: 'b${autoId++}',
              path: newPath,
              blockTag: 'code',
              inlines: const [],
              rawCode: codeEl.textContent,
              codeLanguage: codeEl.attributes['class']?.replaceFirst('language-', ''),
              isCodeBlock: true,
              math: null,
            ),
          );
        } else if (tag == 'hr') {
          blocks.add(
            Block(
              id: 'b${autoId++}',
              path: newPath,
              blockTag: tag,
              inlines: const [],
              rawCode: null,
              codeLanguage: null,
              isCodeBlock: false,
              math: null,
            ),
          );
        } else {
          final inlineNodes = _extractInlineNodes(node);
          // Detect placeholder only paragraph -> math block
          if (inlineNodes.length == 1 && inlineNodes.first.type == 'text') {
            final txt = inlineNodes.first.text?.trim() ?? '';
            if (txt.startsWith(placeholderPrefix)) {
              final idxStr = txt.substring(placeholderPrefix.length);
              final idx = int.tryParse(idxStr);
              if (idx != null && idx >= 0 && idx < mathBlocks.length) {
                blocks.add(
                  Block(
                    id: 'b${autoId++}',
                    path: newPath,
                    blockTag: 'math_block',
                    inlines: const [],
                    rawCode: null,
                    codeLanguage: null,
                    isCodeBlock: false,
                    math: mathBlocks[idx],
                  ),
                );
                return; // done
              }
            }
          }
          blocks.add(
            Block(
              id: 'b${autoId++}',
              path: newPath,
              blockTag: tag,
              inlines: inlineNodes,
              rawCode: null,
              codeLanguage: null,
              isCodeBlock: false,
              math: null,
            ),
          );
        }
      } else {
        for (final child in children) visit(child, newPath);
      }
    } else if (node is md.Text) {
      final text = node.text.trim();
      if (text.isNotEmpty) {
        blocks.add(
          Block(
            id: 'b${autoId++}',
            path: [...path, const BlockPathEntry('p')],
            blockTag: 'p',
            inlines: [BlockInlineNode('text', text: text)],
            rawCode: null,
            codeLanguage: null,
            isCodeBlock: false,
            math: null,
          ),
        );
      }
    }
  }

  for (final root in nodes) visit(root, []);
  return blocks;
}

/// Serialize a list of Blocks to JSON-safe structure (for isolate transfer)
List<Map<String, Object?>> _blocksToJson(List<Block> blocks) => blocks
    .map(
      (b) => {
        'id': b.id,
        'blockTag': b.blockTag,
        'isCodeBlock': b.isCodeBlock,
        'rawCode': b.rawCode,
        'codeLanguage': b.codeLanguage,
        if (b.meta != null) 'meta': b.meta,
        'path': b.path
            .map(
              (p) => {'tag': p.tag, if (p.attributes != null) 'attributes': p.attributes},
            )
            .toList(),
        'inlines': b.inlines.map(_inlineToJson).toList(),
        if (b.math != null) 'math': b.math,
        if (b.tableCells != null)
          'tableCells': b.tableCells!
              .map((cell) => cell.map(_inlineToJson).toList())
              .toList(),
      },
    )
    .toList();

Map<String, Object?> _inlineToJson(BlockInlineNode n) => {
  'type': n.type,
  if (n.text != null) 'text': n.text,
  if (n.data != null) 'data': n.data,
  if (n.children.isNotEmpty) 'children': n.children.map(_inlineToJson).toList(),
};

BlockInlineNode _inlineFromJson(Map<String, Object?> m) => BlockInlineNode(
  m['type'] as String,
  text: m['text'] as String?,
  data: (m['data'] as Map?)?.cast<String, dynamic>(),
  children: ((m['children'] as List?) ?? const [])
      .map((e) => _inlineFromJson((e as Map).cast<String, Object?>()))
      .toList(),
);

Block _blockFromJson(Map<String, Object?> m) => Block(
  id: m['id'] as String,
  path: (m['path'] as List).map((e) {
    final em = (e as Map).cast<String, Object?>();
    return BlockPathEntry(
      em['tag'] as String,
      (em['attributes'] as Map?)?.cast<String, dynamic>(),
    );
  }).toList(),
  blockTag: m['blockTag'] as String,
  inlines: ((m['inlines'] as List?) ?? const [])
      .map((e) => _inlineFromJson((e as Map).cast<String, Object?>()))
      .toList(),
  rawCode: m['rawCode'] as String?,
  codeLanguage: m['codeLanguage'] as String?,
  isCodeBlock: m['isCodeBlock'] as bool,
  meta: (m['meta'] as Map?)?.cast<String, dynamic>(),
  tableCells: (m['tableCells'] as List?)
      ?.map(
        (row) => (row as List)
            .map((e) => _inlineFromJson((e as Map).cast<String, Object?>()))
            .toList(),
      )
      .toList(),
  math: m['math'] as String?,
);

/// Top-level entry for compute (must be a top-level or static function).
List<Map<String, Object?>> _computeMarkdownToBlocks(String source) =>
    _blocksToJson(markdownToBlocks(source));

/// Async version using isolate (compute) to avoid jank. If already on a worker
/// isolate you can still call the sync [markdownToBlocks].
Future<List<Block>> markdownToBlocksAsync(
  String source, {
  bool compressed = false,
}) async {
  // Optionally compress if large (not implemented compression yet, placeholder parameter)
  final jsonList = await compute<String, List<Map<String, Object?>>>(
    _computeMarkdownToBlocks,
    source,
  );
  return jsonList.map(_blockFromJson).toList();
}

bool _isBlockTag(String tag) {
  const blockTags = {
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'pre',
    'blockquote',
    'ul',
    'ol',
    'li',
    'hr',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
  }; // removed inline-only 'code'
  return blockTags.contains(tag);
}

List<BlockInlineNode> _extractInlineNodes(md.Element element) {
  final result = <BlockInlineNode>[];

  BlockInlineNode walk(md.Node node) {
    if (node is md.Text) {
      return BlockInlineNode('text', text: node.text); // will be split later if needed
    }
    if (node is md.Element) {
      final t = node.tag;
      if (_isBlockTag(t) && t != 'code') {
        // block tag inside inline context probably should not happen here.
        return BlockInlineNode('text', text: node.textContent);
      }
      final ch = node.children ?? const <md.Node>[];
      final children = ch.map(walk).toList();
      switch (t) {
        case 'em':
          return BlockInlineNode('em', children: children);
        case 'strong':
          return BlockInlineNode('strong', children: children);
        case 'code':
          return BlockInlineNode('code', text: node.textContent);
        case 'a':
          return BlockInlineNode(
            'link',
            data: {'href': node.attributes['href'], 'title': node.attributes['title']},
            children: children,
          );
        case 'img':
          return BlockInlineNode(
            'image',
            data: {'src': node.attributes['src'], 'alt': node.attributes['alt']},
          );
        case 'del':
          return BlockInlineNode('del', children: children);
        default:
          return BlockInlineNode(t, children: children);
      }
    }
    return BlockInlineNode('text', text: node.textContent);
  }

  final ch = element.children ?? const <md.Node>[];
  for (final c in ch) {
    final walked = walk(c);
    if (walked.type == 'text' && walked.text != null) {
      result.addAll(_splitInlineMath(walked.text!));
    } else {
      result.add(walked);
    }
  }
  return result;
}

List<BlockInlineNode> _gatherListItemInline(List<md.Node> children) {
  final out = <BlockInlineNode>[];
  bool first = true;
  void sep() {
    if (!first) out.add(const BlockInlineNode('text', text: '\n'));
    first = false;
  }

  void walk(md.Node n) {
    if (n is md.Element) {
      if (n.tag == 'p' || n.tag.startsWith('h')) {
        sep();
        out.addAll(_extractInlineNodes(n));
      } else if (n.tag == 'code') {
        sep();
        out.add(BlockInlineNode('code', text: n.textContent));
      } else if (_isBlockTag(n.tag)) {
        for (final c in n.children ?? const <md.Node>[]) walk(c);
      } else {
        out.addAll(_extractInlineNodes(n));
      }
    } else if (n is md.Text) {
      final raw = n.text;
      final t = raw.trim();
      if (t.isNotEmpty) {
        sep();
        for (final seg in _splitInlineMath(t)) {
          out.add(seg);
        }
      }
    }
  }

  for (final c in children) walk(c);
  return out.isEmpty ? const [BlockInlineNode('text', text: '')] : out;
}

// Split a plain text into segments with inline math ($...$) while avoiding $$ blocks.
List<BlockInlineNode> _splitInlineMath(String text) {
  final out = <BlockInlineNode>[];
  final buffer = StringBuffer();
  bool inMath = false;
  for (int i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == r'$') {
      final next = i + 1 < text.length ? text[i + 1] : '';
      // Ignore if starts/ends with $$ (block) or escaped \$
      final prev = i > 0 ? text[i - 1] : '';
      final isEscaped = prev == '\\';
      if (!isEscaped) {
        // Double $$ => leave for block (already handled via preprocessing) so treat literally
        if (next == r'$') {
          buffer.write(r'$$');
          i++; // skip next
          continue;
        }
        // Toggle inline math
        if (inMath) {
          // close math
          final content = buffer.toString();
          out.add(BlockInlineNode('math', text: content));
          buffer.clear();
          inMath = false;
        } else {
          // flush buffer as text
          if (buffer.isNotEmpty) {
            out.add(BlockInlineNode('text', text: buffer.toString()));
            buffer.clear();
          }
          inMath = true;
        }
        continue;
      }
    }
    buffer.write(ch);
  }
  if (buffer.isNotEmpty) {
    final leftover = buffer.toString();
    out.add(BlockInlineNode(inMath ? 'math' : 'text', text: leftover));
  }
  return out;
}
