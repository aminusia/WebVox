import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:webvox/core/constants/app_constants.dart';
import 'package:webvox/core/utils/html_parser.dart';

class RemoteArticleSource {
  final HtmlParser _parser;

  RemoteArticleSource({HtmlParser? parser}) : _parser = parser ?? HtmlParser();

  Future<({ParsedArticle article, String finalUrl})> fetch(String url) async {
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
        ..set('User-Agent', 'Mozilla/5.0 (Linux; Android 10) WebVox/1.0')
        ..set(
          'Accept',
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        )
        ..set('Accept-Language', 'en-US,en;q=0.5');

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

      final article = _parser.parse(body, finalUrl);
      return (article: article, finalUrl: finalUrl);
    } finally {
      client.close(force: false);
    }
  }
}
