import 'package:flutter/material.dart';
import 'block.dart';
import 'inline_span_builder.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'block.dart' show CodeToken; // ensure CodeToken visible
import 'sync_scroll_manager.dart';
import 'code_width_manager.dart';
import 'no_overscroll_physics.dart';

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

    // Check if this is part of a grouped code block
    final isFirstInGroup = block.meta?['isFirstInGroup'] == true;
    final isLastInGroup = block.meta?['isLastInGroup'] == true;
    final isMiddleInGroup = block.meta?['isMiddleInGroup'] == true;

    return _HighlightedCodeBlock(
      language: lang ?? '',
      code: text,
      tokens: block.codeTokens,
      showHeader: isFirstInGroup,
      showTopRounding: isFirstInGroup,
      showBottomRounding: isLastInGroup,
      isMiddleBlock: isMiddleInGroup,
      fullCodeContent: block.meta?['fullCodeContent'] as String?,
      groupId: block.meta?['codeBlockGroupId'] as String?,
      groupIndex: block.meta?['blockIndex'] as int?,
      precomputedLongestLine: block.meta?['fullCodeLongestLine'] as String?,
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
    final bg = isHeader ? Colors.grey.withValues(alpha: 0.16) : Colors.transparent;
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

// Fallback minimal theme maps if flutter_highlight themes not found in environment.
const _fallbackLightTheme = <String, TextStyle>{};
const _fallbackDarkTheme = <String, TextStyle>{};

class _HighlightedCodeBlock extends StatefulWidget {
  final String language;
  final String code;
  final List<CodeToken>? tokens; // precomputed
  final bool showHeader;
  final bool showTopRounding;
  final bool showBottomRounding;
  final bool isMiddleBlock;
  final String? fullCodeContent; // Full code content for copy functionality
  final String? groupId; // code block group id for scroll sync
  final int? groupIndex; // index inside group (for key stability)
  final String? precomputedLongestLine;

  const _HighlightedCodeBlock({
    required this.language,
    required this.code,
    this.tokens,
    this.showHeader = true,
    this.showTopRounding = true,
    this.showBottomRounding = true,
    this.isMiddleBlock = false,
    this.fullCodeContent,
    this.groupId,
    this.groupIndex,
    this.precomputedLongestLine,
  });

  @override
  State<_HighlightedCodeBlock> createState() => _HighlightedCodeBlockState();
}

class _HighlightedCodeBlockState extends State<_HighlightedCodeBlock> {
  late List<CodeToken> _tokens;
  bool _copied = false;
  String langLabel = '';
  ScrollController? _hController; // horizontal scroll controller
  double? _groupLineWidth; // cached unified width
  bool _measured = false;

  @override
  void initState() {
    super.initState();
    _initTokens();
    _maybeInitScrollSync();
  }

  void _maybeInitScrollSync() {
    if (widget.groupId == null) return;
    _hController = ScrollController();
    // Register with sync manager after first frame to ensure hasClients
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SyncScrollManager.instance.register(widget.groupId!, _hController!);
    });
  }

  void _initTokens() {
    final rawLang = widget.language.trim();
    langLabel = _normalizeLang(rawLang);
    _tokens = widget.tokens ?? [CodeToken(widget.code, null)];
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

  List<TextSpan> _tokensToSpans(List<CodeToken> tokens, Map<String, TextStyle> theme) {
    return tokens
        .map(
          (t) => TextSpan(
            text: t.text,
            style: t.className != null ? theme[t.className!] : null,
          ),
        )
        .toList();
  }

  void _measureIfNeeded(TextStyle codeStyle) {
    if (_measured) return;
    final groupId = widget.groupId;
    if (groupId == null) return;
    final existing = CodeWidthManager.instance.getGroupWidth(groupId);
    if (existing != null) {
      _groupLineWidth = existing;
      _measured = true;
      return;
    }
    final longest = widget.precomputedLongestLine;
    if (longest == null) {
      _measured = true; // nothing to do
      return;
    }
    // Defer actual layout cost to post-frame to avoid blocking first paint
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tp = TextPainter(textDirection: TextDirection.ltr, maxLines: 1);
      tp.text = TextSpan(text: longest.isEmpty ? ' ' : longest, style: codeStyle);
      tp.layout();
      final w = tp.width;
      if (CodeWidthManager.instance.updateWidth(groupId, w)) {
        if (mounted) {
          setState(() {
            _groupLineWidth = w;
            _measured = true;
          });
        }
      } else {
        _groupLineWidth = CodeWidthManager.instance.getGroupWidth(groupId);
        _measured = true;
      }
    });
  }

  void _ensureSynced() {
    final gid = widget.groupId;
    if (gid == null) return;
    final ctrl = _hController;
    if (ctrl == null || !ctrl.hasClients) return;
    final cached = SyncScrollManager.instance.cachedOffset(gid);
    if (cached != null && (ctrl.offset - cached).abs() > 0.5) {
      // jumpTo to avoid animation
      ctrl.jumpTo(cached.clamp(0.0, ctrl.position.maxScrollExtent));
    }
  }

  @override
  void didUpdateWidget(covariant _HighlightedCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.language != widget.language ||
        oldWidget.tokens != widget.tokens) {
      _initTokens();
    }
    if (oldWidget.groupId != widget.groupId) {
      // group changed: unregister old, register new
      if (oldWidget.groupId != null && _hController != null) {
        SyncScrollManager.instance.unregister(oldWidget.groupId!, _hController!);
      }
      if (widget.groupId != null) {
        _hController ??= ScrollController();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          SyncScrollManager.instance.register(widget.groupId!, _hController!);
        });
      }
    }
    // Always attempt to resync after rebuild if still same group
    if (widget.groupId != null && oldWidget.groupId == widget.groupId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSynced());
    }
  }

  @override
  void dispose() {
    if (widget.groupId != null && _hController != null) {
      SyncScrollManager.instance.unregister(widget.groupId!, _hController!);
    }
    _hController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeMap = isDark
        ? (() {
            try {
              return atomOneDarkTheme;
            } catch (_) {
              return _fallbackDarkTheme;
            }
          }())
        : (() {
            try {
              return atomOneLightTheme;
            } catch (_) {
              return _fallbackLightTheme;
            }
          }());
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

    // Determine border radius based on position
    BorderRadius? borderRadius;
    if (widget.showTopRounding && widget.showBottomRounding) {
      // Single block or only block
      borderRadius = BorderRadius.circular(6);
    } else if (widget.showTopRounding) {
      // First block in group
      borderRadius = const BorderRadius.only(
        topLeft: Radius.circular(6),
        topRight: Radius.circular(6),
      );
    } else if (widget.showBottomRounding) {
      // Last block in group
      borderRadius = const BorderRadius.only(
        bottomLeft: Radius.circular(6),
        bottomRight: Radius.circular(6),
      );
    } else {
      // Middle block - no rounding
      borderRadius = BorderRadius.zero;
    }

    // Determine border - middle blocks only have left/right borders
    Border? border = Border(
      left: BorderSide(color: Colors.grey.withAlpha(80)),
      right: BorderSide(color: Colors.grey.withAlpha(80)),
      top: widget.showTopRounding
          ? BorderSide(color: Colors.grey.withAlpha(80))
          : BorderSide.none,
      bottom: widget.showBottomRounding
          ? BorderSide(color: Colors.grey.withAlpha(80))
          : BorderSide.none,
    );

    _measureIfNeeded(codeStyle);
    final contentWidth = _groupLineWidth;

    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSynced());

    return Container(
      width: double.infinity,
      // Remove margin for grouped blocks
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(40),
        border: border,
        borderRadius: borderRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Only show header for first block in group
          if (widget.showHeader)
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
                      // Copy the full code content if available, otherwise copy current block
                      final textToCopy = widget.fullCodeContent ?? widget.code;
                      await Clipboard.setData(ClipboardData(text: textToCopy));
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
            physics: const NoOverscrollPhysics(),
            controller: _hController,
            key: widget.groupId != null && widget.groupIndex != null
                ? PageStorageKey('code-h-${widget.groupId}-${widget.groupIndex}')
                : null,
            primary: false,
            padding: EdgeInsets.fromLTRB(12, 0, 12, widget.showBottomRounding ? 10 : 0),
            child: contentWidth != null
                ? ConstrainedBox(
                    constraints: BoxConstraints(minWidth: contentWidth + 1),
                    child: Text.rich(
                      TextSpan(
                        style: codeStyle,
                        children: () {
                          final spans = _tokensToSpans(_tokens, themeMap);
                          // Append an invisible trailing newline so outer SelectionArea copies a line break
                          // without introducing visible vertical space between grouped blocks.
                          if (!widget.code.endsWith('\n')) {
                            spans.add(
                              TextSpan(
                                text: '\n ',
                                style: codeStyle.copyWith(
                                  fontSize: 0.1, // effectively zero-height
                                  height: 0.1,
                                  color: Colors.transparent,
                                ),
                              ),
                            );
                          } else {
                            // If original already ends with newline, still ensure it's invisible & no extra space
                            // by adding a zero-sized span (no text) to avoid layout changes.
                            spans.add(
                              TextSpan(
                                text: '',
                                style: codeStyle.copyWith(
                                  fontSize: 0.1,
                                  height: 0.1,
                                  color: Colors.transparent,
                                ),
                              ),
                            );
                          }
                          return spans;
                        }(),
                      ),
                    ),
                  )
                : Text.rich(
                    TextSpan(
                      style: codeStyle,
                      children: () {
                        final spans = _tokensToSpans(_tokens, themeMap);
                        if (!widget.code.endsWith('\n')) {
                          spans.add(
                            TextSpan(
                              text: '\n ',
                              style: codeStyle.copyWith(
                                fontSize: 0.1,
                                height: 0.1,
                                color: Colors.transparent,
                              ),
                            ),
                          );
                        } else {
                          spans.add(
                            TextSpan(
                              text: '',
                              style: codeStyle.copyWith(
                                fontSize: 0.1,
                                height: 0.1,
                                color: Colors.transparent,
                              ),
                            ),
                          );
                        }
                        return spans;
                      }(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
