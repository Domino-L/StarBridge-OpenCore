import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/shell/widgets/attention_badge.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

import '../features/friends/social_layout_test.dart'
    show app, capture, loadFonts, size;

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'badge is inside the button, separate from icon and fully clickable',
    (tester) async {
      size(tester, const Size(400, 100));
      var presses = 0;
      for (final count in [1, 2, 100]) {
        await tester.pumpWidget(
          app(
            Center(
              child: OutlinedButton(
                key: const Key('badge-button'),
                onPressed: () => presses++,
                child: AttentionBadge(
                  count: count,
                  child: const Icon(
                    Icons.notifications_none,
                    key: Key('badge-icon'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = tester.getRect(find.byKey(const Key('badge-button')));
        final icon = tester.getRect(find.byKey(const Key('badge-icon')));
        final badge = tester.getRect(find.byType(AttentionCount));
        expect(button.contains(badge.topLeft), isTrue);
        expect(
          button.contains(badge.bottomRight - const Offset(.1, .1)),
          isTrue,
        );
        expect(icon.overlaps(badge), isFalse);
        final before = presses;
        await tester.tapAt(badge.center);
        await tester.pump();
        expect(presses, before + 1);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final mode in AppearanceMode.values) {
    testWidgets('attention counters match coral and white reference in $mode', (
      tester,
    ) async {
      size(tester, const Size(240, 80));
      for (final count in [0, 1, 2, 100]) {
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: app(
              Center(
                child: AttentionBadge(
                  count: count,
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
              mode,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final label = find.descendant(
          of: find.byType(AttentionBadge),
          matching: find.byType(Text),
        );
        if (count == 0) {
          expect(label, findsNothing);
          continue;
        }
        final text = tester.widget<Text>(label);
        expect(text.data, count > 99 ? '99+' : '$count');
        final box = tester.widget<Container>(
          find.ancestor(of: label, matching: find.byType(Container)).first,
        );
        final background = (box.decoration! as BoxDecoration).color!;
        expect(background, const Color(0xFFFF5555));
        expect(text.style!.color, Colors.white);
        expect(text.style!.fontWeight, FontWeight.w700);
        if (count == 2) {
          await capture(tester, key, 'attention-coral-${mode.name}');
        }
      }
    });
  }
}
