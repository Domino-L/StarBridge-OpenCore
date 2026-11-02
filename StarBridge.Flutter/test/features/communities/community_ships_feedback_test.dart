// User feedback 2026-10-30 on the organization ships page: the whole card
// opens the details, the replacement count sits beside the price, the presence
// dot sits on the avatar, the size bar is gone, and no control follows the
// interaction suite.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_holo.dart';
import 'package:starbridge_flutter/features/communities/community_ship_card.dart';
import 'package:starbridge_flutter/features/communities/community_ship_loaners.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/community_image_decoder.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import '../friends/social_layout_test.dart' show loadFonts;
import 'community_ship_loaners_test.dart' show loaner, source;

const _target = '00000000000000000000000000000001';

ThemeData _theme(InteractionSuite suite) {
  final theme = buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('zh', 'CN'),
  );
  return theme.copyWith(
    extensions: [
      for (final extension in theme.extensions.values)
        if (extension is! StarBridgeInteractionTheme) extension,
      StarBridgeInteractionTheme(suite: suite),
    ],
  );
}

Widget _app(
  Widget child, {
  InteractionSuite suite = InteractionSuite.standard,
}) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: _theme(suite),
  home: Scaffold(body: child),
);

Widget _card(CommunitySharedShip ship, VoidCallback onDetails) => Center(
  child: SizedBox(
    width: 280,
    child: CommunityShipCard(
      ship: ship,
      targetRef: _target,
      avatarBytes: null,
      avatarLoading: false,
      imageDecoder: decodeCommunityImage,
      onDetails: onDetails,
      ownerTargetFactory: null,
      includeSocialActions: false,
    ),
  ),
);

Future<void> _openPanel(
  WidgetTester tester, {
  required InteractionSuite suite,
  bool holo = true,
}) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final port = ExampleCommunities();
  addTearDown(port.close);
  final panel = RepaintBoundary(
    key: const ValueKey('ships-capture'),
    child: ColoredBox(
      color: _theme(suite).scaffoldBackgroundColor,
      child: CommunityShipsPanel(
        port: port,
        targetRef: _target,
        name: 'Test',
        onBack: () {},
      ),
    ),
  );
  await tester.pumpWidget(
    _app(holo ? OrganizationHolo(child: panel) : panel, suite: suite),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);

  testWidgets('tapping anywhere on a card opens its details', (tester) async {
    var opened = 0;
    final ship = source();
    await tester.pumpWidget(_app(_card(ship, () => opened++)));
    await tester.pumpAndSettle();
    expect(find.text('查看'), findsNothing);
    await tester.tap(
      find.byKey(ValueKey('community-ship-card-image-${ship.shipRef}')),
    );
    await tester.pumpAndSettle();
    expect(opened, 1);
    // The price line, far from the image, counts as the card too.
    await tester.tap(find.textContaining(r'$100'));
    await tester.pumpAndSettle();
    expect(opened, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the replacement count sits right of the price', (tester) async {
    final ship = source(
      rows: [
        loaner('First', 'small', 'flyable'),
        loaner('Second', 'large', 'flyable'),
      ],
    );
    await tester.pumpWidget(_app(_card(ship, () {})));
    await tester.pumpAndSettle();
    final count = find.byKey(
      ValueKey('community-ship-loaner-count-${ship.shipRef}'),
    );
    expect(count, findsOneWidget);
    expect(find.text('替代船 2'), findsOneWidget);
    final price = tester.getRect(find.textContaining(r'$100'));
    final rect = tester.getRect(count);
    expect(rect.left, greaterThan(price.right));
    expect(rect.center.dy, closeTo(price.center.dy, 2));
    // The list of replacements itself stays in the details.
    expect(find.byType(CommunityShipLoaners), findsNothing);

    await tester.pumpWidget(_app(_card(source(rows: []), () {})));
    await tester.pumpAndSettle();
    expect(find.textContaining('替代船'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the presence dot sits on the avatar lower right', (
    tester,
  ) async {
    final ship = source();
    await tester.pumpWidget(_app(_card(ship, () {})));
    await tester.pumpAndSettle();
    final dot = tester.getRect(
      find.byKey(ValueKey('community-ship-presence-${ship.shipRef}')),
    );
    final name = tester.getRect(find.textContaining(ship.ownerCallsign).first);
    // 20px avatar + 2px: the dot ends at the box's corner, before the name.
    expect(dot.right, lessThan(name.left));
    expect(name.left - dot.right, lessThan(12));
    expect(dot.center.dy, greaterThan(name.center.dy - 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no control on the page follows the interaction suite', (
    tester,
  ) async {
    await _openPanel(tester, suite: InteractionSuite.rail);
    for (final key in [
      'community-ships-back',
      'community-ships-search',
      'community-ships-direction',
    ]) {
      final data = resolveStarBridgeInteraction(
        tester.element(find.byKey(Key(key))),
      );
      expect(data.suite, InteractionSuite.standard, reason: key);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('outside an organization page the suite still applies', (
    tester,
  ) async {
    await _openPanel(tester, suite: InteractionSuite.rail, holo: false);
    final data = resolveStarBridgeInteraction(
      tester.element(find.byKey(const Key('community-ships-back'))),
    );
    expect(data.suite, InteractionSuite.rail);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the header actions use the standard suite outside the surface', (
    tester,
  ) async {
    late BuildContext inner;
    await tester.pumpWidget(
      _app(
        OrganizationHoloFace(
          outsideSurface: true,
          child: Builder(
            builder: (context) {
              inner = context;
              return const SizedBox();
            },
          ),
        ),
        suite: InteractionSuite.glow,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      resolveStarBridgeInteraction(inner).suite,
      InteractionSuite.standard,
    );
    expect(OrganizationHolo.of(inner), isFalse);
  });

  testWidgets('the owner tiles share the whole row', (tester) async {
    await _openPanel(tester, suite: InteractionSuite.standard);
    await tester.tap(find.byKey(const ValueKey('community-ships-view-owners')));
    await tester.pumpAndSettle();
    bool keyed(Widget w, bool Function(String) test) =>
        w.key is ValueKey && test('${(w.key as ValueKey).value}');
    final tiles = find
        .byWidgetPredicate(
          (w) => keyed(w, (k) => k.startsWith('community-ships-owner-tile-')),
        )
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)))
        .toList();
    expect(tiles, isNotEmpty);
    final group = tester.getRect(
      find
          .byWidgetPredicate(
            (w) => keyed(
              w,
              (k) =>
                  k.startsWith('community-ships-owner-') &&
                  !k.contains('tile') &&
                  !k.contains('groups'),
            ),
          )
          .first,
    );
    final rowEnd = tiles
        .where((r) => r.top == tiles.first.top)
        .map((r) => r.right)
        .reduce((a, b) => a > b ? a : b);
    // Only the group's 10px padding is left at the end of a full row.
    expect(group.right - rowEnd, lessThan(14));
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('ships-capture')),
      );
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final output = File('build/community-ships-owners-review.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the summary has no size bar and the sort holds its direction', (
    tester,
  ) async {
    await _openPanel(tester, suite: InteractionSuite.standard);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey &&
            '${(w.key as ValueKey).value}'.startsWith('community-ships-size-'),
      ),
      findsNothing,
    );
    final sort = tester.getRect(
      find.byKey(const ValueKey('community-ships-sort-control')),
    );
    final direction = tester.getRect(
      find.byKey(const Key('community-ships-direction')),
    );
    expect(direction.left - sort.right, lessThan(24));
    expect(direction.height, lessThanOrEqualTo(32));
    // Review capture, not an assertion.
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('ships-capture')),
      );
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final output = File('build/community-ships-feedback-review.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
