import 'package:test/test.dart';
import 'package:zhihu_api/zhihu_api_parsers.dart';

void main() {
  group('content body parsers', () {
    test('reads rich pin content objects', () {
      final value = <String, dynamic>{
        'type': 'pin',
        'content': <String, dynamic>{
          'blocks': [
            {'type': 'paragraph', 'text': '第一段'},
            {'type': 'paragraph', 'text': '第二段'},
          ],
          'text': '第一段\n第二段',
        },
      };

      expect(htmlContent(value), '第一段\n第二段');
      expect(plainText(htmlContent(value)), '第一段 第二段');
    });

    test('reads nested pin envelopes and JSON encoded content', () {
      final value = <String, dynamic>{
        'data': <String, dynamic>{
          'pin': <String, dynamic>{
            'type': 'pin',
            'id': '33',
            'content': '{"text":"想法正文"}',
          },
        },
      };

      expect(htmlContent(value), '想法正文');
      expect(unwrapObject(value)['type'], 'pin');
      expect(idOf(value), '33');
    });

    test('reads blocks-only pin content and its media', () {
      const value = <String, dynamic>{
        'type': 'pin',
        'id': '33',
        'content': {
          'blocks': [
            {
              'type': 'paragraph',
              'children': [
                {'text': '第一段'},
              ],
            },
            {
              'type': 'image',
              'image': {'url': 'https://example.com/pin-image.jpg'},
            },
            {
              'type': 'paragraph',
              'children': [
                {'text': '第二段'},
              ],
            },
          ],
        },
      };

      expect(htmlContent(value), '第一段\n\n第二段');
      expect(contentImageUrlsOf(value), ['https://example.com/pin-image.jpg']);
      expect(unwrapObject(value)['type'], 'pin');
      expect(idOf(value), '33');
    });

    test('keeps ordinary html unchanged', () {
      const value = <String, dynamic>{'content': '<p>正文</p><img src="x">'};

      expect(htmlContent(value), '<p>正文</p><img src="x">');
    });
  });
}
