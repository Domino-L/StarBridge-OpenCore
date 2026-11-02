// Slice21: "my activity" — the trades / listings / manifests switch and the
// trading profile summary's edit and reload actions. Since layout A (user
// 2026-10-23) the switch is a left rail and the profile a card under it; its
// measured geometry is pinned for the standard suite, and every suite keeps
// one reader action per control and pointer activation.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_my_activity.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_profile.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'marketplace_bridge_trade_test.dart' show Online;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

final _tabs = find.byKey(const Key('market-activity-tab'));
final _edit = find.byKey(const Key('market-trade-profile-summary-edit'));
final _retry = find.byKey(const Key('market-trade-profile-summary-retry'));

/// A listings-capable Bridge port whose Host never answers.
Future<MarketplaceController> _activity(
  WidgetTester tester,
  InteractionSuite suite,
) async {
  size(tester, const Size(1280, 900));
  final pair = InMemoryBridgeConnection.createPair();
  final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 1,
  );
  session.acceptHostCapabilities([
    'marketplace.read',
    'marketplace.listings',
    'marketplace.trades',
  ]);
  final sub = pair.host.incoming.listen((_) {});
  final mode = Online();
  final c = MarketplaceController(BridgeMarketplacePort(session, mode));
  addTearDown(() async {
    mode.dispose();
    await tester.runAsync(() async {
      await sub.cancel();
      await session.close().timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
      await pair.host.close().timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
    });
  });
  await tester.pumpWidget(scopedApp(MarketplaceMyActivity(c), suite));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return c;
}

Future<void> _end(WidgetTester tester, MarketplaceController c) async {
  await tester.pumpWidget(const SizedBox.shrink());
  c.dispose();
  // Let the unanswered Bridge requests time out.
  await tester.pump(const Duration(minutes: 2));
}

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    final c = await _activity(tester, InteractionSuite.standard);
    try {
      // The profile card sits under the rail's entries.
      expect(tester.getRect(_edit), const Rect.fromLTRB(132, 154, 180, 202));
      expect(tester.getRect(_retry), const Rect.fromLTRB(13, 276, 81, 324));
      expect(tester.getRect(_tabs), const Rect.fromLTRB(0, 0, 208, 900));
      for (final (label, rect) in [
        ('交易', const Rect.fromLTRB(0, 4, 193, 40)),
        ('挂单', const Rect.fromLTRB(0, 42, 193, 78)),
        ('清单', const Rect.fromLTRB(0, 80, 193, 116)),
      ]) {
        final segment = find.ancestor(
          of: find.text(label),
          matching: find.byType(TextButton),
        );
        expect(
          tester.getRect(segment),
          within(distance: .001, from: rect),
        );
      }
      // Rail entries have no checkmark: the selected one is exposed as
      // selected to readers instead.
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey(('market-activity-tab', 0))),
            )
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester.getRect(find.text('交易').first),
        within(distance: .001, from: const Rect.fromLTRB(20, 15.5, 183, 28.5)),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await _end(tester, c);
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: activity switch opens listings by pointer and reader',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final c = await _activity(tester, suite);
        try {
          expect(find.byType(MarketplaceListingsPage), findsNothing);
          activate(tester, namedButton(tester, '挂单'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(MarketplaceListingsPage), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await _end(tester, c);
        }
      },
    );

    testWidgets('${suite.name}: activity switch by pointer', (tester) async {
      final c = await _activity(tester, suite);
      try {
        await tester.tap(find.text('清单'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(MarketplaceListingsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _end(tester, c);
      }
    });

    testWidgets(
      '${suite.name}: summary edit opens the profile; reload stays available',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final c = await _activity(tester, suite);
        try {
          activate(tester, namedButton(tester, '重新读取'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(_retry, findsOneWidget);
          activate(tester, namedButton(tester, '编辑交易资料'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(TradeProfileForm), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await _end(tester, c);
        }
      },
    );
  }
}
