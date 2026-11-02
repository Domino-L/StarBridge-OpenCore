// Slice18: the trade profile form's own controls — the trading-day chips, the
// time zone and language selects and the folded sections. Native geometry
// measured before the adaptation is pinned for the standard suite; every
// suite keeps one reader action per control, pointer activation and the
// written changes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_profile.dart';

import 'marketplace_trade_profile_test.dart' show fixtureProfile;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

Finder _day(String label) =>
    find.byKey(ValueKey<(String, String)>(('trade-profile-day', label)));
const _zone = Key('trade-profile-zone');
const _language = Key('trade-profile-language');

Future<List<MarketRow>> _form(
  WidgetTester tester,
  InteractionSuite suite, {
  String? missing,
}) async {
  size(tester, const Size(1280, 1000));
  final sent = <MarketRow>[];
  await tester.pumpWidget(
    scopedApp(
      TradeProfileForm(
        read: () async => fixtureProfile(),
        zones: () async => [
          {'id': 1, 'label': 'UTC +08:00', 'offsetMinutes': 480},
          {'id': 2, 'label': 'UTC +00:00', 'offsetMinutes': 0},
        ],
        current: () => true,
        missing: missing,
        write: (changes) async {
          sent.add(changes);
          return {
            'profile': {...fixtureProfile(), ...changes},
            'confirmed': true,
          };
        },
      ),
      suite,
    ),
  );
  await tester.pumpAndSettle();
  return sent;
}

bool _selected(WidgetTester tester, String label) => namedButton(
  tester,
  label,
).getSemanticsData().flagsCollection.isSelected.toString().endsWith('isTrue');

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    await _form(tester, InteractionSuite.standard);
    expect(
      tester.getRect(_day('每天')),
      within(
        distance: .001,
        from: const Rect.fromLTRB(380, 270, 438.2, 318),
      ),
    );
    for (final (i, d) in ['一', '二', '三', '四', '五', '六', '日'].indexed) {
      expect(
        tester.getRect(_day(d)),
        within(
          distance: .001,
          from: Rect.fromLTWH(442.2 + 52.0 * i, 270, 48, 48),
        ),
      );
    }
    expect(
      tester.getRect(find.byKey(_zone)),
      const Rect.fromLTRB(380, 481, 900, 525),
    );
    // Folded "more": native ListTile header, title inset 16, trailing 20px
    // indicator, 1px edge above and below.
    final title = find.text('更多');
    expect(tester.getRect(title), const Rect.fromLTRB(396, 676, 840, 700));
    final header = find.ancestor(of: title, matching: find.byType(ListTile));
    expect(tester.getRect(header), const Rect.fromLTRB(380, 660, 900, 716));
    final indicator = find.descendant(of: header, matching: find.byType(Icon));
    expect(
      tester.getRect(indicator),
      const Rect.fromLTRB(856, 678, 876, 698),
    );
    await tester.tap(header, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('trade-profile-mark'))),
      const Rect.fromLTRB(380, 685, 900, 729),
    );
    expect(
      tester.getRect(find.byKey(_language)),
      const Rect.fromLTRB(380, 729, 900, 773),
    );
    expect(tester.takeException(), isNull);

    // Blocked on contact: the complete hours section is folded at the top.
    await tester.pumpWidget(const SizedBox.shrink());
    await _form(
      tester,
      InteractionSuite.standard,
      missing: 'marketplace.contact_required',
    );
    expect(
      tester.getRect(
        find.ancestor(of: find.text('交易日'), matching: find.byType(ListTile)),
      ),
      const Rect.fromLTRB(380, 381.5, 900, 437.5),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: day chips toggle by pointer and reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final sent = await _form(tester, suite);
        expect(_selected(tester, '一'), isTrue);
        expect(_selected(tester, '每天'), isTrue);
        await tester.tap(_day('一'));
        await tester.pumpAndSettle();
        expect(_selected(tester, '一'), isFalse);
        expect(_selected(tester, '每天'), isFalse);
        activate(tester, namedButton(tester, '一'));
        await tester.pumpAndSettle();
        expect(_selected(tester, '一'), isTrue);
        activate(tester, namedButton(tester, '日'));
        await tester.pumpAndSettle();
        expect(_selected(tester, '日'), isFalse);
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(sent.single['tradeTime'], [1, 1, 1, 1, 1, 1, 0]);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    });

    testWidgets('${suite.name}: zone and language selects write the choice', (
      tester,
    ) async {
      final sent = await _form(tester, suite);
      await tester.tap(find.byKey(_zone));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UTC +00:00').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('更多'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_language));
      await tester.pumpAndSettle();
      await tester.tap(find.text('英文').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(sent.single['timezoneId'], 2);
      expect('${sent.single['language']}', '1');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('${suite.name}: folded sections open by reader and pointer', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _form(tester, suite, missing: 'marketplace.contact_required');
        expect(_day('每天'), findsNothing);
        activate(tester, namedButton(tester, '交易日'));
        await tester.pumpAndSettle();
        expect(_day('每天'), findsOneWidget);
        await tester.tap(find.text('交易日').first, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(_day('每天'), findsNothing);
        expect(find.byKey(_language), findsNothing);
        await tester.tap(find.text('更多'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byKey(_language), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    });
  }
}
