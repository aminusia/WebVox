class Article {
  final String id;
  final String url;
  final String title;
  final String content; // paragraphs joined with \n\n
  final String? author;
  final String language;
  final int estimatedReadTime;
  final bool isBookmarked;
  final int createdAt; // millisecondsSinceEpoch
  final String? prevUrl;
  final String? nextUrl;
  final String? homeUrl;

  const Article({
    required this.id,
    required this.url,
    required this.title,
    required this.content,
    this.author,
    required this.language,
    required this.estimatedReadTime,
    required this.isBookmarked,
    required this.createdAt,
    this.prevUrl,
    this.nextUrl,
    this.homeUrl,
  });

  List<String> get paragraphs =>
      content.split('\n\n').where((p) => p.trim().isNotEmpty).toList();

  Article copyWith({
    String? id,
    String? url,
    String? title,
    String? content,
    String? author,
    String? language,
    int? estimatedReadTime,
    bool? isBookmarked,
    int? createdAt,
    String? prevUrl,
    String? nextUrl,
    String? homeUrl,
  }) {
    return Article(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      content: content ?? this.content,
      author: author ?? this.author,
      language: language ?? this.language,
      estimatedReadTime: estimatedReadTime ?? this.estimatedReadTime,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      createdAt: createdAt ?? this.createdAt,
      prevUrl: prevUrl ?? this.prevUrl,
      nextUrl: nextUrl ?? this.nextUrl,
      homeUrl: homeUrl ?? this.homeUrl,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'url': url,
    'title': title,
    'content': content,
    'author': author,
    'language': language,
    'estimated_read_time': estimatedReadTime,
    'is_bookmarked': isBookmarked ? 1 : 0,
    'created_at': createdAt,
    'prev_url': prevUrl,
    'next_url': nextUrl,
    'home_url': homeUrl,
  };

  factory Article.fromMap(Map<String, dynamic> map) => Article(
    id: map['id'] as String,
    url: map['url'] as String,
    title: map['title'] as String,
    content: map['content'] as String,
    author: map['author'] as String?,
    language: map['language'] as String? ?? 'en-US',
    estimatedReadTime: map['estimated_read_time'] as int? ?? 0,
    isBookmarked: (map['is_bookmarked'] as int? ?? 0) == 1,
    createdAt: map['created_at'] as int,
    prevUrl: map['prev_url'] as String?,
    nextUrl: map['next_url'] as String?,
    homeUrl: map['home_url'] as String?,
  );
}
