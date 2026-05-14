import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:webreader/core/constants/app_constants.dart';
import 'package:webreader/core/utils/html_parser.dart';

class RemoteArticleSource {
  final HtmlParser _parser;

  RemoteArticleSource({HtmlParser? parser}) : _parser = parser ?? HtmlParser();

  Future<ParsedArticle> fetch(String url) async {
    final uri = Uri.parse(url);

    final response = await http
        .get(
          uri,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 10) WebReader/1.0',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.5',
          },
        )
        .timeout(AppConstants.fetchTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: failed to fetch $url');
    }

    final contentType = response.headers['content-type'] ?? '';
    String body;
    if (contentType.contains('charset=')) {
      final match = RegExp(
        r'charset=([^\s;]+)',
        caseSensitive: false,
      ).firstMatch(contentType);
      final charset = match?.group(1)?.toLowerCase() ?? 'utf-8';
      if (charset == 'utf-8' || charset == 'utf8') {
        body = utf8.decode(response.bodyBytes, allowMalformed: true);
      } else {
        body = response.body;
      }
    } else {
      body = utf8.decode(response.bodyBytes, allowMalformed: true);
    }

    return _parser.parse(body, url);
  }
}
