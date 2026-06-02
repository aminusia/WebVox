import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:webvox/core/constants/app_constants.dart';
import 'package:webvox/core/services/platform_service.dart';
import 'package:webvox/core/utils/html_parser.dart';

class RemoteArticleSource {
  static const _desktopUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/148.0.0.0 Safari/537.36';

  final HtmlParser _parser;

  RemoteArticleSource({HtmlParser? parser}) : _parser = parser ?? HtmlParser();

  Future<({ParsedArticle article, String finalUrl})> fetch(
    String url, {
    String? refererUrl,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = AppConstants.fetchTimeout;
    client.idleTimeout = AppConstants.fetchTimeout;

    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(AppConstants.fetchTimeout);
      request.followRedirects = true;
      request.maxRedirects = 10;
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
}
