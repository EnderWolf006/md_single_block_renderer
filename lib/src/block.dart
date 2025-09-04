import 'dart:async';
import 'package:markdown/markdown.dart' as md;
import 'extension_syntaxes/math_syntax.dart';
import 'extension_syntaxes/footnote_syntax.dart';
import 'package:flutter/foundation.dart';
import 'package:highlight/highlight.dart' as hl;

/// Lightweight representation of highlighted code after parsing.
/// Each token stores the raw text along with an optional highlight className.
class CodeToken {
  final String text;
  final String? className; // highlight class (e.g. 'keyword', 'string')
  const CodeToken(this.text, this.className);

  Map<String, Object?> toJson() => {'t': text, if (className != null) 'c': className};
  static CodeToken fromJson(Map<String, Object?> m) =>
      CodeToken(m['t'] as String? ?? '', m['c'] as String?);
}

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
  final String? footnoteId; // for footnote definition or reference
  final bool isFootnoteDefinition;
  final List<CodeToken>?
  codeTokens; // precomputed highlighted code tokens (for code blocks)

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
    this.footnoteId,
    this.isFootnoteDefinition = false,
    this.codeTokens,
  });

  @override
  String toString() =>
      'Block(tag: $blockTag, meta: $meta, path: ${path.map((e) => e.tag).join('>')})';
}

/// Convert markdown string into list of leaf [Block]s.
List<Block> markdownToBlocks(String markdownSource) {
  final doc = md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubWeb,
    inlineSyntaxes: [MathInlineSyntax(), FootnoteRefSyntax()],
    blockSyntaxes: const [MathBlockSyntax(), FootnoteBlockSyntax()],
  );
  final nodes = doc.parseLines(markdownSource.split('\n'));
  final blocks = <Block>[];
  int autoId = 0;
  int globalIndex = 0; // monotonically increasing index across ALL emitted blocks
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
              'globalIndex': globalIndex++,
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
          final cellAlignments = <String>[]; // left|center|right
          bool isHeaderRow = false;
          for (final cc in tr.children ?? const <md.Node>[]) {
            if (cc is md.Element && (cc.tag == 'td' || cc.tag == 'th')) {
              if (cc.tag == 'th') isHeaderRow = true;
              cells.add(_extractInlineNodes(cc));
              // Infer alignment from style attribute produced by markdown package (style="text-align: center").
              final styleAttr = cc.attributes['style'] ?? '';
              final alignAttr = cc.attributes['align'] ?? '';
              String align = 'left';
              final lowered = (styleAttr + ' ' + alignAttr).toLowerCase();
              if (lowered.contains('center'))
                align = 'center';
              else if (lowered.contains('right'))
                align = 'right';
              cellAlignments.add(align);
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
                if (cellAlignments.isNotEmpty) 'cellAlign': cellAlignments,
              },
              tableCells: cells,
              math: null,
            ),
          );
        }
        return;
      }

      // Direct math block emitted by syntax
      if (tag == 'math_block') {
        blocks.add(
          Block(
            id: 'b${autoId++}',
            path: newPath,
            blockTag: 'math_block',
            inlines: const [],
            rawCode: null,
            codeLanguage: null,
            isCodeBlock: false,
            math: node.textContent.trim(),
            footnoteId: null,
            isFootnoteDefinition: false,
          ),
        );
        return;
      }
      if (tag == 'footnote_def') {
        final idElem = (node.children ?? []).whereType<md.Element>().firstWhere(
          (e) => e.tag == 'id',
          orElse: () => md.Element.text('id', ''),
        );
        final id = idElem.textContent;
        final textContent =
            node.children?.whereType<md.Text>().map((e) => e.text).join('\n') ?? '';
        // Parse inner content as markdown to inline nodes
        final fakeParagraph = md.Element('p', [md.Text(textContent)]);
        final inlineNodes = _extractInlineNodes(fakeParagraph);
        blocks.add(
          Block(
            id: 'b${autoId++}',
            path: newPath,
            blockTag: 'footnote_def',
            inlines: inlineNodes,
            rawCode: null,
            codeLanguage: null,
            isCodeBlock: false,
            math: null,
            footnoteId: id,
            isFootnoteDefinition: true,
          ),
        );
        return;
      }
      final hasBlockChildren = children.any((c) => c is md.Element && _isBlockTag(c.tag));
      if (!hasBlockChildren && _isBlockTag(tag)) {
        if (tag == 'pre') {
          final codeEl = children.whereType<md.Element>().firstWhere(
            (e) => e.tag == 'code',
            orElse: () => md.Element.text('code', ''),
          );

          // Split code content into chunks of 8 lines each
          final codeContent = codeEl.textContent;
          final codeLanguage = codeEl.attributes['class']?.replaceFirst('language-', '');

          // Split into lines and remove trailing empty lines to avoid counting them
          var lines = codeContent.split('\n');
          while (lines.isNotEmpty && lines.last.isEmpty) {
            lines.removeLast();
          }

          // Calculate total number of blocks needed
          final totalBlocks = (lines.length / 8).ceil();
          final codeBlockGroupId = 'codeGroup$autoId';

          // Store the full original code content for copy functionality
          final fullCodeContent = lines.join('\n');
          // Precompute longest line (raw text) to avoid measuring all lines in widget
          String longestLine = '';
          for (final l in lines) {
            if (l.length > longestLine.length) longestLine = l;
          }

          // Create blocks for each chunk of 8 lines
          for (int i = 0; i < lines.length; i += 8) {
            final endIndex = (i + 8 < lines.length) ? i + 8 : lines.length;
            final chunkLines = lines.sublist(i, endIndex);
            final chunkContent = chunkLines.join('\n');
            final blockIndex = i ~/ 8;

            // Determine position in the group
            final isFirst = blockIndex == 0;
            final isLast = blockIndex == totalBlocks - 1;
            final isMiddle = !isFirst && !isLast;

            blocks.add(
              Block(
                id: 'b${autoId++}',
                path: newPath,
                blockTag: 'code',
                inlines: const [],
                rawCode: chunkContent,
                codeLanguage: codeLanguage,
                isCodeBlock: true,
                codeTokens: _buildCodeTokens(chunkContent, codeLanguage),
                meta: {
                  'codeBlockGroupId': codeBlockGroupId,
                  'globalIndex': globalIndex++,
                  'isFirstInGroup': isFirst,
                  'isLastInGroup': isLast,
                  'isMiddleInGroup': isMiddle,
                  'blockIndex': blockIndex,
                  'totalBlocks': totalBlocks,
                  'fullCodeContent': fullCodeContent,
                  'fullCodeLongestLine': longestLine,
                },
                math: null,
                footnoteId: null,
                isFootnoteDefinition: false,
              ),
            );
          }
        } else if (tag == 'hr') {
          blocks.add(
            Block(
              id: 'b${autoId++}',
              path: newPath,
              blockTag: tag,
              meta: {'globalIndex': globalIndex++},
              inlines: const [],
              rawCode: null,
              codeLanguage: null,
              isCodeBlock: false,
              codeTokens: null,
              math: null,
              footnoteId: null,
              isFootnoteDefinition: false,
            ),
          );
        } else {
          final inlineNodes = _extractInlineNodes(node);
          // If this paragraph sits inside a blockquote anywhere in its path, expose it
          // as a 'blockquote' block so consumers can style it directly without needing
          // to inspect its ancestors. (Only override simple paragraph leaves.)
          final insideBlockquote = tag == 'p' && path.any((e) => e.tag == 'blockquote');
          final effectiveTag = insideBlockquote ? 'blockquote' : tag;
          blocks.add(
            Block(
              id: 'b${autoId++}',
              path: newPath,
              blockTag: effectiveTag,
              inlines: inlineNodes,
              rawCode: null,
              codeLanguage: null,
              isCodeBlock: false,
              math: null,
              footnoteId: null,
              isFootnoteDefinition: false,
              codeTokens: null,
              meta: {'globalIndex': globalIndex++},
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
            footnoteId: null,
            isFootnoteDefinition: false,
            codeTokens: null,
            meta: {'globalIndex': globalIndex++},
          ),
        );
      }
    }
  }

  for (final root in nodes) visit(root, []);
  return blocks;
}

/// Highlight code into tokens using highlight package. Falls back to plain text token list.
List<CodeToken> _buildCodeTokens(String code, String? language) {
  final lang = (language ?? '').trim();
  String normalize(String input) {
    final l = input.toLowerCase();
    switch (l) {
      case 'js':
        return 'javascript';
      case 'ts':
        return 'typescript';
      case 'py':
        return 'python';
      case 'c++':
        return 'cpp';
      case 'sh':
        return 'bash';
      case 'md':
      case 'markdown':
        return 'markdown';
      case 'yml':
        return 'yaml';
      default:
        return l;
    }
  }

  try {
    final res = hl.highlight.parse(
      code.trimRight(),
      language: lang.isEmpty ? null : normalize(lang),
    );
    final out = <CodeToken>[];
    void walk(hl.Node n, [String? parentClass]) {
      final cls = n.className ?? parentClass;
      if (n.value != null) {
        out.add(CodeToken(n.value!, cls));
      } else if (n.children != null) {
        for (final c in n.children!) {
          walk(c, cls);
        }
      }
    }

    for (final n in res.nodes ?? const <hl.Node>[]) {
      walk(n);
    }
    if (out.isEmpty) return [CodeToken(code, null)];
    return out;
  } catch (_) {
    return [CodeToken(code, null)];
  }
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
        if (b.codeTokens != null)
          'codeTok': b.codeTokens!.map((t) => t.toJson()).toList(),
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
        if (b.footnoteId != null) 'footnoteId': b.footnoteId,
        if (b.isFootnoteDefinition) 'footDef': true,
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
  footnoteId: m['footnoteId'] as String?,
  isFootnoteDefinition: (m['footDef'] as bool?) ?? false,
  codeTokens: (m['codeTok'] as List?)
      ?.map((e) => CodeToken.fromJson((e as Map).cast<String, Object?>()))
      .toList(),
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
      return BlockInlineNode('text', text: node.text);
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
        case 'footnote_ref':
          return BlockInlineNode('footnote_ref', text: node.textContent);
        case 'math_inline':
          return BlockInlineNode('math', text: node.textContent);
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
  for (final c in ch) result.add(walk(c));
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
      final t = n.text.trim();
      if (t.isNotEmpty) {
        sep();
        out.add(BlockInlineNode('text', text: t));
      }
    }
  }

  for (final c in children) walk(c);
  return out.isEmpty ? const [BlockInlineNode('text', text: '')] : out;
}

// inline math handled by Markdown extension syntaxes
