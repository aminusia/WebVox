import 'package:flutter/material.dart';
import 'package:web_reader/domain/entities/settings.dart';

/// Resolved Flutter-level highlight style, converted from [Settings] fields.
class HighlightStyle {
  final Color color;
  final Color? backgroundColor;
  final TextDecoration decoration;

  const HighlightStyle({
    required this.color,
    this.backgroundColor,
    this.decoration = TextDecoration.none,
  });

  static const HighlightStyle defaultParagraph = HighlightStyle(
    color: Color(0xFF2196F3), // Colors.blue
    decoration: TextDecoration.none,
  );

  static const HighlightStyle defaultWord = HighlightStyle(
    color: Color(0xFFB8860B),
    decoration: TextDecoration.underline,
  );

  static HighlightStyle fromSettings({
    required int colorValue,
    required int? backgroundValue,
    required HighlightDecoration decoration,
  }) {
    return HighlightStyle(
      color: Color(colorValue),
      backgroundColor: backgroundValue != null ? Color(backgroundValue) : null,
      decoration: _toTextDecoration(decoration),
    );
  }

  static TextDecoration _toTextDecoration(HighlightDecoration d) {
    switch (d) {
      case HighlightDecoration.underline:
        return TextDecoration.underline;
      case HighlightDecoration.lineThrough:
        return TextDecoration.lineThrough;
      case HighlightDecoration.overline:
        return TextDecoration.overline;
      case HighlightDecoration.none:
        return TextDecoration.none;
    }
  }
}

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

  /// Called when the user taps a paragraph. Provides the paragraph index.
  final void Function(int paragraphIndex)? onTap;

  /// GlobalKeys for each paragraph to support precise scrolling.
  final List<GlobalKey>? paragraphKeys;

  /// Style applied to the currently highlighted paragraph.
  final HighlightStyle paragraphHighlightStyle;

  /// Style applied to the currently highlighted word.
  final HighlightStyle wordHighlightStyle;

  const ArticleContentWidget({
    super.key,
    required this.paragraphs,
    required this.fontSize,
    required this.highlightedIndex,
    this.wordStart = -1,
    this.wordEnd = -1,
    this.onTap,
    this.paragraphKeys,
    this.paragraphHighlightStyle = HighlightStyle.defaultParagraph,
    this.wordHighlightStyle = HighlightStyle.defaultWord,
  });

  @override
  State<ArticleContentWidget> createState() => _ArticleContentWidgetState();
}

class _ArticleContentWidgetState extends State<ArticleContentWidget> {
  @override
  Widget build(BuildContext context) {
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
          color: isHighlighted ? widget.paragraphHighlightStyle.color : null,
          backgroundColor:
              isHighlighted
                  ? widget.paragraphHighlightStyle.backgroundColor
                  : null,
          decoration:
              isHighlighted ? widget.paragraphHighlightStyle.decoration : null,
          decorationColor:
              isHighlighted ? widget.paragraphHighlightStyle.color : null,
        );
        final bodyStyle = tt.bodyLarge?.copyWith(
          fontSize: widget.fontSize,
          height: 1.7,
          color: isHighlighted ? widget.paragraphHighlightStyle.color : null,
          backgroundColor:
              isHighlighted
                  ? widget.paragraphHighlightStyle.backgroundColor
                  : null,
          decoration:
              isHighlighted ? widget.paragraphHighlightStyle.decoration : null,
          decorationColor:
              isHighlighted ? widget.paragraphHighlightStyle.color : null,
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
          final wordStyle = widget.wordHighlightStyle;
          textWidget = Text.rich(
            TextSpan(
              style: bodyStyle,
              children: [
                TextSpan(text: displayText.substring(0, safeStart)),
                TextSpan(
                  text: displayText.substring(safeStart, safeEnd),
                  style: bodyStyle?.copyWith(
                    color: wordStyle.color,
                    backgroundColor: wordStyle.backgroundColor,
                    decoration: wordStyle.decoration,
                    decorationColor: wordStyle.color,
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

        Widget containerChild = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap == null ? null : () => widget.onTap!(i),
          child: textWidget,
        );

        return Padding(
          key: widget.paragraphKeys?[i],
          padding: EdgeInsets.only(bottom: isHeading ? 4 : 14),
          child: containerChild,
        );
      }),
    );
  }
}
