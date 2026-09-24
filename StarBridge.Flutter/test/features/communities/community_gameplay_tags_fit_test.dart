import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_gameplay_tags.dart';

import '../personal_profile/profile_polish_regression_test.dart' show app;
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final scale in [1.0, 1.5]) {
    for (final height in [32.0, 64.0]) {
      testWidgets(
        'fit all available rows and reserve overflow label $height $scale',
        (tester) async {
          tester.view.physicalSize = const Size(1400, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          const names = ['探索', '战斗', '社交', '休闲', '新手友好', '运输'];
          for (final width in [190.0, 320.0, 560.0]) {
            await tester.pumpWidget(
              app(
                Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: SizedBox(
                      width: width * scale,
                      height: height * scale,
                      child: const CommunityGameplayTags(
                        value: '探索 · 战斗 · 社交 · 休闲 · 新手友好 · 运输',
                        fitAvailableSpace: true,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final bounds = tester.getRect(find.byType(CommunityGameplayTags));
            var visible = 0;
            for (final name in names) {
              final tag = find.byKey(ValueKey('community-gameplay-tag-$name'));
              if (tag.evaluate().isEmpty) continue;
              visible++;
              final rect = tester.getRect(tag);
              expect(rect.right, lessThanOrEqualTo(bounds.right + .01));
              expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + .01));
            }
            final hidden = names.length - visible;
            if (hidden > 0) {
              final more = find.text('+$hidden');
              expect(more, findsOneWidget);
              final rect = tester.getRect(more);
              expect(rect.right, lessThanOrEqualTo(bounds.right + .01));
              expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + .01));
            }
            if (width == 560 || (width == 320 && height == 64)) {
              expect(visible, names.length);
              expect(find.textContaining(RegExp(r'^\+\d+$')), findsNothing);
            }
          }
        },
      );
    }
  }
  testWidgets('a fitting long tag is not shortened to one third of the row', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const SizedBox(
          width: 440,
          height: 32,
          child: CommunityGameplayTags(
            value: 'Weekend Exploration Crew · PVE',
            fitAvailableSpace: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final label = find.text('Weekend Exploration Crew');
    expect(label, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(find.text('PVE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
