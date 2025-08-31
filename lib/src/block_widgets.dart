import 'package:flutter/material.dart';
import 'block.dart';
import 'inline_span_builder.dart';
import 'package:flutter_math_fork/flutter_math.dart';

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
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
      padding: EdgeInsets.fromLTRB(level * 2.0 + 4, 12, 8, 4),
      child: Text.rich(span),
    );
  }

  Widget _buildBlockquote(BuildContext context) {
    // The leaf is likely a paragraph inside blockquote so show indicator.
    final style = _resolveBaseStyle(context).copyWith(
      fontStyle: FontStyle.italic,
      color: Theme.of(context).colorScheme.onSurface.withOpacity(.85),
    );
    final spanBuilder =
        inlineBuilderOverride ??
        InlineSpanBuilder(
          InlineSpanBuilderContext(baseStyle: style, onTapLink: onTapLink),
        );
    final span = spanBuilder.build(block.inlines);
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey.shade400, width: 4)),
        color: Colors.grey.shade100,
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(span),
    );
  }

  Widget _buildCodeBlock(BuildContext context) {
    final text = block.rawCode ?? '';
    final lang = block.codeLanguage;
    final style = _resolveBaseStyle(
      context,
    ).copyWith(fontFamily: 'monospace', fontSize: 12);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lang != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                lang,
                style: style.copyWith(color: Colors.white70, fontSize: 10),
              ),
            ),
          Text(text, style: style.copyWith(color: Colors.white)),
        ],
      ),
    );
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
      padding: EdgeInsets.only(left: 12.0 * depth + 8, right: 8, top: 2, bottom: 2),
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
    final bg = isHeader
        ? Theme.of(context).colorScheme.primary.withOpacity(.08)
        : Colors.transparent;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final cell in cells)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text.rich(
                  spanBuilder.build(cell),
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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blueGrey.withOpacity(.2)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(block.math ?? '', mathStyle: MathStyle.display, textStyle: style),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
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
                color: Colors.blueGrey.shade700,
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
