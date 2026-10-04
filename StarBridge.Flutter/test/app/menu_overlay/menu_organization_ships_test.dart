import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_ships.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_avatars.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_fleet_summary.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_inline_avatar.dart';
import 'package:starbridge_flutter/features/communities/community_fleet_statistics_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import 'menu_channel_media_session_test.dart' show PhotoPort;
import 'menu_chat_media_test.dart' show photo;
import 'menu_organizations_test.dart' show fixture;
import '../../features/communities/community_ships_test.dart' show shipRow;
import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

class FleetPort extends PhotoPort implements CommunityShipsPort {
  final queries = <CommunityShipQuery>[];
  int avatarReads = 0;
  bool changed = false, denied = false;
  @override
  bool get shipsAvailable => true;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    queries.add(query!);
    if (denied && offset > 0) throw const CommunityFailure('notAllowed');
    final total = query.text.isEmpty ? 25 : 1;
    return CommunityShipsPage.parse({
      'schemaVersion': 1,
      'queryVersion': 2,
      'targetRef': targetRef,
      'query': query.toPayload(),
      'revision': (changed && offset > 0 ? 'e' : 'b') * 64,
      'offset': offset,
      'totalCount': 25,
      'matchedCount': total,
      'next': offset + 20 < total ? offset + 20 : null,
      'ships': [
        for (var i = offset; i < (offset + 20).clamp(0, total); i++)
          {
            ...shipRow(),
            'shipRef': i.toRadixString(16).padLeft(32, '0'),
            'ownerAvatarVersion': sha256
                .convert(base64Decode(photo.split(',').last))
                .toString(),
            'catalogPriceUsd': '100',
          },
      ],
    });
  }

  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async {
    avatarReads++;
    final bytes = base64Decode(photo.split(',').last);
    return {
      'schemaVersion': 1,
      'targetRef': targetRef,
      'kind': kind,
      'memberRef': memberRef,
      'mimeType': 'image/png',
      'offset': 0,
      'next': null,
      'totalBytes': bytes.length,
      'version': sha256.convert(bytes).toString(),
      'data': base64Encode(bytes),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  test(
    'menu reuses full inventory statistics and authorized owner thumbnails',
    () async {
      final port = FleetPort(),
          ships = MenuOrganizationShips(),
          avatars = MenuOrganizationAvatars();
      addTearDown(port.close);
      addTearDown(avatars.dispose);
      ships.statisticsOpen = true;
      final result = await ships.read(
        port,
        port,
        avatars,
        'a' * 32,
        0,
        'filtered',
        () {},
      );
      expect(result.rows.length, 1);
      final summary = MenuFleetSummary.parse(result.statistics)!;
      expect(summary.shipCount, 25);
      expect(summary.totalCents, 250000);
      expect(summary.sharingMemberCount, 1);
      expect(
        result.presentation.single['avatar'],
        startsWith('data:image/png;base64,'),
      );
      expect(port.avatarReads, 1);
      expect(port.queries.map((q) => q.text), ['filtered', '', '']);
      expect(jsonEncode(result.statistics), isNot(contains('ownerMemberRef')));
      expect(
        () => MenuFleetSummary.parse({...result.statistics!, 'shipCount': 24}),
        throwsFormatException,
      );
      ships.clear();
      expect(ships.statisticsOpen, isFalse);
    },
  );
  test(
    'changed inventory rejects partial totals; revoked access propagates',
    () async {
      final port = FleetPort()..changed = true,
          ships = MenuOrganizationShips()..statisticsOpen = true;
      final avatars = MenuOrganizationAvatars();
      addTearDown(port.close);
      addTearDown(avatars.dispose);
      final result = await ships.read(
        port,
        port,
        avatars,
        'a' * 32,
        0,
        '',
        () {},
      );
      expect(result.statistics, isNull);
      expect(result.notice, contains('重试'));
      port.denied = true;
      ships.statisticsOpen = true;
      await expectLater(
        ships.read(port, port, avatars, 'a' * 32, 0, '', () {}),
        throwsA(isA<CommunityFailure>()),
      );
    },
  );
  testWidgets(
    'ship page removes date, shows owner portrait and client statistics at both widths',
    (tester) async {
      final captureKey = GlobalKey();
      for (final width in [1400.0, 390.0]) {
        size(tester, Size(width, 900));
        final data = fixture(tab: 'ships');
        (data['buttons'] as List).add({
          'key': 'a7',
          'label': '舰队统计',
          'limit': 128,
        });
        final org = data['organization'] as Map;
        org['rows'] = [
          for (var i = 0; i < 4; i++)
            {
              'owner': '持有者',
              'avatar': photo,
              'presence': 'online',
              'spec': 'ground-small',
              'role': 'ground-transport',
              'importedAt': '2026-09-01',
              'price': '\$400',
              'status': 'flyable',
            },
        ];
        String? action;
        await tester.pumpWidget(
          app(
            Theme(
              data: buildMenuOverlayTheme(const Locale('zh', 'CN')),
              child: RepaintBoundary(
                key: captureKey,
                child: ColoredBox(
                  color: const Color(0xff0d171d),
                  child: MenuOrganizationsPanel(
                    view: MenuFeatureView.parse(data),
                    onAction: (key, _) => action = key,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('机库导入时间'), findsNothing);
        expect(find.byType(MenuInlineAvatar), findsNWidgets(4));
        final searchRect = tester.getRect(find.text('搜索'));
        final statisticsRect = tester.getRect(find.text('舰队统计'));
        expect(statisticsRect.left, greaterThan(searchRect.right));
        expect(statisticsRect.center.dy, closeTo(searchRect.center.dy, 1));
        await tester.tap(find.text('舰队统计'));
        expect(action, 'a7');
        expect(tester.takeException(), isNull);
        if (width == 1400) {
          await capture(tester, captureKey, 'menu-org-ships-polish');
        }
        org['fleetStatistics'] = {
          'shipCount': 0,
          'modelCount': 0,
          'sharingMemberCount': 0,
          'pricedCount': 0,
          'totalCents': 0,
          'sizes': {},
          'roles': {},
          'matrix': {},
        };
        (data['buttons'] as List).add({
          'key': 'a8',
          'label': '关闭统计',
          'limit': 128,
        });
        await tester.pumpWidget(
          app(
            MenuOrganizationsPanel(
              view: MenuFeatureView.parse(data),
              onAction: (key, _) => action = key,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CommunityFleetStatisticsDialog), findsOneWidget);
        await tester.tap(find.text('关闭').last);
        expect(action, 'a8');
        await tester.pump();
        expect(
          find.byType(CommunityFleetStatisticsDialog),
          findsNothing,
          reason: 'Close is immediate even before a primary-engine response',
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
