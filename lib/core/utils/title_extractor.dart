/// Utility helpers for extracting book/series titles and website domains
/// from raw article titles and URLs.
class TitleExtractor {
  // Matches " - Chapter 3", ": Part II", ", Vol. 5", " Ch.12", etc.
  static final _chapterPattern = RegExp(
    r'^(?: - | # |: )$|\s*[-:,–—]?\s*\b(chapter|part|episode|section|volume|ch\.?|ep\.?|vol\.?)\s*#?\s*[\dIVXivx]+.*$',
    caseSensitive: false,
  );

  /// Strip chapter / part / episode info from an article title to get the
  /// parent book or series title.
  static String extractBookTitle(String articleTitle) {
    final stripped = articleTitle.replaceAll(_chapterPattern, '').trim();
    return stripped.isEmpty ? articleTitle : stripped;
  }

  /// Extract a clean domain string from a URL (strips "www.").
  static String extractDomain(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    final host = uri.host;
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}
