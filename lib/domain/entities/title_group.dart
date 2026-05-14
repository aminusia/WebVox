import 'package:webreader/domain/entities/article.dart';

/// A group of [Article]s that share the same book / series title.
class TitleGroup {
  final String titleId;
  final String titleName;
  final String websiteDomain;
  final List<Article> articles;

  const TitleGroup({
    required this.titleId,
    required this.titleName,
    required this.websiteDomain,
    required this.articles,
  });

  TitleGroup copyWith({String? titleName, List<Article>? articles}) {
    return TitleGroup(
      titleId: titleId,
      titleName: titleName ?? this.titleName,
      websiteDomain: websiteDomain,
      articles: articles ?? this.articles,
    );
  }
}
