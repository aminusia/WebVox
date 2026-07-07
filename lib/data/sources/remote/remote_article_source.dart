import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:webvox/core/constants/app_constants.dart';
import 'package:webvox/core/services/platform_service.dart';
import 'package:webvox/core/utils/html_parser.dart';

class RemoteArticleSource {
  static const _desktopUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/149.0.0.0 Safari/537.36';

  static const _novelArrowHeaders = {
    'accept': '*/*',
    'accept-language': 'en-US,en;q=0.9',
    'cache-control': 'no-cache',
    'cf-ipcountry': 'ID',
    'pragma': 'no-cache',
    'priority': 'u=1, i',
    'sec-ch-ua':
        '"Google Chrome";v="149", "Chromium";v="149", "Not)A;Brand";v="24"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"macOS"',
    'sec-fetch-dest': 'empty',
    'sec-fetch-mode': 'cors',
    'sec-fetch-site': 'same-origin',
    'x-client-platform': 'web-desktop',
    'x-device-type': 'desktop',
    'x-site-host': 'novelarrow.com',
    'x-track-reading-progress': 'false',
    'x-version-app': 'web-desktop',
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/149.0.0.0 Safari/537.36',
  };

  static const _freeWebNovelHeaders = {
    'accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
    'accept-language': 'en-US,en;q=0.9',
    'priority': 'u=0, i',
    'sec-ch-ua':
        '"Google Chrome";v="149", "Chromium";v="149", "Not)A;Brand";v="24"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"macOS"',
    'sec-fetch-dest': 'document',
    'sec-fetch-mode': 'navigate',
    'sec-fetch-site': 'none',
    'sec-fetch-user': '?1',
    'upgrade-insecure-requests': '1',
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/149.0.0.0 Safari/537.36',
  };

  final HtmlParser _parser;

  RemoteArticleSource({HtmlParser? parser}) : _parser = parser ?? HtmlParser();

  Future<({ParsedArticle article, String finalUrl})> fetch(
    String url, {
    String? refererUrl,
  }) async {
    final uri = Uri.parse(url);
    // Check if this is a novelarrow.com chapter URL
    if (uri.host == 'novelarrow.com' && uri.pathSegments.contains('chapter')) {
      return _fetchChapterWithAPI(url, refererUrl: refererUrl);
    }

    // Check if this is a freewebnovel.com URL
    final isFreeWebNovel = uri.host.contains('freewebnovel.com');

    final client = HttpClient();
    client.connectionTimeout = AppConstants.fetchTimeout;
    client.idleTimeout = AppConstants.fetchTimeout;

    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(AppConstants.fetchTimeout);
      request.followRedirects = true;
      request.maxRedirects = 10;
      if (isFreeWebNovel) {
        debugPrint('[FreeWebNovel] Fetching: $url');
        debugPrint('[FreeWebNovel] refererUrl: ${refererUrl ?? "(none)"}');
        _freeWebNovelHeaders.forEach((key, value) {
          request.headers.set(key, value);
        });
        if (refererUrl != null && refererUrl.trim().isNotEmpty) {
          request.headers.set('Referer', refererUrl.trim());
          debugPrint('[FreeWebNovel] Referer header set: ${refererUrl.trim()}');
        }
      } else {
        request.headers
          ..set('User-Agent', _desktopUserAgent)
          ..set(
            'Accept',
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          )
          ..set('Accept-Language', 'en-US,en;q=0.5')
          ..set('rsc', '1')
          ..set(
            'sec-ch-ua',
            '"Chromium";v="148", "Google Chrome";v="148", '
                '"Not/A)Brand";v="99"',
          )
          ..set('sec-ch-ua-mobile', '?0')
          ..set('sec-ch-ua-platform', '"macOS"')
          ..set('sec-fetch-dest', 'empty')
          ..set('sec-fetch-mode', 'cors')
          ..set('sec-fetch-site', 'same-origin');
        if (refererUrl != null && refererUrl.trim().isNotEmpty) {
          request.headers.set('Referer', refererUrl.trim());
        }
      }

      final response = await request.close().timeout(AppConstants.fetchTimeout);

      // Resolve the final URL after following all redirects.
      String finalUrl = url;
      if (response.redirects.isNotEmpty) {
        final lastLocation = response.redirects.last.location;
        // location may be relative; resolve it against the previous URL.
        finalUrl = Uri.parse(url).resolve(lastLocation.toString()).toString();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}: failed to fetch $url');
      }

      final contentType = response.headers.contentType;
      final charset = contentType?.charset?.toLowerCase() ?? 'utf-8';

      final bodyBytes = await response
          .expand((chunk) => chunk)
          .toList()
          .timeout(AppConstants.fetchTimeout);
      final bytes = Uint8List.fromList(bodyBytes);

      final String body;
      if (charset == 'utf-8' || charset == 'utf8') {
        body = utf8.decode(bytes, allowMalformed: true);
      } else {
        body = latin1.decode(bytes);
      }

      var article = _parser.parse(body, finalUrl);
      if (article.paragraphs.isEmpty) {
        final renderedBody = await PlatformService.renderUrlToHtml(
          finalUrl,
          refererUrl: refererUrl,
        );
        if (renderedBody != null && renderedBody.trim().isNotEmpty) {
          final renderedArticle = _parser.parse(renderedBody, finalUrl);
          if (renderedArticle.paragraphs.isNotEmpty) {
            article = renderedArticle;
          }
        }
      }
      if (article.paragraphs.isEmpty) {
        throw Exception('No readable content found at $finalUrl');
      }
      return (article: article, finalUrl: finalUrl);
    } finally {
      client.close(force: false);
    }
  }

  /// Fetches a chapter from websites like novelarrow.com via their API.
  /// The refererUrl should be the previous chapter's web URL (not API URL).
  /// For the first chapter, refererUrl can be null.
  Future<({ParsedArticle article, String finalUrl})> _fetchChapterWithAPI(
    String url, {
    String? refererUrl,
  }) async {
    debugPrint('[APIFetch] Fetching chapter: $url');
    debugPrint(
      '[APIFetch] refererUrl: ${refererUrl ?? "(none - first chapter)"}',
    );

    final uri = Uri.parse(url);
    final domain = uri.host;
    final pathSegments = uri.pathSegments;
    // Extract the novel slug and chapter slug from the URL
    // URL format: https://{domain}/chapter/<novel-slug>/<chapter-slug>
    // API format: https://{domain}/api-web/novels/<novel-slug>/chapters/<chapter-slug>
    if (pathSegments.length < 3 || pathSegments[0] != 'chapter') {
      debugPrint('[APIFetch] ERROR: Invalid chapter URL format: $url');
      throw Exception('Invalid chapter URL: $url');
    }
    final novelSlug = pathSegments[1];
    final chapterSlug = pathSegments[2];
    debugPrint(
      '[APIFetch] Parsed: novelSlug=$novelSlug, chapterSlug=$chapterSlug',
    );

    // Build the API URL
    final apiUrl = 'https://$domain/api-web/novels/$novelSlug/chapters/$chapterSlug';
    debugPrint('[APIFetch] API URL: $apiUrl');

    // Build headers - use the previous chapter's web URL as referer
    // For the first chapter, refererUrl is null so we omit it (like the first fetch in the example)
    final headers = Map<String, String>.from(_novelArrowHeaders);
    if (refererUrl != null && refererUrl.trim().isNotEmpty) {
      // Convert chapter web URL to the format used as referer
      // The referer should be the web chapter URL, not API URL
      headers['Referer'] = refererUrl.trim();
      debugPrint('[APIFetch] Referer header set: ${refererUrl.trim()}');
    } else {
      debugPrint('[APIFetch] No Referer header (first chapter)');
    }

    final client = HttpClient();
    client.connectionTimeout = AppConstants.fetchTimeout;
    client.idleTimeout = AppConstants.fetchTimeout;

    try {
      debugPrint('[APIFetch] Creating HTTP request...');
      final request = await client
          .getUrl(Uri.parse(apiUrl))
          .timeout(AppConstants.fetchTimeout);
      request.followRedirects = true;
      request.maxRedirects = 10;

      headers.forEach((key, value) {
        request.headers.set(key, value);
      });
      debugPrint('[APIFetch] Headers set, sending request...');

      final response = await request.close().timeout(AppConstants.fetchTimeout);
      debugPrint(
        '[APIFetch] Response received: statusCode=${response.statusCode}',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[APIFetch] ERROR: HTTP ${response.statusCode} for $apiUrl');
        throw Exception('HTTP ${response.statusCode}: failed to fetch $apiUrl');
      }

      final contentType = response.headers.contentType;
      final charset = contentType?.charset?.toLowerCase() ?? 'utf-8';
      debugPrint('[APIFetch] Content-Type: $contentType, charset: $charset');

      final bodyBytes = await response
          .expand((chunk) => chunk)
          .toList()
          .timeout(AppConstants.fetchTimeout);
      debugPrint('[APIFetch] Body bytes received: ${bodyBytes.length} bytes');
      final bytes = Uint8List.fromList(bodyBytes);

      final String body;
      if (charset == 'utf-8' || charset == 'utf8') {
        body = utf8.decode(bytes, allowMalformed: true);
      } else {
        body = latin1.decode(bytes);
      }
      debugPrint(
        '[APIFetch] Body decoded (first 500 chars): ${body.substring(0, body.length.clamp(0, 500))}',
      );

      // Parse the JSON response from the API
      final jsonData = jsonDecode(body) as Map<String, dynamic>;
      debugPrint('[APIFetch] JSON parsed, keys: ${jsonData.keys.join(", ")}');

      // The API returns chapter content at item.chapterInfo
      // Structure: { "item": { "chapterInfo": { "chapter_content": "...", "title": "...", "chapter_name": "Chapter 827 825: The Squad Gathers Together", "novel": {"novel_id": "sage-of-humanity", "novel_name": "Sage of Humanity"}, "chapter_id": "chapter-827-825-the-squad-gathers-together", "prevChapter": {"chapter_id": "...", "chapter_name": "..."}, "nextChapter": {"chapter_id": "...", "chapter_name": "..."} } } }
      final item = jsonData['item'] as Map<String, dynamic>?;
      final chapterInfo = item?['chapterInfo'] as Map<String, dynamic>?;
      if (chapterInfo == null) {
        debugPrint('[APIFetch] ERROR: chapterInfo not found in response');
        throw Exception('Invalid API response: missing chapterInfo');
      }
      debugPrint('[APIFetch] chapterInfo keys: ${chapterInfo.keys.join(", ")}');

      // Extract chapter name from chapter_name field (format: "Chapter N M: Name")
      final chapterNameRaw = chapterInfo['chapter_name'] as String?;
      final chapterName = chapterNameRaw?.split(':').last.trim() ?? 'Chapter';

      // Use novel_name from chapterInfo for the novel/series title (db.series.name)
      final seriesName = chapterInfo['novel_name'] as String?;

      final contentHtml =
          (chapterInfo['chapter_content'] as String? ??
              chapterInfo['content'] as String? ??
              '');
      debugPrint(
        '[APIFetch] Chapter name: $chapterName, Series name: $seriesName, Content HTML length: ${contentHtml.length}',
      );

      // Extract novel ID and chapter ID for building API URLs
      final novel = chapterInfo['novel'] as Map<String, dynamic>?;
      final novelId = novel?['novel_id'] as String?;
      final chapterId = chapterInfo['chapter_id'] as String?;
      debugPrint('[APIFetch] novelId: $novelId, chapterId: $chapterId');

      final prevChapter = chapterInfo['prevChapter'] as Map<String, dynamic>?;
      final nextChapter = chapterInfo['nextChapter'] as Map<String, dynamic>?;
      final prevChapterId = prevChapter?['chapter_id'] as String?;
      final nextChapterId = nextChapter?['chapter_id'] as String?;
      debugPrint(
        '[APIFetch] prevChapterId: $prevChapterId, nextChapterId: $nextChapterId',
      );

      // Build WEB URLs for prev/next navigation (so refererUrl passed to next fetch is correct web URL)
      // Web URL format: https://novelarrow.com/chapter/{novelId}/{chapterId}
      final String? prevUrl;
      if (novelId != null && prevChapterId != null) {
        prevUrl = 'https://novelarrow.com/chapter/$novelId/$prevChapterId';
      } else {
        prevUrl = null;
      }

      final String? nextUrl;
      if (novelId != null && nextChapterId != null) {
        nextUrl = 'https://novelarrow.com/chapter/$novelId/$nextChapterId';
      } else {
        nextUrl = null;
      }

      // Parse the HTML content using the existing HTML parser
      final finalUrl = 'https://novelarrow.com/chapter/$novelId/$chapterId';
      debugPrint('[APIFetch] Parsing HTML content...');
      var article = _parser.parse(contentHtml, finalUrl);
      debugPrint('[APIFetch] Parsed paragraphs: ${article.paragraphs.length}');
      article = ParsedArticle(
        title:
            chapterName, // Use extracted chapter name (e.g., "The Squad Gathers Together")
        paragraphs: article.paragraphs,
        author: article.author,
        language: article.language,
        estimatedReadTime: article.estimatedReadTime,
        prevUrl: prevUrl,
        nextUrl: nextUrl,
        homeUrl: 'https://novelarrow.com/novel/$novelSlug',
        seriesName: seriesName,
      );

      if (article.paragraphs.isEmpty) {
        debugPrint('[APIFetch] ERROR: No readable content found after parsing');
        throw Exception('No readable content found at $finalUrl');
      }
      debugPrint(
        '[APIFetch] SUCCESS: Chapter fetched, ${article.paragraphs.length} paragraphs',
      );
      return (article: article, finalUrl: finalUrl);
    } catch (e, st) {
      debugPrint('[APIFetch] ERROR: $e');
      debugPrint('[APIFetch] Stack trace: $st');
      rethrow;
    } finally {
      client.close(force: false);
    }
  }
}
