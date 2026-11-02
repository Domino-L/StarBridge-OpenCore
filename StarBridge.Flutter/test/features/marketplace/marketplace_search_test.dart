import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_test.dart' show FixturePort, app, capture;

class SuggestPort extends FixturePort {
  @override
  Future<MarketRead> read(
    String operation, {
    int id = 0,
    String keyword = '',
    int category = 0,
    int side = 1,
    int page = 1,
    String language = 'CN',
    Map<String, String> options = const {},
  }) {
    if (operation == 'search') {
      return Future.value(
        MarketRead({
          'rows': [
            {'id': 81, 'itemName': '制裁'},
            {'id': 82, 'itemName': '裁决'},
          ],
        }, DateTime.now()),
      );
    }
    return super.read(
      operation,
      id: id,
      keyword: keyword,
      category: category,
      side: side,
      page: page,
      language: language,
      options: options,
    );
  }
}

void main() {
  testWidgets('Tab completes prefix match without navigating, history wraps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = SuggestPort();
    port.prefs = {
      ...port.prefs,
      'recentSearches': ['科力晶', '裁决'],
    };
    final c = MarketplaceController(port);
    await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('zh')));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('marketplace-search'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('科力晶')).dy,
      tester.getTopLeft(find.text('裁决')).dy,
    );
    await tester.enterText(field, '裁');
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(find.text('制裁'), findsNWidgets(2));
    expect(find.text('裁决'), findsNWidgets(3));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(tester.widget<TextField>(field).controller!.text, '裁决');
    expect(c.hasItem, isFalse);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await capture(tester, 'search-completion-manual');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.itemId, 82);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
