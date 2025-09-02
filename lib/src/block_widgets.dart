import 'package:flutter/material.dart';
import 'block.dart';
import 'inline_span_builder.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:highlight/highlight.dart' as hl;

/// Builds a widget for a single Block.
class MarkdownSingleBlockRenderer extends StatelessWidget {
  final Block block;
  final InlineSpanBuilder? inlineBuilderOverride;
  final TextStyle? baseTextStyle;
  final void Function(String url)? onTapLink;

  const MarkdownSingleBlockRenderer(
    this.block, {
    super.key,
    this.inlineBuilderOverride,
    this.baseTextStyle,
    this.onTapLink,
  });

  TextStyle _resolveBaseStyle(BuildContext context) {
    return baseTextStyle ?? DefaultTextStyle.of(context).style.copyWith(fontSize: 14);
  }

  @override
  Widget build(BuildContext context) {
    if (block.isCodeBlock) {
      return _buildCodeBlock(context);
    }
    switch (block.blockTag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return _buildHeading(context);
      case 'hr':
        return const Divider(height: 32);
      case 'blockquote':
        return _buildBlockquote(context);
      case 'li':
        return _buildListItem(context);
      case 'table_row':
        return _buildTableRow(context);
      case 'math_block':
        return _buildMathBlock(context);
      case 'footnote_def':
        return _buildFootnoteDef(context);
      default:
        return _buildParagraphLike(context);
    }
  }

  Widget _buildParagraphLike(BuildContext context) {
    final style = _resolveBaseStyle(context);
    final spanBuilder =
        inlineBuilderOverride ??
        InlineSpanBuilder(
          InlineSpanBuilderContext(baseStyle: style, onTapLink: onTapLink),
        );
    final span = spanBuilder.build(block.inlines);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(span),
    );
  }

  Widget _buildHeading(BuildContext context) {
    final level = int.tryParse(block.blockTag.substring(1)) ?? 1;
    final style = _resolveBaseStyle(
      context,
    ).copyWith(fontSize: 26 - (level * 2.0), fontWeight: FontWeight.bold);
    final spanBuilder =
        inlineBuilderOverride ??
        InlineSpanBuilder(
          InlineSpanBuilderContext(baseStyle: style, onTapLink: onTapLink),
        );
    final span = spanBuilder.build(block.inlines);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text.rich(span),
    );
  }

  Widget _buildBlockquote(BuildContext context) {
    // The leaf is likely a paragraph inside blockquote so show indicator.
    final style = _resolveBaseStyle(context).copyWith();
    final spanBuilder =
        inlineBuilderOverride ??
        InlineSpanBuilder(
          InlineSpanBuilderContext(baseStyle: style, onTapLink: onTapLink),
        );
    final span = spanBuilder.build(block.inlines);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey.withAlpha(80), width: 4)),
        color: Colors.grey.withAlpha(40),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Text.rich(span),
    );
  }

  Widget _buildCodeBlock(BuildContext context) {
    final text = block.rawCode ?? '';
    final lang = block.codeLanguage;
    return _HighlightedCodeBlock(language: lang ?? '', code: text);
  }

  Widget _buildListItem(BuildContext context) {
    final style = _resolveBaseStyle(context);
    final spanBuilder =
        inlineBuilderOverride ??
        InlineSpanBuilder(
          InlineSpanBuilderContext(baseStyle: style, onTapLink: onTapLink),
        );
    final span = spanBuilder.build(block.inlines);
    final listType = block.meta?['listType'] as String? ?? 'ul';
    final depth = (block.meta?['depth'] as int? ?? 0).clamp(0, 10);
    final order = block.meta?['order'] as int?;
    final bullet = listType == 'ol' ? '${order ?? 1}.' : '\u2022';
    return Padding(
      padding: EdgeInsets.only(left: 12.0 * depth + 8, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(bullet, style: style.copyWith(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text.rich(span)),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext context) {
    final isHeader = block.meta?['isHeader'] == true;
    final cells = block.tableCells ?? const [];
    final base = _resolveBaseStyle(context);
    final spanBuilder =
        inlineBuilderOverride ??
        InlineSpanBuilder(
          InlineSpanBuilderContext(baseStyle: base, onTapLink: onTapLink),
        );
    final bg = isHeader ? Colors.grey.withAlpha(40) : Colors.transparent;
    final borderColor = Colors.grey.withAlpha(80);
    final cellAlign =
        (block.meta?['cellAlign'] as List?)?.cast<String>() ??
        List.filled(cells.length, 'left');
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text.rich(
                  spanBuilder.build(cells[i]),
                  textAlign: () {
                    switch (cellAlign[i]) {
                      case 'center':
                        return TextAlign.center;
                      case 'right':
                        return TextAlign.end;
                      default:
                        return TextAlign.start;
                    }
                  }(),
                  style: isHeader ? base.copyWith(fontWeight: FontWeight.bold) : base,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMathBlock(BuildContext context) {
    final style = _resolveBaseStyle(context).copyWith(fontSize: 16);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(40),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.withAlpha(80)),
      ),
      child: Align(
        alignment: Alignment.center,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            block.math ?? '',
            mathStyle: MathStyle.display,
            textStyle: style,
          ),
        ),
      ),
    );
  }

  Widget _buildFootnoteDef(BuildContext context) {
    final style = _resolveBaseStyle(context).copyWith(fontSize: 12);
    final spanBuilder =
        inlineBuilderOverride ??
        InlineSpanBuilder(
          InlineSpanBuilderContext(baseStyle: style, onTapLink: onTapLink),
        );
    final span = spanBuilder.build(block.inlines);
    final label = block.footnoteId ?? '';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: style.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withOpacity(.7),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text.rich(span)),
        ],
      ),
    );
  }
}

class _HighlightedCodeBlock extends StatefulWidget {
  final String language;
  final String code;
  const _HighlightedCodeBlock({required this.language, required this.code});
  @override
  State<_HighlightedCodeBlock> createState() => _HighlightedCodeBlockState();
}

class _HighlightedCodeBlockState extends State<_HighlightedCodeBlock> {
  late List<hl.Node> _nodes;
  bool _copied = false;
  String langLabel = '';

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant _HighlightedCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code || oldWidget.language != widget.language) {
      _parse();
    }
  }

  void _parse() {
    final rawLang = widget.language.trim();
    final lang = _normalizeLang(rawLang);
    langLabel = lang;
    try {
      final res = hl.highlight.parse(
        widget.code.trimRight(),
        language: (lang.isEmpty) ? null : lang,
      );
      _nodes = res.nodes ?? const [];
    } catch (e) {
      // Any parsing exception -> treat as plain text to avoid crashes.
      _nodes = [hl.Node(value: widget.code)];
    }
  }

  String _normalizeLang(String input) {
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
        return l.isEmpty ? 'plaintext' : l;
    }
  }

  List<TextSpan> _toTextSpans(List<hl.Node> nodes, Map<String, TextStyle> theme) {
    final spans = <TextSpan>[];
    for (final n in nodes) {
      if (n.value != null) {
        final style = n.className != null ? theme[n.className!] : null;
        spans.add(TextSpan(text: n.value, style: style));
      } else if (n.children != null) {
        final style = n.className != null ? theme[n.className!] : null;
        spans.add(TextSpan(style: style, children: _toTextSpans(n.children!, theme)));
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeMap = isDark ? atomOneDarkTheme : atomOneLightTheme;
    final codeStyle = TextStyle(
      fontFamilyFallback: const [
        'MapleMono',
        'Menlo',
        'Consolas',
        'Roboto Mono',
        'Courier New',
        'monospace',
      ],
      fontSize: 13,
      height: 1.4,
      color: (isDark ? Colors.white : Colors.black87),
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(40),
        border: Border.all(color: Colors.grey.withAlpha(80)),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 2),
            child: Row(
              children: [
                Expanded(
                  child: SelectionContainer.disabled(
                    child: Text(
                      langLabel.isEmpty
                          ? ''
                          : langLabel[0].toUpperCase() + langLabel.substring(1),
                      style: codeStyle.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _copied ? 'Copied' : 'Copy',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: widget.code));
                    if (mounted) {
                      setState(() => _copied = true);
                      Future.delayed(const Duration(milliseconds: 1500), () {
                        if (mounted) setState(() => _copied = false);
                      });
                    }
                  },
                  icon: Icon(_copied ? Icons.check : Icons.copy, size: 14),
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  color: codeStyle.color,
                  splashRadius: 14,
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            primary: false,
            
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Text.rich(
              TextSpan(style: codeStyle, children: _toTextSpans(_nodes, themeMap)),
            ),
          ),
        ],
      ),
    );
  }
}
