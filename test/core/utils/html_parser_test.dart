import 'package:flutter_test/flutter_test.dart';
import 'package:webvox/core/utils/html_parser.dart';

void main() {
  group('HtmlParser single paragraph post-processing', () {
    test('splits one multi-sentence paragraph into separate paragraphs', () {
      final article = HtmlParser().parse('''
        <html>
          <body>
            <article>
              <p>First sentence has enough content. Second sentence also has enough content! Third sentence is here?</p>
            </article>
          </body>
        </html>
        ''', 'https://example.com/article');

      expect(article.paragraphs, [
        'First sentence has enough content.',
        'Second sentence also has enough content!',
        'Third sentence is here?',
      ]);
    });

    test('duplicates one single-sentence paragraph', () {
      final article = HtmlParser().parse('''
        <html>
          <body>
            <article>
              <p>This is one sentence with enough content to keep.</p>
            </article>
          </body>
        </html>
        ''', 'https://example.com/article');

      expect(article.paragraphs, [
        'This is one sentence with enough content to keep.',
        'This is one sentence with enough content to keep.',
      ]);
    });

    test('leaves multiple existing paragraphs unchanged', () {
      final article = HtmlParser().parse('''
        <html>
          <body>
            <article>
              <p>First paragraph has enough content.</p>
              <p>Second paragraph has enough content.</p>
            </article>
          </body>
        </html>
        ''', 'https://example.com/article');

      expect(article.paragraphs, [
        'First paragraph has enough content.',
        'Second paragraph has enough content.',
      ]);
    });
  });
}
