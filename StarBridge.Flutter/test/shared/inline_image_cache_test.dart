import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/inline_image_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const image = 'data:image/png;base64,AQID';

  test('cache owners neither reuse bytes nor clear each other', () {
    final first = InlineImageCache();
    final second = InlineImageCache();
    final a = first.resolve(image);
    final b = second.resolve(image);
    expect(a, isNotNull);
    expect(b, isNot(same(a)));
    expect(first.resolve(image), same(a));
    first.clear();
    expect(first.resolve(image), isNot(same(a)));
    expect(second.resolve(image), same(b));
    first.clear();
    second.clear();
  });

  test('byte limit evicts old images before entry limit', () {
    final cache = InlineImageCache();
    String source(int value) =>
        'data:image/png;base64,${base64Encode(List.filled(500 * 1024, value))}';
    final oldest = source(1);
    final original = cache.resolve(oldest);
    for (var i = 2; i < 8; i++) {
      expect(cache.resolve(source(i)), isNotNull);
    }
    expect(cache.resolve(oldest), isNot(same(original)));
    cache.clear();
  });

  testWidgets('scope replacement refreshes inherited image consumers', (
    tester,
  ) async {
    final first = InlineImageCache();
    final second = InlineImageCache();
    final resolved = <ImageProvider?>[];
    final consumer = Builder(
      builder: (context) {
        resolved.add(InlineImageCacheScope.resolve(context, image));
        return const SizedBox();
      },
    );
    await tester.pumpWidget(
      InlineImageCacheScope(cache: first, child: consumer),
    );
    final initial = resolved.last;
    await tester.pumpWidget(
      InlineImageCacheScope(cache: second, child: consumer),
    );
    expect(resolved, hasLength(2));
    expect(resolved.last, same(second.resolve(image)));
    expect(resolved.last, isNot(same(initial)));
    first.clear();
    second.clear();
  });
}
