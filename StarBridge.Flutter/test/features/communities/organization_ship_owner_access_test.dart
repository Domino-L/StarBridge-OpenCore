import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_hangar_sharing.dart';
import 'package:starbridge_flutter/features/common/organization_ship_owner.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_ship_avatar_access.dart';
import 'package:starbridge_flutter/features/communities/community_ship_detail_pane.dart';
import 'package:starbridge_flutter/features/communities/community_ship_image_port.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import 'community_ships_test.dart' show shipRow;
import 'community_workspace_test.dart' show WorkspaceTestPort;
import '../friends/social_layout_test.dart' show app, loadFonts, size;

final _target = 'a' * 32;
final _owner = 'd' * 32;
final _ship = 'c' * 32;
final _profile = 'e' * 64;
const _avatarKey = Key('synthetic-owner-avatar');
const _denyMedia = CommunityShipAvatarAccess();

// Test-only Host projection: this literal is not a derivation from a community
// reference and supplies no production official-fleet authority.
UserTarget? _authorizedOfficialTarget(
  String targetRef,
  CommunitySharedShip ship,
) => UserTarget('officialFleet', _profile, contextRef: 'officialFleet:74');

class _Port extends WorkspaceTestPort
    implements
        CommunityShipsPort,
        CommunityShipImagePort,
        CommunityShipReportPort {
  bool hasAvatar = false, self = false, empty = false;
  int reads = 0, mediaReads = 0, imageReads = 0, reportWrites = 0;
  @override
  bool get shipsAvailable => true;
  @override
  bool get shipImageAvailable => true;
  @override
  bool get shipReportAvailable => true;

  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    reads++;
    return CommunityShipsPage.parse({
      'schemaVersion': 1,
      'queryVersion': query == null ? 0 : 2,
      'query': query?.toPayload(),
      'targetRef': targetRef,
      'revision': 'b' * 64,
      'offset': 0,
      'next': null,
      'totalCount': empty ? 0 : 1,
      'matchedCount': empty ? 0 : 1,
      'ships': [
        if (!empty)
          shipRow()
            ..['ownerHasAvatar'] = hasAvatar
            ..['ownerIsSelf'] = self,
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
    mediaReads++;
    throw const CommunityFailure('unavailable');
  }

  @override
  Future<Map<String, Object?>> readShipImage(
    String targetRef,
    String shipRef, {
    required int offset,
    String? version,
  }) async {
    imageReads++;
    throw StateError('Catalog-only UI has no custom-image read permission');
  }

  @override
  Future<CommunityShipReportOutcome> reportShipImage(
    CommunityShipReportIntent intent,
  ) async {
    reportWrites++;
    throw StateError('Catalog-only UI has no image-report action');
  }

  @override
  Future<CommunityShipReportOutcome> checkShipReport(
    CommunityShipReportIntent intent,
  ) async {
    throw StateError('No image-report outcome may be inferred');
  }
}

Widget _ownerView({
  OrganizationShipOwnerTargetFactory? factory = communityShipOwnerTarget,
  bool social = true,
}) => app(
  OrganizationShipOwner(
    targetRef: _target,
    ship: CommunitySharedShip.parse(shipRow()),
    name: 'Synthetic owner',
    targetFactory: factory,
    includeSocialActions: social,
    child: const SizedBox(
      key: _avatarKey,
      width: 32,
      height: 32,
      child: ColoredBox(color: Colors.blue),
    ),
  ),
);

final class _Sharing implements OrganizationHangarSharingPort {
  @override
  bool get available => true;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FailingStatistics extends _Port {
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    if (query != null && query.culture.isNotEmpty) {
      throw const CommunityFailure('unavailable');
    }
    return super.readShips(targetRef, offset: offset, query: query);
  }
}

void main() {
  testWidgets('the right column shows the held row: no read, no polling', (
    tester,
  ) async {
    size(tester, const Size(1600, 1000));
    final port = _Port();
    addTearDown(port.changes.close);
    final page = await port.readShips(
      _target,
      query: CommunityShipQuery(culture: 'zh-CN'),
    );
    port.reads = 0;
    await tester.pumpWidget(
      app(
        CommunityShipDetailPane(
          port: port,
          page: page,
          shipRef: _ship,
          inline: true,
          pageIsCurrent: true,
          imageDecoder: (_, _) => throw UnimplementedError(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CommunityShipDetailPane), findsOneWidget);
    expect(port.reads, 0);
    await tester.pump(const Duration(seconds: 46));
    expect(port.reads, 0, reason: 'Open on every ship page, so it never polls.');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a ship withdrawn from the list leaves the right column', (
    tester,
  ) async {
    size(tester, const Size(1600, 1000));
    final port = _Port();
    addTearDown(port.changes.close);
    await tester.pumpWidget(
      app(
        CommunityShipsPanel(
          port: port,
          targetRef: _target,
          name: 'Synthetic organization',
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CommunityShipDetailPane), findsOneWidget);
    port.empty = true;
    await tester.tap(find.byKey(const Key('community-ships-refresh')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityShipDetailPane), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  group('the note beside the sharing entry', () {
    Future<void> open(WidgetTester tester, _Port port) async {
      size(tester, const Size(1600, 1000));
      addTearDown(port.changes.close);
      await tester.pumpWidget(
        app(
          CommunityShipsPanel(
            port: port,
            targetRef: _target,
            name: 'Synthetic organization',
            onBack: () {},
            hangarSharingPort: _Sharing(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    const hint = Key('community-ships-sharing-hint');
    testWidgets('shows once the whole library says nothing is mine', (
      tester,
    ) async {
      await open(tester, _Port());
      expect(find.byKey(hint), findsOneWidget);
      expect(find.byKey(const Key('community-ships-sharing')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('gone when something of mine is shared', (tester) async {
      await open(tester, _Port()..self = true);
      expect(find.byKey(hint), findsNothing);
    });
    testWidgets('not shown when the library could not be read', (tester) async {
      await open(tester, _FailingStatistics());
      expect(find.byKey(hint), findsNothing);
      expect(find.text('待确认'), findsNothing);
    });
  });

  setUpAll(loadFonts);

  testWidgets('a factory returning no authorization has no owner menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ownerView(factory: (targetRef, ship) => null, social: false),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UserAvatarMenu), findsNothing);
    expect(tester.getSize(find.byKey(_avatarKey)), const Size(32, 32));
    await tester.tap(find.byKey(_avatarKey));
    await tester.pump();
    expect(find.byType(UserAvatarMenu), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'withdrawn target removes the menu without replacing its avatar',
    (tester) async {
      var visible = true;
      UserTarget? target(String reference, CommunitySharedShip ship) =>
          visible ? _authorizedOfficialTarget(reference, ship) : null;
      await tester.pumpWidget(_ownerView(factory: target, social: false));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(_avatarKey));
      visible = false;
      await tester.pumpWidget(_ownerView(factory: target, social: false));
      await tester.pumpAndSettle();
      expect(find.byType(UserAvatarMenu), findsNothing);
      expect(tester.getRect(find.byKey(_avatarKey)), rect);
    },
  );

  test('omitted media seam still uses existing community media', () async {
    final port = _Port()..hasAvatar = true;
    addTearDown(port.changes.close);
    final controller = CommunityShipsController(port, _target, mediaPort: port);
    addTearDown(controller.dispose);
    await controller.load();
    expect(port.mediaReads, 1);
    expect(controller.page, isNotNull);
    expect(controller.mediaFailed, isTrue);
  });

  test('explicit denied media never falls back to workspace media', () async {
    final port = _Port()..hasAvatar = true;
    addTearDown(port.changes.close);
    final controller = CommunityShipsController(
      port,
      _target,
      mediaPort: port,
      avatarAccess: _denyMedia,
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(port.mediaReads, 0);
    expect(controller.avatar(_owner), isNull);
    expect(controller.page, isNotNull);
    expect(controller.mediaFailed, isFalse);
  });

  test(
    'explicit avatar reader receives scoped references without fallback',
    () async {
      final port = _Port()..hasAvatar = true;
      addTearDown(port.changes.close);
      final calls = <(String, String, int, String?)>[];
      final controller = CommunityShipsController(
        port,
        _target,
        mediaPort: port,
        avatarAccess: CommunityShipAvatarAccess(
          read:
              (
                String targetRef,
                String owner, {
                required int offset,
                String? version,
              }) async {
                calls.add((targetRef, owner, offset, version));
                throw const CommunityFailure('unavailable');
              },
        ),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(calls, [(_target, _owner, 0, null)]);
      expect(port.mediaReads, 0);
      expect(controller.mediaFailed, isTrue);
    },
  );

  for (final mode in [
    'community-default',
    'official-denied',
    'official-authorized',
  ]) {
    testWidgets('row and reauthorized detail use the same owner seam: $mode', (
      tester,
    ) async {
      size(tester, const Size(1280, 1000));
      final port = _Port();
      addTearDown(port.changes.close);
      final defaultCommunity = mode == 'community-default';
      final permitted = mode != 'official-denied';
      await tester.pumpWidget(
        app(
          defaultCommunity
              ? CommunityShipsPanel(
                  port: port,
                  targetRef: _target,
                  name: 'Synthetic organization',
                  onBack: () {},
                )
              : CommunityShipsPanel(
                  port: port,
                  targetRef: _target,
                  name: 'Synthetic organization',
                  onBack: () {},
                  ownerTargetFactory: permitted
                      ? _authorizedOfficialTarget
                      : null,
                  avatarAccess: _denyMedia,
                  includeSocialActions: false,
                ),
        ),
      );
      await tester.pumpAndSettle();
      // The row's, then the right column's: it shows the first ship at once.
      final listMenus = find.descendant(
        of: find.byType(CommunityShipsPanel),
        matching: find.byType(UserAvatarMenu),
      );
      expect(listMenus, permitted ? findsNWidgets(2) : findsNothing);
      if (permitted) {
        final menu = tester.widget<UserAvatarMenu>(listMenus.first);
        expect(
          menu.target?.source,
          defaultCommunity ? 'community' : 'officialFleet',
        );
        expect(menu.target?.reference, defaultCommunity ? _owner : _profile);
        expect(
          menu.target?.contextRef,
          defaultCommunity ? _target : 'officialFleet:74',
        );
        expect(menu.includeSocialActions, defaultCommunity);
      }
      final details = find.byKey(ValueKey('community-ship-details-$_ship'));
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      // 1280 wide: the details open inline in the side column (option D).
      expect(find.byType(CommunityShipDetailPane), findsOneWidget);
      expect(port.reads, greaterThan(1), reason: 'The details reread.');
      final detailMenus = find.descendant(
        of: find.byType(CommunityShipDetailPane),
        matching: find.byType(UserAvatarMenu),
      );
      expect(detailMenus, permitted ? findsOneWidget : findsNothing);
      if (permitted) {
        final menu = tester.widget<UserAvatarMenu>(detailMenus);
        expect(
          menu.target?.source,
          defaultCommunity ? 'community' : 'officialFleet',
        );
        expect(menu.target?.reference, defaultCommunity ? _owner : _profile);
        expect(menu.includeSocialActions, defaultCommunity);
      }
      expect(port.imageReads, 0);
      expect(port.reportWrites, 0);
      expect(port.mediaReads, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}
