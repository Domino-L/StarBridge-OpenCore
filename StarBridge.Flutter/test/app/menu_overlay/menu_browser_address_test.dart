import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_browser_address.dart';

void main() {
  test('version numbers and punctuation remain useful search terms', () {
    for (final input in ['star citizen 3.24 更新', 'node.js 教程', '星际公民']) {
      final uri = menuBrowserAddress(input)!;
      expect(uri.host, 'www.bing.com');
      expect(uri.queryParameters['q'], input);
    }
  });
  test('web addresses support ports and preserve explicit HTTP', () {
    for (final input in [
      'localhost:8080',
      'example.com:8080/path',
      'example.com',
    ]) {
      expect(menuBrowserAddress(input).toString(), 'https://$input');
    }
    expect(
      menuBrowserAddress('http://example.com/a?q=1').toString(),
      'http://example.com/a?q=1',
    );
  });
  test('explicit unsafe protocols and credentials are never dispatched', () {
    for (final input in [
      '',
      'file:///C:/',
      'javascript:alert(1)',
      'mailto:test@example.com',
      'data:text/html,test',
      'https://user:password@example.com',
      'https://bad host.test',
    ]) {
      expect(menuBrowserAddress(input), isNull, reason: input);
    }
  });
}
