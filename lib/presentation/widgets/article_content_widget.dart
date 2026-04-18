import 'package:flutter/material.dart';

class ArticleContentWidget extends StatefulWidget {
  final List<String> paragraphs;
  final double fontSize;

  /// Index of the paragraph currently being spoken (-1 = none).
  final int highlightedIndex;

  /// Char offset of the highlighted word start within [highlightedIndex]'s
  /// display text. -1 when no word is highlighted.
  final int wordStart;

  /// Char offset of the highlighted word end (exclusive). -1 when none.
  final int wordEnd;

  /// Called when the user taps a word.  Provides the paragraph index and the
  /// char offset within that paragraph's display text.
  final void Function(int paragraphIndex, int charOffset)? onWordTap;

  /// GlobalKeys for each paragraph to support precise scrolling.
  final List<GlobalKey>? paragraphKeys;

  const ArticleContentWidget({
    super.key,
    required this.paragraphs,
    required this.fontSize,
    required this.highlightedIndex,
    this.wordStart = -1,
    this.wordEnd = -1,
    this.onWordTap,
    this.paragraphKeys,
  });

  @override
  State<ArticleContentWidget> createState() => _ArticleContentWidgetState();
}

class _ArticleContentWidgetState extends State<ArticleContentWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(ArticleContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When highlight changes, trigger fade animation
    if (oldWidget.highlightedIndex != widget.highlightedIndex) {
      _fadeController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(widget.paragraphs.length, (i) {
        final raw = widget.paragraphs[i];
        final isHeading = raw.startsWith('## ');
        final isHighlighted = i == widget.highlightedIndex;
        final displayText = isHeading ? raw.substring(3) : raw;

        final headingStyle = tt.titleMedium?.copyWith(
          fontSize: widget.fontSize + 2,
          fontWeight: FontWeight.bold,
          color: cs.onSurface,
        );
        final bodyStyle = tt.bodyLarge?.copyWith(
          fontSize: widget.fontSize,
          height: 1.7,
          color: cs.onSurface,
        );

        // Build the text content (with optional word highlight)
        Widget textWidget;
        if (isHighlighted &&
            !isHeading &&
            widget.wordStart >= 0 &&
            widget.wordEnd > widget.wordStart &&
            widget.wordEnd <= displayText.length) {
          final safeStart = widget.wordStart.clamp(0, displayText.length);
          final safeEnd = widget.wordEnd.clamp(safeStart, displayText.length);
          textWidget = Text.rich(
            TextSpan(
              style: bodyStyle,
              children: [
                TextSpan(text: displayText.substring(0, safeStart)),
                TextSpan(
                  text: displayText.substring(safeStart, safeEnd),
                  style: bodyStyle?.copyWith(
                    backgroundColor: cs.primaryContainer,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                TextSpan(text: displayText.substring(safeEnd)),
              ],
            ),
          );
        } else {
          textWidget = Text(
            displayText,
            style: isHeading ? headingStyle : bodyStyle,
          );
        }

        // Wrap with AnimatedOpacity for fade effect
        Widget containerChild = LayoutBuilder(
          builder:
              (ctx, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp:
                    widget.onWordTap == null
                        ? null
                        : (details) {
                          final style =
                              (isHeading ? headingStyle : bodyStyle) ??
                              const TextStyle();
                          final painter = TextPainter(
                            text: TextSpan(text: displayText, style: style),
                            textDirection: TextDirection.ltr,
                          )..layout(maxWidth: constraints.maxWidth);
                          final charOffset =
                              painter
                                  .getPositionForOffset(details.localPosition)
                                  .offset;
                          painter.dispose();
                          widget.onWordTap!(i, charOffset);
                        },
                child: textWidget,
              ),
        );

        // Animate highlight appearance/disappearance
        if (isHighlighted) {
          containerChild = AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: containerChild,
            ),
          );
        }

        return Padding(
          key: widget.paragraphKeys?[i],
          padding: EdgeInsets.only(bottom: isHeading ? 4 : 14),
          child: containerChild,
        );
      }),
    );
  }
}
