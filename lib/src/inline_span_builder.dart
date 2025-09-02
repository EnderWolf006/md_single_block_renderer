import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'block.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Convert a list of BlockInlineNode (already parsed off the UI thread ideally)
/// into a TextSpan tree.
class InlineSpanBuilderContext {
  final TextStyle baseStyle;
  final void Function(String url)? onTapLink;
  InlineSpanBuilderContext({required this.baseStyle, this.onTapLink});
}

class InlineSpanBuilder {
  final InlineSpanBuilderContext ctx;
  InlineSpanBuilder(this.ctx);

  TextSpan build(List<BlockInlineNode> nodes) {
    return TextSpan(style: ctx.baseStyle, children: nodes.map(_convert).toList());
  }

  InlineSpan _convert(BlockInlineNode node) {
    switch (node.type) {
      case 'text':
        return TextSpan(text: node.text);
      case 'em':
        return TextSpan(
          style: ctx.baseStyle.merge(const TextStyle(fontStyle: FontStyle.italic)),
          children: node.children.map(_convert).toList(),
        );
      case 'strong':
        return TextSpan(
          style: ctx.baseStyle.merge(const TextStyle(fontWeight: FontWeight.bold)),
          children: node.children.map(_convert).toList(),
        );
      case 'code':
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.grey.withAlpha(40),
              border: Border.all(color: Colors.grey.withAlpha(80)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              node.text ?? '',
              style: ctx.baseStyle.copyWith(
                fontFamilyFallback: [
                  'MapleMono',
                  'Menlo',
                  'Consolas',
                  'Roboto Mono',
                  'Courier New',
                  'monospace',
                ],
                fontSize: ctx.baseStyle.fontSize != null
                    ? (ctx.baseStyle.fontSize! * 0.9)
                    : null,
              ),
            ),
          ),
        );
      case 'link':
        final url = node.data?['href'] as String?;
        return TextSpan(
          style: ctx.baseStyle.merge(
            const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
          ),
          recognizer: url == null
              ? null
              : (TapGestureRecognizer()
                  ..onTap = () {
                    ctx.onTapLink?.call(url);
                  }),
          children: node.children.map(_convert).toList(),
        );
      case 'del':
        return TextSpan(
          style: ctx.baseStyle.merge(
            const TextStyle(decoration: TextDecoration.lineThrough),
          ),
          children: node.children.map(_convert).toList(),
        );
      case 'math':
        // inline math
        final raw = node.text ?? '';
        final processed = _preprocessMath(raw);
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Math.tex(
            processed,
            mathStyle: MathStyle.text,
            textStyle: ctx.baseStyle,
            onErrorFallback: (err) => Text(
              err.message,
              style: ctx.baseStyle.merge(
                const TextStyle(color: Colors.red, fontSize: 11),
              ),
            ),
          ),
        );
      case 'footnote_ref':
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Text(
              node.text ?? '',
              style: ctx.baseStyle.merge(
                TextStyle(
                  fontSize: (ctx.baseStyle.fontSize ?? 14) * 0.65,
                  color: Colors.blueGrey,
                ),
              ),
            ),
          ),
        );
      default:
        return TextSpan(children: node.children.map(_convert).toList());
    }
  }
}

/// Very small subset translator for mhchem \ce{...} macro to ordinary TeX
/// Supports:
///  - charges like Hg^2+  -> Hg^{2+}
///  - reaction arrows A ->[X] B ->[Y] C converted to A \xrightarrow{X} B \xrightarrow{Y} C
String _preprocessMath(String input) {
  final cePattern = RegExp(r'\\ce\{([^}]*)\}');
  return input.replaceAllMapped(cePattern, (m) {
    String inner = m.group(1)!;
    // Convert charges pattern Element^2+ or Element^2-
    inner = inner.replaceAllMapped(
      RegExp(r'([A-Za-z]+)\^(\d+)([+-])'),
      (mm) => '${mm[1]}^{${mm[2]}${mm[3]}}',
    );
    // Arrows with annotation ->[X]
    inner = inner.replaceAllMapped(
      RegExp(r'->\[([^\]]+)\]'),
      (mm) => '\\xrightarrow{${mm[1]}}',
    );
    inner = inner.replaceAllMapped(
      RegExp(r'<-\[([^\]]+)\]'),
      (mm) => '\\xleftarrow{${mm[1]}}',
    );
    return inner;
  });
}
