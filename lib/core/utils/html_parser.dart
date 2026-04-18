import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

class ParsedArticle {
  final String title;
  final String? author;
  final String language;
  final List<String> paragraphs;
  final int estimatedReadTime;
  final String? prevUrl;
  final String? nextUrl;
  final String? homeUrl;

  const ParsedArticle({
    required this.title,
    this.author,
    required this.language,
    required this.paragraphs,
    required this.estimatedReadTime,
    this.prevUrl,
    this.nextUrl,
    this.homeUrl,
  });

  String get content => paragraphs.join('\n\n');
}

class HtmlParser {
  static const _removeTags = {
    'script',
    'style',
    'noscript',
    'iframe',
    'nav',
    'header',
    'footer',
    'aside',
    'advertisement',
    'ads',
    'banner',
    'comment',
    'comments',
    'sidebar',
    'widget',
    'related',
    'share',
    'social',
    'popup',
  };

  static const _contentSelectors = [
    '[itemprop="articleBody"]',
    'article',
    '[role="main"]',
    'main',
    '.post-content',
    '.article-content',
    '.entry-content',
    '.content-body',
    '.story-body',
    '.article-body',
    '#content',
    '.content',
    '.post',
  ];

  ParsedArticle parse(String htmlString, String url) {
    final document = html_parser.parse(htmlString);

    // Extract navigation links BEFORE removing elements, since nav/header/footer
    // tags (which are removed) often contain chapter prev/next links.
    final navLinks = _extractNavigationLinks(document, url);

    _removeUnwantedElements(document);

    final title = _extractTitle(document);
    final author = _extractAuthor(document);
    final language = _extractLanguage(document);
    final paragraphs = _extractParagraphs(document);
    final estimatedReadTime = _calcReadTime(paragraphs);

    return ParsedArticle(
      title: title,
      author: author,
      language: language,
      paragraphs: paragraphs,
      estimatedReadTime: estimatedReadTime,
      prevUrl: navLinks['prev'],
      nextUrl: navLinks['next'],
      homeUrl: navLinks['home'],
    );
  }

  void _removeUnwantedElements(Document document) {
    for (final tag in _removeTags) {
      document.querySelectorAll(tag).forEach((el) => el.remove());
    }
    // Remove elements with ad/nav-like classes
    document.querySelectorAll('[class]').forEach((el) {
      final cls = el.attributes['class'] ?? '';
      if (_isNoisyClass(cls)) el.remove();
    });
    document.querySelectorAll('[id]').forEach((el) {
      final id = el.attributes['id'] ?? '';
      if (_isNoisyClass(id)) el.remove();
    });
  }

  bool _isNoisyClass(String cls) {
    const noisy = [
      'ad',
      'ads',
      'advert',
      'advertisement',
      'nav',
      'navigation',
      'sidebar',
      'comment',
      'footer',
      'header',
      'menu',
      'social',
      'share',
      'related',
      'recommended',
      'promo',
      'popup',
      'modal',
      'cookie',
      'banner',
      'newsletter',
    ];
    final lower = cls.toLowerCase();
    return noisy.any(
      (n) =>
          lower == n ||
          lower.contains('-$n') ||
          lower.contains('${n}_') ||
          lower.contains('_$n') ||
          lower.contains('$n-'),
    );
  }

  String _extractTitle(Document document) {
    // Try og:title, twitter:title, then <title>
    final ogTitle =
        document
            .querySelector('meta[property="og:title"]')
            ?.attributes['content'];
    if (ogTitle != null && ogTitle.isNotEmpty) return ogTitle.trim();

    final twitterTitle =
        document
            .querySelector('meta[name="twitter:title"]')
            ?.attributes['content'];
    if (twitterTitle != null && twitterTitle.isNotEmpty) {
      return twitterTitle.trim();
    }

    final h1 = document.querySelector('h1')?.text.trim();
    if (h1 != null && h1.isNotEmpty) return h1;

    return document.querySelector('title')?.text.trim() ?? 'Untitled';
  }

  String? _extractAuthor(Document document) {
    final candidates = [
      document.querySelector('meta[name="author"]')?.attributes['content'],
      document.querySelector('[rel="author"]')?.text,
      document.querySelector('[itemprop="author"]')?.text,
      document.querySelector('.author')?.text,
      document.querySelector('.byline')?.text,
    ];
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }

  String _extractLanguage(Document document) {
    final htmlLang = document.querySelector('html')?.attributes['lang'];
    if (htmlLang != null && htmlLang.isNotEmpty) {
      return _normaliseLang(htmlLang.trim());
    }
    final metaLang =
        document
            .querySelector('meta[http-equiv="Content-Language"]')
            ?.attributes['content'];
    if (metaLang != null && metaLang.isNotEmpty) {
      return _normaliseLang(metaLang.split(',').first.trim());
    }
    return 'en-US';
  }

  String _normaliseLang(String lang) {
    final parts = lang.split(RegExp(r'[-_]'));
    if (parts.isEmpty) return 'en-US';
    final language = parts[0].toLowerCase();
    final region =
        parts.length > 1 ? parts[1].toUpperCase() : _defaultRegion(language);
    return '$language-$region';
  }

  String _defaultRegion(String lang) {
    const map = {
      'en': 'US',
      'de': 'DE',
      'fr': 'FR',
      'es': 'ES',
      'it': 'IT',
      'pt': 'BR',
      'ru': 'RU',
      'zh': 'CN',
      'ja': 'JP',
      'ko': 'KR',
      'ar': 'SA',
      'nl': 'NL',
    };
    return map[lang] ?? lang.toUpperCase();
  }

  List<String> _extractParagraphs(Document document) {
    Element? contentEl;

    for (final selector in _contentSelectors) {
      contentEl = document.querySelector(selector);
      if (contentEl != null) break;
    }
    contentEl ??= document.querySelector('body') ?? document.documentElement;

    if (contentEl == null) return [];
    final paragraphs = <String>[];
    _collectText(contentEl, paragraphs);

    return paragraphs.map((p) => p.trim()).where((p) => p.length > 20).toList();
  }

  void _collectText(Element element, List<String> out) {
    for (final child in element.children) {
      final tag = child.localName?.toLowerCase() ?? '';

      if (_removeTags.contains(tag)) continue;

      if (tag == 'p' || tag == 'blockquote' || tag == 'li') {
        final text = _innerText(child);
        if (text.isNotEmpty) out.add(text);
      } else if (tag == 'h1' ||
          tag == 'h2' ||
          tag == 'h3' ||
          tag == 'h4' ||
          tag == 'h5' ||
          tag == 'h6') {
        final text = _innerText(child);
        if (text.isNotEmpty) out.add('## $text');
      } else if (tag == 'div' || tag == 'section' || tag == 'article') {
        // Only recurse if div contains structural elements
        final hasParagraphs =
            child.querySelector('p, h1, h2, h3, h4, h5, h6, blockquote, li') !=
            null;
        if (hasParagraphs) {
          _collectText(child, out);
        } else {
          final text = _innerText(child);
          if (text.trim().length > 20) out.add(text.trim());
        }
      }
    }
  }

  String _innerText(Element element) {
    return element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  int _calcReadTime(List<String> paragraphs) {
    final wordCount = paragraphs
        .map((p) => p.split(RegExp(r'\s+')).length)
        .fold(0, (a, b) => a + b);
    return (wordCount / 200).ceil(); // 200 WPM average
  }

  Map<String, String?> _extractNavigationLinks(
    Document document,
    String baseUrl,
  ) {
    final result = <String, String?>{'prev': null, 'next': null, 'home': null};
    final baseUri = Uri.parse(baseUrl);

    // Try link elements with rel attributes
    final links = document.querySelectorAll('link[rel]');
    for (final link in links) {
      final rel = link.attributes['rel']?.toLowerCase() ?? '';
      final href = link.attributes['href'];
      if (href == null || href.isEmpty) continue;

      final absoluteUrl = _resolveUrl(href, baseUri);

      if (rel.contains('prev') || rel.contains('previous')) {
        result['prev'] = absoluteUrl;
      } else if (rel.contains('next')) {
        result['next'] = absoluteUrl;
      } else if (rel.contains('home') || rel.contains('index')) {
        result['home'] = absoluteUrl;
      }
    }

    // Also check for navigation links in the content (a tags with common rel patterns)
    final navLinks = document.querySelectorAll('a[rel]');
    for (final link in navLinks) {
      final rel = link.attributes['rel']?.toLowerCase() ?? '';
      final href = link.attributes['href'];
      if (href == null || href.isEmpty) continue;

      final absoluteUrl = _resolveUrl(href, baseUri);

      if (result['prev'] == null &&
          (rel.contains('prev') || rel.contains('previous'))) {
        result['prev'] = absoluteUrl;
      } else if (result['next'] == null && rel.contains('next')) {
        result['next'] = absoluteUrl;
      } else if (result['home'] == null &&
          (rel.contains('home') || rel.contains('index'))) {
        result['home'] = absoluteUrl;
      }
    }

    // Search for navigation links by text content inside anchor elements
    final allLinks = document.querySelectorAll('a[href]');
    for (final link in allLinks) {
      final href = link.attributes['href'];
      if (href == null || href.isEmpty) continue;

      final text = link.text.toLowerCase().trim();
      final cls = (link.attributes['class'] ?? '').toLowerCase();
      final title = (link.attributes['title'] ?? '').toLowerCase();
      final absoluteUrl = _resolveUrl(href, baseUri);

      // Check by CSS class pattern (e.g. prevchap, prev-chapter, next_chap, chapindex)
      final isPrevClass =
          _containsWord(cls, 'prev') || _containsWord(cls, 'previous');
      final isNextClass = _containsWord(cls, 'next');
      final isHomeClass =
          _containsWord(cls, 'index') ||
          _containsWord(cls, 'home') ||
          _containsWord(cls, 'toc');

      // Check by visible text inside spans/children
      // Get just span/button text to avoid noise from icon font text
      final spanTexts = link
          .querySelectorAll('span, b, strong, button')
          .map((e) => e.text.toLowerCase().trim())
          .join(' ');
      final effectiveText = spanTexts.isNotEmpty ? spanTexts : text;

      if (result['prev'] == null &&
          (isPrevClass ||
              effectiveText.contains('previous') ||
              effectiveText.contains('prev') ||
              _containsWord(title, 'prev') ||
              _containsWord(title, 'previous'))) {
        result['prev'] = absoluteUrl;
      } else if (result['next'] == null &&
          (isNextClass ||
              effectiveText.contains('next') ||
              _containsWord(title, 'next'))) {
        result['next'] = absoluteUrl;
      } else if (result['home'] == null &&
          (isHomeClass ||
              effectiveText.contains('index') ||
              effectiveText.contains('home') ||
              effectiveText == 'home page' ||
              _containsWord(title, 'index') ||
              _containsWord(title, 'home'))) {
        result['home'] = absoluteUrl;
      }
    }

    return result;
  }

  /// Returns true if [text] contains [word] as a whole word or word-part
  /// within a CSS class token (separated by spaces, hyphens, or underscores).
  bool _containsWord(String text, String word) {
    if (text.isEmpty) return false;
    // Split class string on spaces, hyphens, underscores and check each token
    final tokens = text.split(RegExp(r'[\s\-_]+'));
    return tokens.any(
      (t) => t == word || t.startsWith(word) || t.endsWith(word),
    );
  }

  String _resolveUrl(String href, Uri baseUri) {
    try {
      final uri = Uri.parse(href);
      if (uri.hasScheme) {
        return uri.toString();
      }
      return baseUri.resolve(href).toString();
    } catch (e) {
      return href;
    }
  }
}
