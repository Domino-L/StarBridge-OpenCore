import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_member_board.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_controller.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_members.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_member_role_port.dart';
import 'package:starbridge_flutter/features/communities/community_member_runtime.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_image.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_section.dart';
import 'package:starbridge_flutter/features/party_rooms/room_display.dart'
    show roomDate;

import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';

import '../communities/community_workspace_test.dart';
import '../friends/social_layout_test.dart' show app, loadFonts;

class _CaptureFrame extends StatelessWidget {
  const _CaptureFrame({required this.captureKey, required this.child});
  final GlobalKey captureKey;
  final Widget child;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: captureKey,
    child: ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    ),
  );
}

class _CurrentFleetPort implements OfficialFleetMembersPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<void> close() async {}
  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) async => parseOfficialFleetMembers({
    'schemaVersion': 1,
    'sourceRef': query.sourceRef,
    'search': query.search,
    'filter': 'all',
    'pageNumber': query.pageNumber,
    'pageSize': query.pageSize,
    'totalCount': 3,
    'totalPages': 1,
    'coverage': 'scmRegisteredMembers',
    'onlineCount': null,
    'inGameCount': null,
    'members': [
      for (var i = 0; i < 3; i++)
        {
          'memberRef': (i + 1).toRadixString(16).padLeft(64, '0'),
          'callsign': ['舰桥成员', 'SCM 成员', '—'][i],
          'avatarUrl': null,
          'officialRankName': 'Member',
          'officialRankValue': null,
          'presence': 'unknown',
          'identityState': ['starBridge', 'scm', 'restricted'][i],
          'starBridgeConnected': i == 0 ? true : null,
          if (i == 0)
            'profileTargetRef': (i + 1).toRadixString(16).padLeft(64, '0'),
        },
    ],
  }, query);
}

enum _RuntimeScene {
  visible,
  online,
  away,
  offline,
  manualOffline,
  invisible,
  paused,
  unknown,
  noSession,
  serverHidden,
  shipHidden,
  locationRestricted,
  shipRecognizing,
  locationRecognizing,
  serverSync,
  arrivalTarget,
  arrivalWithoutTarget,
  lowConfidence,
  defaultRole,
  visibleOther,
}

Map<String, Object?> _runtimeInput(_RuntimeScene scene) => switch (scene) {
  _RuntimeScene.visible || _RuntimeScene.defaultRole => const {},
  _RuntimeScene.visibleOther => {
    'serverRegion': 'EUROPE',
    'ship': 'Avenger Titan',
    'location': 'New Babbage',
  },
  _RuntimeScene.online => {'liveStatus': 'AppOnline'},
  _RuntimeScene.away => {'liveStatus': 'Away'},
  _RuntimeScene.offline => {'online': false, 'liveStatus': 'Offline'},
  _RuntimeScene.manualOffline => {'liveStatus': 'ManualOffline'},
  _RuntimeScene.invisible => {'liveStatus': 'Invisible'},
  _RuntimeScene.paused => {'liveStatus': 'Paused'},
  _RuntimeScene.unknown => {'liveStatus': 'Unknown'},
  _RuntimeScene.noSession => {'hasServerSession': false},
  _RuntimeScene.serverHidden => {'serverRegion': null},
  _RuntimeScene.shipHidden => {'ship': null},
  _RuntimeScene.locationRestricted => {'location': null},
  _RuntimeScene.shipRecognizing => {'ship': 'Unknown'},
  _RuntimeScene.locationRecognizing => {'location': 'Unknown'},
  _RuntimeScene.serverSync => {
    'serverRegion': 'Unknown',
    'hasServerSession': null,
    'ship': 'Unknown',
    'location': 'Unknown',
  },
  _RuntimeScene.arrivalTarget => {
    'arrivalPendingConfirmation': true,
    'arrivalTargetCode': 'ARRIVAL_PORT',
    'arrivalTargetLabels': {'zhHans': '奥里森', 'en': 'Orison'},
  },
  _RuntimeScene.arrivalWithoutTarget => {
    'arrivalPendingConfirmation': true,
    'arrivalTargetCode': null,
  },
  _RuntimeScene.lowConfidence => {
    'location': 'Unknown',
    'locationHiddenReason': 'lowConfidence',
  },
};

(String, String, String) _expectedRuntime(_RuntimeScene scene) =>
    switch (scene) {
      _RuntimeScene.online ||
      _RuntimeScene.away ||
      _RuntimeScene.offline ||
      _RuntimeScene.manualOffline ||
      _RuntimeScene.invisible ||
      _RuntimeScene.paused ||
      _RuntimeScene.unknown => ('未进入游戏', '未进入游戏', '未进入游戏'),
      _RuntimeScene.noSession => ('未进入服务器', '未进入服务器', '未进入服务器'),
      _RuntimeScene.serverHidden => ('暂无可见信息', 'C2 Hercules', 'Orison'),
      _RuntimeScene.shipHidden => ('美服', '暂无可见信息', 'Orison'),
      _RuntimeScene.locationRestricted => ('美服', 'C2 Hercules', '暂无可见信息'),
      _RuntimeScene.shipRecognizing => ('美服', '等待识别', 'Orison'),
      _RuntimeScene.locationRecognizing => ('美服', 'C2 Hercules', '等待识别'),
      _RuntimeScene.serverSync => ('等待服务器同步', '等待服务器同步', '等待服务器同步'),
      _RuntimeScene.arrivalTarget => ('美服', 'C2 Hercules', '奥里森 · 地点待确认'),
      _RuntimeScene.arrivalWithoutTarget => ('美服', 'C2 Hercules', '地点待确认'),
      _RuntimeScene.lowConfidence => ('美服', 'C2 Hercules', '低可信度位置'),
      _RuntimeScene.visibleOther => ('欧服', 'Avenger Titan', 'New Babbage'),
      _ => ('美服', 'C2 Hercules', 'Orison'),
    };

class _Port extends WorkspaceTestPort implements CommunityMemberRolePort {
  _Port({
    this.owner = false,
    this.privacyOnly = false,
    this.unknownOnly = false,
    this.scenes,
    this.multiplePages = false,
  }) {
    reader = (target, query, offset) async {
      final payload = workspacePayload(target: target, query: query);
      final template = Map<String, Object?>.from(
        (payload['members'] as List).single as Map,
      );
      final activeScenes =
          scenes ??
          (privacyOnly
              ? [
                  _RuntimeScene.offline,
                  _RuntimeScene.manualOffline,
                  _RuntimeScene.invisible,
                  _RuntimeScene.paused,
                ]
              : unknownOnly
              ? [_RuntimeScene.unknown]
              : _RuntimeScene.values);
      final count = activeScenes.length;
      payload['totalCount'] = count + (multiplePages ? 5 : 0);
      payload['matchedCount'] = count + (multiplePages ? 5 : 0);
      payload['next'] = multiplePages ? count : null;
      payload['fetchedAt'] = DateTime(
        2026,
        10,
        16,
        20,
        30,
      ).toUtc().toIso8601String();
      (payload['access'] as Map)['isOwner'] = owner;
      payload['members'] = List.generate(
        count,
        (i) => <String, Object?>{
          ...template,
          'memberRef': (i + 1).toRadixString(16).padLeft(32, '0'),
          'callsign': '成员 ${(i + 1).toString().padLeft(2, '0')}',
          'gameName': privacyOnly ? '' : 'Pilot-${i + 1}',
          'isSelf': !privacyOnly && i == 0,
          'isOwner': !privacyOnly && owner && i == 0,
          'roleTitle': privacyOnly
              ? '成员'
              : activeScenes[i] == _RuntimeScene.defaultRole
              ? ''
              : owner && i == 0
              ? '所有者'
              : i.isEven
              ? '探索'
              : '后勤',
          'roleColor': privacyOnly
              ? '#9DAAB3'
              : activeScenes[i] == _RuntimeScene.defaultRole
              ? '#9DAAB3'
              : i.isEven
              ? '#36A966'
              : '#C74949',
          'online': true,
          'liveStatus': 'InGame',
          'ship': 'C2 Hercules',
          'serverRegion': 'USA',
          'location': 'Orison',
          'arrivalPendingConfirmation': false,
          'arrivalTargetCode': null,
          'hasServerSession': true,
          ..._runtimeInput(activeScenes[i]),
        },
      );
      return CommunityWorkspace.parse(payload);
    };
  }
  final bool owner, privacyOnly, unknownOnly;
  final List<_RuntimeScene>? scenes;
  final bool multiplePages;
  @override
  bool get memberRoleAvailable => owner;
  @override
  Future<CommunityMemberRole> readMemberRole({
    String? targetRef,
    String? memberRef,
    String? editRef,
  }) => throw UnsupportedError('Read-only render fixture');
  @override
  Future<CommunityMemberRoleOutcome> saveMemberRole(
    String requestId,
    String editRef,
    String roleKey, {
    bool confirmUncertainRetry = false,
  }) => throw UnsupportedError('Read-only render fixture');
}

Future<CommunityWorkspaceController> _community(_Port port) async {
  final model = CommunityWorkspaceController(port, 'a' * 32);
  addTearDown(() async {
    model.dispose();
    await port.changes.close();
  });
  await model.load();
  return model;
}

Widget _communityView(CommunityWorkspaceController model) => AnimatedBuilder(
  animation: model,
  builder: (context, _) => CommunityWorkspaceMembers(
    context: context,
    currentModel: () => model,
    isMounted: () => context.mounted,
    port: model.port,
    organizationKey: 'fixture-organization',
    search: _search(model),
    contextInvalidations: const Stream.empty(),
    onGovernanceChanged: () async {},
    openDialog: (_) async => false,
  ).build(),
);
final _searches = <CommunityWorkspaceController, TextEditingController>{};
TextEditingController _search(CommunityWorkspaceController model) =>
    _searches.putIfAbsent(model, () {
      final search = TextEditingController();
      addTearDown(() {
        _searches.remove(model);
        search.dispose();
      });
      return search;
    });

final _captured = <Map<String, Object?>>[];

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String name, {
  List<String> coverage = const [],
  bool fitContent = true,
}) async {
  final destination = Platform.environment['MEMBER_BOARD_CAPTURE_DIR'];
  if (destination == null) return;
  final fleet = name.startsWith('official-fleet-current');
  final originalViewport = tester.view.physicalSize;
  var viewportExpanded = false;
  // Keep the actual production viewport and expand only the synthetic capture
  // surface to its complete content, so all 20 mapped rows can be inspected.
  if (!fleet && fitContent) {
    final vertical = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .where(
          (state) => const [
            AxisDirection.down,
            AxisDirection.up,
          ].contains(state.position.axisDirection),
        )
        .toList();
    expect(
      vertical,
      hasLength(1),
      reason: 'The member region must have one vertical viewport',
    );
    final extent = vertical.single.position.maxScrollExtent;
    if (extent > 1) {
      tester.view.physicalSize = Size(
        tester.view.physicalSize.width,
        tester.view.physicalSize.height + extent.ceilToDouble(),
      );
      viewportExpanded = true;
      await tester.pumpAndSettle();
    }
  }
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(destination).create(recursive: true);
    final bytes = data!.buffer.asUint8List();
    await File('$destination/$name.png').writeAsBytes(bytes);
    _captured.add({
      'file': '$name.png',
      'width': image.width,
      'height': image.height,
      'sha256': sha256.convert(bytes).toString(),
      'synthetic': true,
      'realAccountAcceptance': false,
      'viewportExpanded': viewportExpanded,
      'normalViewport': !fitContent,
      'originalViewportWidth': originalViewport.width,
      'originalViewportHeight': originalViewport.height,
      'viewportNote': fitContent
          ? 'complete-content evidence; community viewport expands only when content exceeds its native height'
          : 'native 1600x1000 viewport; natural clipping at the window bottom is not a nested member-list viewport',
      'source': fleet
          ? 'synthetic Bridge contract payload'
          : 'synthetic community workspace payload',
      'productionMapping': fleet
          ? [
              'parseOfficialFleetMembers',
              'OfficialFleetMembersModule',
              'officialFleetMemberEntry',
              'OrganizationMemberBoard',
              'OrganizationMemberRow',
            ]
          : [
              'CommunityWorkspace.parse',
              'CommunityWorkspaceController',
              'CommunityWorkspaceMembers.build',
              'communityMemberRuntimeCells',
              'OrganizationMemberBoard',
              'OrganizationMemberRow',
            ],
      'coverage': coverage.isNotEmpty
          ? coverage
          : fleet
          ? [
              'current Bridge capabilities: identity and RSI rank only',
              'three identity presentations',
              'natural three-row height and nearby pagination',
              'column-count aware layout',
              'content-aligned member and rank columns',
            ]
          : [
              '20 rows through community production mapping',
              'shared owner/member layout',
              'single vertical viewport with natural list height',
              'restored community column order and bounded shared board width',
              'legacy role colors and public-state stripe/text presentation',
              'typed runtime metadata with original inherited body presentation',
            ],
    });
    await File('$destination/capture-manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 2,
        'synthetic': true,
        'realAccountAcceptance': false,
        'visibleClientLaunched': false,
        'visualDirection': 'user-approved restored community presentation; typed runtime, privacy and identity behavior preserved',
        'captureSurface': 'isolated Flutter widget tests; theme background included; complete-content images plus an explicitly marked native viewport; no cropping or stitching',
        'fixtureSource':
            'test/features/common/organization_member_board_test.dart',
        'fixtureSourceSha256': sha256
            .convert(
              await File(
                'test/features/common/organization_member_board_test.dart',
              ).readAsBytes(),
            )
            .toString(),
        'images': _captured,
      }),
    );
    image.dispose();
  });
}

void _size(WidgetTester tester, double width, [double height = 1000]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

void _assertRuntimeColors(WidgetTester tester, OrganizationMemberEntry entry) {
  final row = find.byKey(ValueKey('member-row-${entry.reference}'));
  final body = Theme.of(tester.element(row)).textTheme.bodyMedium!;
  for (final cell in [
    entry.runtime.server,
    entry.runtime.ship,
    entry.runtime.location,
  ]) {
    if (cell.text.isEmpty) continue;
    final texts = find.descendant(of: row, matching: find.text(cell.text));
    expect(texts, findsWidgets);
    for (final element in texts.evaluate()) {
      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byElementPredicate((candidate) => candidate == element),
          matching: find.byType(RichText),
        ),
      );
      expect(richText.text.style?.color, body.color);
      expect(richText.text.style?.fontWeight, body.fontWeight);
      expect(richText.text.style?.fontSize, body.fontSize);
    }
  }
}

void _assertSummary(WidgetTester tester, CommunityWorkspaceController model) {
  final workspace = model.workspace!;
  final summary = find.byKey(const Key('community-member-summary'));
  final updated = find.byKey(const Key('community-member-updated'));
  final text = tester.widget<Text>(summary).data!;
  expect(text, '组织成员 · ${workspace.matchedCount} / ${workspace.totalCount}');
  expect(
    tester.widget<Text>(updated).data,
    '资料更新 · ${roomDate(tester.element(updated), workspace.fetchedAt)}',
  );
  expect(
    tester.getTopLeft(updated).dx,
    greaterThan(tester.getTopLeft(summary).dx),
  );
  expect(find.text('在线与游戏人数仅统计当前页'), findsNothing);
  final board = tester.widget<OrganizationMemberBoard>(
    find.byType(OrganizationMemberBoard),
  );
  expect(board.filters, isEmpty);
  expect(board.onFilter, isNull);
  expect(board.pagination.page, isNull);
  for (final filter in OrganizationMemberFilter.values) {
    expect(
      find.byKey(Key('community-member-filter-${filter.name}')),
      findsNothing,
    );
  }
  expect(find.byKey(const Key('community-member-jump-input')), findsNothing);
  expect(find.byKey(const Key('community-member-page-size')), findsNothing);
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('community-member-search')))
        .decoration
        ?.labelText,
    '搜索成员、呼号或职务',
  );
  final previous = find.byKey(const Key('community-member-previous-page'));
  final next = find.byKey(const Key('community-member-next-page'));
  expect(previous, findsOneWidget);
  expect(next, findsOneWidget);
  expect(
    tester.widget<ButtonStyleButton>(previous).onPressed,
    workspace.offset == 0 ? isNull : isNotNull,
  );
  expect(
    tester.widget<ButtonStyleButton>(next).onPressed,
    workspace.next == null ? isNull : isNotNull,
  );
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'four private/offline forms stay identical and visible despite a legacy filter state',
    (tester) async {
      _size(tester, 1280);
      final model = await _community(_Port(privacyOnly: true));
      final key = GlobalKey();
      await tester.pumpWidget(
        app(_CaptureFrame(captureKey: key, child: _communityView(model))),
      );
      await tester.pumpAndSettle();
      final rows = tester
          .widgetList<OrganizationMemberRow>(find.byType(OrganizationMemberRow))
          .toList();
      expect(rows, hasLength(4));
      for (final row in rows) {
        expect(row.entry.presence, OrganizationMemberPresence.offline);
        expect(
          (row.entry.server, row.entry.ship, row.entry.location),
          ('未进入游戏', '未进入游戏', '未进入游戏'),
        );
      }
      final colors = tester
          .widgetList<Text>(find.text('离线'))
          .map((text) => text.style?.color)
          .toSet();
      expect(colors, hasLength(1));
      expect(find.text('未进入游戏'), findsNWidgets(12));
      final board = tester.widget<OrganizationMemberBoard>(
        find.byType(OrganizationMemberBoard),
      );
      expect(board.onlineCount, 0);
      expect(board.inGameCount, 0);
      _assertSummary(tester, model);
      expect(find.text('共享已暂停'), findsNothing);
      expect(find.text('隐身'), findsNothing);
      await _capture(
        tester,
        key,
        'privacy-four-identical-1280-dark',
        coverage: [
          'ordinary offline, manual offline, invisible, paused while actually in game',
          'identical offline state, three original notInGame cells, zero online/game counts',
          'production privacy normalization and member entry mapping',
        ],
      );
      model.setMemberFilter('online');
      await tester.pumpAndSettle();
      expect(find.byType(OrganizationMemberRow), findsNWidgets(4));
      model.setMemberFilter('inGame');
      await tester.pumpAndSettle();
      expect(find.byType(OrganizationMemberRow), findsNWidgets(4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unknown presence stays non-online without being hidden by a legacy filter state',
    (tester) async {
      _size(tester, 1280);
      final model = await _community(_Port(unknownOnly: true));
      final key = GlobalKey();
      await tester.pumpWidget(
        app(_CaptureFrame(captureKey: key, child: _communityView(model))),
      );
      await tester.pumpAndSettle();
      final row = tester.widget<OrganizationMemberRow>(
        find.byType(OrganizationMemberRow),
      );
      expect(row.entry.presence, OrganizationMemberPresence.offline);
      expect(find.text('离线'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      expect(find.text('未进入游戏'), findsNWidgets(3));
      expect(
        (row.entry.server, row.entry.ship, row.entry.location),
        ('未进入游戏', '未进入游戏', '未进入游戏'),
      );
      final status = find.byType(OrganizationMemberStatus);
      expect(
        find.descendant(
          of: find.byType(OrganizationMemberRow),
          matching: find.byType(PositionedDirectional),
        ),
        findsOneWidget,
        reason: 'An unknown public state uses the same offline status stripe',
      );
      expect(
        find.descendant(
          of: status,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
          ),
        ),
        findsNothing,
      );
      final board = tester.widget<OrganizationMemberBoard>(
        find.byType(OrganizationMemberBoard),
      );
      expect(board.onlineCount, 0);
      expect(board.inGameCount, 0);
      _assertSummary(tester, model);
      await _capture(
        tester,
        key,
        'unknown-not-online-1280-dark',
        coverage: [
          'online=true and raw status Unknown does not imply online',
          'unknown state has no status dot',
          'unknown public state uses the offline status stripe and label',
          'each runtime cell uses the original notInGame text',
          'zero public online/game counts and no hidden filtering of unknown members',
        ],
      );
      model.setMemberFilter('online');
      await tester.pumpAndSettle();
      expect(find.byType(OrganizationMemberRow), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'governance actions appear only for a permitted source with shared community chrome',
    (tester) async {
      _size(tester, 1280);
      final model = await _community(_Port(owner: true));
      await tester.pumpWidget(app(_communityView(model)));
      await tester.pumpAndSettle();
      final rows = tester
          .widgetList<OrganizationMemberRow>(find.byType(OrganizationMemberRow))
          .toList();
      expect(rows.every((row) => row.showActions), isTrue);
      expect(rows.first.entry.actions, isNull);
      expect(rows.skip(1).any((row) => row.entry.actions != null), isTrue);
      final row = find.byType(OrganizationMemberRow).at(1);
      final status = find.descendant(
        of: row,
        matching: find.byType(OrganizationMemberStatus),
      );
      expect(
        find.ancestor(of: status, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(find.byType(OrganizationMemberRoleBadge), findsWidgets);
      expect(find.byType(UserAvatarMenu), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final scenario in <(String, List<_RuntimeScene>)>[
    ('visible-values', [_RuntimeScene.visible]),
    ('online-and-away', [_RuntimeScene.online, _RuntimeScene.away]),
    ('no-server-session', [_RuntimeScene.noSession]),
    (
      'not-disclosed',
      [
        _RuntimeScene.serverHidden,
        _RuntimeScene.shipHidden,
        _RuntimeScene.locationRestricted,
      ],
    ),
    (
      'identifying',
      [
        _RuntimeScene.shipRecognizing,
        _RuntimeScene.locationRecognizing,
        _RuntimeScene.serverSync,
      ],
    ),
    ('arrival-with-target', [_RuntimeScene.arrivalTarget]),
    ('arrival-without-target', [_RuntimeScene.arrivalWithoutTarget]),
    ('uncertain-location', [_RuntimeScene.lowConfidence]),
    ('default-role', [_RuntimeScene.defaultRole]),
  ]) {
    testWidgets(
      'approved runtime wording uses production mapping ${scenario.$1}',
      (tester) async {
        _size(tester, 1280, 650);
        final model = await _community(_Port(scenes: scenario.$2));
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            _CaptureFrame(
              captureKey: key,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('社区组织 · 合成资料', style: TextStyle(fontSize: 22)),
                    const SizedBox(height: 20),
                    Expanded(child: _communityView(model)),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final board = tester.widget<OrganizationMemberBoard>(
          find.byType(OrganizationMemberBoard),
        );
        expect(board.rows, hasLength(scenario.$2.length));
        for (var i = 0; i < board.rows.length; i++) {
          final row = board.rows[i];
          final scene = scenario.$2[i];
          final input = model.workspace!.members.singleWhere(
            (member) => member.memberRef == row.reference,
          );
          expect(row.identity, isA<OrganizationMemberIdentity>());
          expect(
            (row.identity as OrganizationMemberIdentity).avatar,
            isA<CommunityWorkspaceImage>(),
          );
          final mapped = communityMemberRuntimeCells(
            input,
            text: (key) =>
                memberBoardTextForLocale(const Locale('zh', 'CN'), key),
            regionText: (region) => region == 'US'
                ? '美服'
                : region == 'EU'
                ? '欧服'
                : region,
            locale: const Locale('zh', 'CN'),
          );
          expect((row.server, row.ship, row.location), _expectedRuntime(scene));
          expect((
            mapped.server.text,
            mapped.ship.text,
            mapped.location.text,
          ), _expectedRuntime(scene));
          _assertRuntimeColors(tester, row);
          if (scene == _RuntimeScene.defaultRole) expect(row.roleColor, isNull);
        }
        final rows = find.byType(OrganizationMemberRow);
        if (scenario.$1 == 'online-and-away') {
          for (var i = 0; i < 2; i++) {
            expect(
              find.descendant(of: rows.at(i), matching: find.text('未进入游戏')),
              findsNWidgets(3),
            );
          }
        }
        _assertSummary(tester, model);
        expect(find.text('未共享'), findsNothing);
        expect(find.text('当前不可见'), findsNothing);
        expect(find.text('—'), findsNothing);
        expect(find.text('未公开'), findsNothing);
        expect(find.text('识别中'), findsNothing);
        expect(find.textContaining('位置待确认'), findsNothing);
        expect(find.text('位置不确定'), findsNothing);
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          key,
          'runtime-${scenario.$1}-1280-dark',
          coverage: [
            ...scenario.$2.map((scene) => 'scene:${scene.name}'),
            '0.7.1 wording with confirmed server fallback through community production mapper',
            if (scenario.$1 == 'online-and-away') 'three original notInGame values per non-game row with inherited body styling',
          ],
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'multi-page community retains matched total summary and source-owned navigation without page controls',
    (tester) async {
      _size(tester, 1280);
      final model = await _community(_Port(multiplePages: true));
      await tester.pumpWidget(app(_communityView(model)));
      await tester.pumpAndSettle();
      _assertSummary(tester, model);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('community-member-summary')))
            .data,
        '组织成员 · 25 / 25',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [900.0, 1280.0, 1600.0]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      for (final owner in [true, false]) {
        testWidgets(
          'render shared community owner=$owner ${width.toInt()} ${mode.name}',
          (tester) async {
            _size(tester, width);
            final model = await _community(_Port(owner: owner));
            final key = GlobalKey();
            await tester.pumpWidget(
              app(
                _CaptureFrame(
                  captureKey: key,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '社区组织 · ${owner ? '所有者' : '普通成员'} · 合成资料',
                          style: const TextStyle(fontSize: 22),
                        ),
                        const SizedBox(height: 20),
                        Expanded(child: _communityView(model)),
                      ],
                    ),
                  ),
                ),
                mode,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(OrganizationMemberBoard), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (!owner && width == 1600 && mode == AppearanceMode.dark) {
              await _capture(
                tester,
                key,
                'community-member-1600-dark-viewport',
                fitContent: false,
                coverage: [
                  'native 1600x1000 viewport before any complete-content expansion',
                  'same community production model and widget as the full-content image',
                  'restored community visual at its natural desktop scale',
                  'natural viewport-bottom clipping only; single scroll area verified separately',
                ],
              );
            }
            await _capture(
              tester,
              key,
              'community-${owner ? 'owner' : 'member'}-${width.toInt()}-${mode.name}',
            );
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
      testWidgets(
        'render official fleet source with no runtime ${width.toInt()} ${mode.name}',
        (tester) async {
          _size(tester, width);
          final port = _CurrentFleetPort();
          final module = createOfficialFleetMembersModule(port);
          addTearDown(module.dispose);
          final key = GlobalKey();
          await tester.pumpWidget(
            app(
              _CaptureFrame(
                captureKey: key,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: OfficialFleetMembersSection(
                      sourceRef: 'officialFleet:7',
                      module: module,
                    ),
                  ),
                ),
              ),
              mode,
            ),
          );
          await tester.pumpAndSettle();
          final board = tester.widget<OrganizationMemberBoard>(
            find.byType(OrganizationMemberBoard),
          );
          expect(
            module.projection.value.availability,
            OfficialFleetMemberDirectoryAvailability.available,
          );
          expect(board.rows, hasLength(3));
          expect(board.error, isNull);
          expect(board.columns.keys, ['member', 'role']);
          expect(board.filters.length, lessThanOrEqualTo(1));
          expect(board.onlineCount, isNull);
          expect(board.inGameCount, isNull);
          expect(tester.takeException(), isNull);
          await _capture(
            tester,
            key,
            'official-fleet-current-${width.toInt()}-${mode.name}',
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'twenty mixed rows use production mapping and survive a legacy online filter state',
    (tester) async {
      _size(tester, 1280);
      final model = await _community(_Port());
      model.setMemberFilter('online');
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          _CaptureFrame(
            captureKey: key,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '共享成员行 · 20 行混合状态 · 合成资料',
                    style: TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 20),
                  Expanded(child: _communityView(model)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final board = tester.widget<OrganizationMemberBoard>(
        find.byType(OrganizationMemberBoard),
      );
      expect(board.rows, hasLength(20));
      expect(
        board.rows.map((row) => row.reference).toSet(),
        model.workspace!.members.map((member) => member.memberRef).toSet(),
      );
      for (final row in board.rows) {
        expect(row.identity, isA<OrganizationMemberIdentity>());
        expect(
          (row.identity as OrganizationMemberIdentity).avatar,
          isA<CommunityWorkspaceImage>(),
        );
        final index = int.parse(row.reference, radix: 16) - 1;
        expect((
          row.server,
          row.ship,
          row.location,
        ), _expectedRuntime(_RuntimeScene.values[index]));
        _assertRuntimeColors(tester, row);
      }
      _assertSummary(tester, model);
      expect(find.byType(OrganizationMemberRow), findsNWidgets(20));
      expect(tester.takeException(), isNull);
      await _capture(
        tester,
        key,
        'mixed-twenty-rows-1280-dark',
        coverage: [
          'all 20 rows come from CommunityWorkspace.parse and CommunityWorkspaceMembers.build',
          ..._RuntimeScene.values.map((scene) => 'scene:${scene.name}'),
          'all identities include production avatar fallback; consistent row geometry',
          'typed metadata does not change original runtime body styling; restored community role colors',
        ],
      );
      await tester.pumpWidget(const SizedBox());
      expect(model.workspace, isNotNull);
    },
  );
}
