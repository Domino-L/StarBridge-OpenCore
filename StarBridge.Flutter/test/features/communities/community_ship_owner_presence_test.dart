import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_holo.dart';
import 'package:starbridge_flutter/features/communities/community_image_decoder.dart';
import 'package:starbridge_flutter/features/communities/community_ship_banner.dart';
import 'package:starbridge_flutter/features/communities/community_ship_card.dart';
import 'package:starbridge_flutter/features/communities/community_ship_owner_avatar.dart';
import 'package:starbridge_flutter/features/communities/community_ship_statistics.dart';
import 'package:starbridge_flutter/features/communities/community_ships_owner_groups.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import 'community_ships_test.dart' show shipRow;

const _target = '00000000000000000000000000000001';

CommunitySharedShip _ship(
  int id, {
  required bool online,
  required String status,
  String callsign = 'Holder',
}) => CommunitySharedShip.parse(
  shipRow()
    ..['shipRef'] = '$id'.padLeft(32, '0')
    ..['ownerMemberRef'] = '$id'.padLeft(32, 'a')
    ..['ownerGameName'] = ''
    ..['ownerCallsign'] = callsign
    ..['ownerOnline'] = online
    ..['ownerLiveStatus'] = status,
);

CommunitySharedShip _unknown(int id, {String callsign = 'Holder'}) =>
    _ship(id, online: false, status: 'Unknown', callsign: callsign);
CommunitySharedShip _offline(int id, {String callsign = 'Holder'}) =>
    _ship(id, online: false, status: 'Offline', callsign: callsign);

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('zh', 'CN'),
  ),
  home: Scaffold(body: OrganizationHolo(child: child)),
);

Widget _avatar(CommunitySharedShip ship) => CommunityShipOwnerAvatar(
  ship: ship,
  bytes: null,
  decoder: decodeCommunityImage,
  size: 32,
);

Widget _card(CommunitySharedShip ship) => Center(
  child: SizedBox(
    width: 280,
    child: CommunityShipCard(
      ship: ship,
      targetRef: _target,
      avatarBytes: null,
      avatarLoading: false,
      imageDecoder: decodeCommunityImage,
      onDetails: () {},
      ownerTargetFactory: null,
      includeSocialActions: false,
    ),
  ),
);

Widget _row(CommunitySharedShip ship) => SizedBox(
  width: 1100,
  child: CommunitySharedShipRow(
    ship: ship,
    targetRef: _target,
    avatarBytes: null,
    avatarLoading: false,
    imageDecoder: decodeCommunityImage,
    onDetails: () {},
    ownerTargetFactory: null,
    includeSocialActions: false,
  ),
);

Widget _groups(List<CommunitySharedShip> ships) => CommunityShipsOwnerGroups(
  ships: ships,
  selectedRef: null,
  onSelect: (_) {},
  decoder: decodeCommunityImage,
);

Finder _dot(CommunitySharedShip ship) =>
    find.byKey(ValueKey('community-ship-presence-${ship.shipRef}'));

Finder _presenceTooltip() => find.byWidgetPredicate(
  (widget) => widget is StarBridgeTooltip && widget.message == '离线',
);

void main() {
  test('only a source with no status at all counts as unknown', () {
    expect(_unknown(1).ownerPresenceKnown, isFalse);
    expect(communityShipPresenceKey(_unknown(1)), isNull);
    expect(_offline(1).ownerPresenceKnown, isTrue);
    expect(communityShipPresenceKey(_offline(1)), 'presence.offline');
    // The online flag wins, as it did before.
    final online = _ship(1, online: true, status: 'Unknown');
    expect(online.ownerPresenceKnown, isTrue);
    expect(communityShipPresenceKey(online), 'presence.online');
    for (final (status, key) in const [
      ('InGame', 'presence.inGame'),
      ('Away', 'presence.away'),
      ('AppOnline', 'presence.online'),
    ]) {
      expect(
        communityShipPresenceKey(_ship(1, online: true, status: status)),
        key,
      );
    }
  });

  test('statistics do not count an unknown owner as offline', () {
    final stats = CommunityShipStatistics([
      _unknown(1),
      _unknown(2),
      _offline(3),
    ]);
    expect(stats.ownerOffline, 1, reason: 'Only the real offline owner');
    expect(stats.availabilityUnknown, 2);
    expect(stats.available, isEmpty);
    expect(stats.shipCount, 3);
  });

  testWidgets('an unknown owner has no dot and no presence tooltip', (
    tester,
  ) async {
    final ship = _unknown(1);
    await tester.pumpWidget(_app(_avatar(ship)));
    await tester.pumpAndSettle();
    expect(_dot(ship), findsNothing);
    expect(_presenceTooltip(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a community owner keeps the dot and the tooltip', (
    tester,
  ) async {
    final ship = _offline(1);
    await tester.pumpWidget(_app(_avatar(ship)));
    await tester.pumpAndSettle();
    expect(_dot(ship), findsOneWidget);
    expect(_presenceTooltip(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card, list row and owner view never say offline when unknown', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final ship = _unknown(1);
    for (final view in [
      _card(ship),
      _row(ship),
      _groups([ship]),
    ]) {
      await tester.pumpWidget(_app(view));
      await tester.pumpAndSettle();
      expect(find.textContaining('Holder'), findsWidgets);
      expect(find.text('离线'), findsNothing);
      expect(_dot(ship), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('list row and owner view still say offline for a community', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final ship = _offline(1);
    for (final view in [
      _row(ship),
      _groups([ship]),
    ]) {
      await tester.pumpWidget(_app(view));
      await tester.pumpAndSettle();
      expect(find.text('离线'), findsOneWidget);
      expect(_dot(ship), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  test('owner view order: unknown owners by name, after any real status', () {
    final order = CommunityShipsOwnerGroups.group([
      _unknown(1, callsign: 'Zed'),
      _unknown(2, callsign: 'Amy'),
      _offline(3, callsign: 'Kim'),
    ]).map((list) => CommunityShipStatistics.owner(list.first)).toList();
    expect(order, ['Kim', 'Amy', 'Zed']);
  });
}
