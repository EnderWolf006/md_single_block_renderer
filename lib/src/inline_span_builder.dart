import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:md_single_block_renderer/src/selectable_adapter.dart';
import 'block.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:extended_image/extended_image.dart';

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
  // Keep recognizers alive for the lifetime of this builder instance so that
  // link taps work reliably when spans are rebuilt. Otherwise creating a new
  // TapGestureRecognizer each build without holding a reference can lead to
  // it being disposed early by the framework's gesture arena when the
  // TextSpan tree is replaced.
  final List<TapGestureRecognizer> _linkRecognizers = [];

  void dispose() {
    for (final r in _linkRecognizers) {
      r.dispose();
    }
    _linkRecognizers.clear();
  }

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
      case 'image':
        final src = node.data?['src'] as String? ?? '';
        final alt = node.data?['alt'] as String? ?? '';
        // Use a WidgetSpan so images flow inline but can expand vertically.
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _ImageView(imageUrl: src, alt: alt, baseStyle: ctx.baseStyle),
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
        if (url == null) {
          return TextSpan(children: node.children.map(_convert).toList());
        }
        final recognizer = TapGestureRecognizer()..onTap = () => ctx.onTapLink?.call(url);
        _linkRecognizers.add(recognizer);
        // Apply link styling to all descendant spans by wrapping them in a parent span.
        return TextSpan(
          style: ctx.baseStyle.merge(
            const TextStyle(color: Colors.blue),
          ),
          children: node.children.isEmpty
              ? [TextSpan(text: url, recognizer: recognizer)]
              : node.children.map((c) {
                  final converted = _convert(c);
                  // Only attach recognizer to leaf TextSpans so selection works.
                  if (converted is TextSpan) {
                    return TextSpan(
                      text: converted.text,
                      style: converted.style,
                      children: converted.children,
                      recognizer: recognizer,
                    );
                  }
                  return converted;
                }).toList(),
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
          child: SelectableAdapter(
            selectedText: ' $processed ',
            child: SizedBox(
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

/// Simple image view used for inline markdown images. Provides basic loading,
/// error, and alt-text fallback. Height is capped for layout safety.
class _ImageView extends StatelessWidget {
  final String imageUrl;
  final String alt;
  final TextStyle baseStyle;
  const _ImageView({required this.imageUrl, required this.alt, required this.baseStyle});

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(alt, style: baseStyle.copyWith(fontStyle: FontStyle.italic)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: SelectableAdapter(
        selectedText: '\n[$alt]($imageUrl)\n',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ExtendedImage.network(
            imageUrl,
            height: 240,
            fit: BoxFit.contain,
            cache: true,
            loadStateChanged: (state) {
              switch (state.extendedImageLoadState) {
                case LoadState.loading:
                  return Container(
                    width: 240,
                    height: 240,
                    alignment: Alignment.center,
                    color: Colors.grey.withAlpha(30),
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                case LoadState.completed:
                  return null; // default rendering
                case LoadState.failed:
                  return Container(
                    width: 240,
                    height: 240,
                    alignment: Alignment.center,
                    color: Colors.grey.withAlpha(30),
                    child: Icon(
                      Icons.broken_image,
                      size: 40,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(.6),
                    ),
                  );
              }
            },
          ),
        ),
      ),
    );
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
