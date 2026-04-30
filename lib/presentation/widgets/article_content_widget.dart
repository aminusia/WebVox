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
  ArticleContentWidgetState createState() => ArticleContentWidgetState();
}

class ArticleContentWidgetState extends State<ArticleContentWidget> {
  /// Stable key placed on the section widget that contains the active TTS word.
  /// Allows [ensureWordVisible] to scroll exactly to the right sub-section
  /// even when a paragraph is taller than the viewport.
  final GlobalKey _wordSectionKey = GlobalKey();

  /// Approximate character count per rendered section when splitting a long
  /// paragraph for word-level scrollability.
  static const int _kSectionLength = 350;

  /// Split [text] into contiguous (start, end) index pairs, each at most
  /// [_kSectionLength] characters, breaking only at word boundaries.
  static List<(int, int)> _computeSections(String text) {
    if (text.length <= _kSectionLength) return [(0, text.length)];
    final sections = <(int, int)>[];
    int start = 0;
    while (start < text.length) {
      int end = (start + _kSectionLength).clamp(start, text.length);
      if (end < text.length) {
        // Snap to the nearest sentence delimiter before [end].
        final delimiterIdx = _findSentenceDelimiterBefore(text, end, start);
        if (delimiterIdx > start) {
          end = delimiterIdx + 1;
          while (end < text.length && text[end] == ' ') {
            end += 1;
          }
        } else {
          // Fallback to the nearest word boundary before [end].
          final spaceIdx = text.lastIndexOf(' ', end);
          if (spaceIdx > start) end = spaceIdx + 1;
        }
      }
      sections.add((start, end));
      start = end;
    }
    return sections;
  }

  static int _findSentenceDelimiterBefore(String text, int end, int start) {
    for (int i = end - 1; i >= start; i--) {
      final char = text[i];
      if (char == '.' || char == '!' || char == '?') {
        return i;
      }
    }
    return -1;
  }

  /// Scrolls the section containing the active TTS word into the viewport.
  /// No-op when the section is already visible or when TTS is not active.
  void ensureWordVisible() {
    final ctx = _wordSectionKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: 0.5,
    );
  }

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

          // Split the paragraph into sections so the active word can always
          // be scrolled into view via [ensureWordVisible], even when the
          // paragraph is taller than the viewport.
          final sections = _computeSections(displayText);
          final wordSectionIdx = sections.indexWhere(
            (s) => safeStart >= s.$1 && safeStart < s.$2,
          );

          if (wordSectionIdx >= 0) {
            textWidget = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(sections.length, (sIdx) {
                final (sStart, sEnd) = sections[sIdx];
                final sText = displayText.substring(sStart, sEnd);
                final isWordSection = sIdx == wordSectionIdx;

                Widget tw;
                if (isWordSection) {
                  final ls = (safeStart - sStart).clamp(0, sText.length);
                  final le = (safeEnd - sStart).clamp(ls, sText.length);
                  tw = Text.rich(
                    TextSpan(
                      style: bodyStyle,
                      children: [
                        if (ls > 0) TextSpan(text: sText.substring(0, ls)),
                        TextSpan(
                          text: sText.substring(ls, le),
                          style: bodyStyle?.copyWith(
                            color: wordStyle.color,
                            backgroundColor: wordStyle.backgroundColor,
                            decoration: wordStyle.decoration,
                            decorationColor: wordStyle.color,
                          ),
                        ),
                        if (le < sText.length)
                          TextSpan(text: sText.substring(le)),
                      ],
                    ),
                  );
                } else {
                  tw = Text(sText, style: bodyStyle);
                }

                return isWordSection
                    ? KeyedSubtree(key: _wordSectionKey, child: tw)
                    : tw;
              }),
            );
          } else {
            // Fallback: render as a single rich text (original behaviour).
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
          }
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
