class ReadingState {
  final String articleId;
  final double scrollPosition; // 0.0 – 1.0
  final int lastReadIndex; // paragraph index for TTS resume
  final int lastWordOffset; // char offset within paragraph for TTS resume

  const ReadingState({
    required this.articleId,
    required this.scrollPosition,
    required this.lastReadIndex,
    this.lastWordOffset = 0,
  });

  ReadingState copyWith({
    String? articleId,
    double? scrollPosition,
    int? lastReadIndex,
    int? lastWordOffset,
  }) => ReadingState(
    articleId: articleId ?? this.articleId,
    scrollPosition: scrollPosition ?? this.scrollPosition,
    lastReadIndex: lastReadIndex ?? this.lastReadIndex,
    lastWordOffset: lastWordOffset ?? this.lastWordOffset,
  );

  Map<String, dynamic> toMap() => {
    'article_id': articleId,
    'scroll_position': scrollPosition,
    'last_read_index': lastReadIndex,
    'last_word_offset': lastWordOffset,
  };

  factory ReadingState.fromMap(Map<String, dynamic> map) => ReadingState(
    articleId: map['article_id'] as String,
    scrollPosition: (map['scroll_position'] as num).toDouble(),
    lastReadIndex: map['last_read_index'] as int,
    lastWordOffset: (map['last_word_offset'] as int?) ?? 0,
  );
}
