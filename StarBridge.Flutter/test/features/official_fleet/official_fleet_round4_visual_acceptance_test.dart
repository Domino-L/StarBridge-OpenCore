import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/starbridge_shell.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/common/organization_member_board.dart';
import 'package:starbridge_flutter/features/common/organization_workspace_frame.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_page.dart';
import 'package:starbridge_flutter/features/party_rooms/room_display.dart'
    show roomDate;
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import '../communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../communities/community_workspace_test.dart' show workspacePayload;
import '../friends/social_layout_test.dart' show loadFonts;
import '../communities/community_holo_test_support.dart';

const _sourceRef = 'officialFleet:74';
const _communityRef = '00000000000000000000000000000074';
const _size = Size(1280, 1000);
final _communityTime = DateTime.utc(2026, 10, 16, 20, 30);
final _images = <Map<String, Object?>>[];
final _comparisons = <Map<String, Object?>>[];

List<OfficialFleetMember> _members(int count) => [
  for (var index = 1; index <= count; index++)
    OfficialFleetMember(
      memberRef: index.toRadixString(16).padLeft(64, '0'),
      callsign: '合成舰队成员 ${index.toString().padLeft(3, '0')}',
      gameId: 'Fixture_Fleet_${index.toString().padLeft(3, '0')}',
      officialRankName: index % 3 == 0 ? 'Officer' : 'Member',
      officialRankValue: index % 3 == 0 ? 4 : 1,
      presence: OfficialFleetMemberPresence.unknown,
      server: const OfficialFleetMemberField(
        OfficialFleetMemberFieldState.unknown,
      ),
      ship: const OfficialFleetMemberField(
        OfficialFleetMemberFieldState.unknown,
      ),
      location: const OfficialFleetMemberField(
        OfficialFleetMemberFieldState.unknown,
      ),
      starBridgeConnected: null,
      identityState: OfficialFleetMemberIdentityState.scm,
    ),
];

class _Roster implements OfficialFleetMembersPort {
  _Roster(this.count) : members = _members(count);
  final int count;
  final List<OfficialFleetMember> members;
  final requests = <Map<String, Object?>>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) async {
    requests.add({
      'sourceRef': query.sourceRef,
      'search': query.search,
      'filter': query.filter.name,
      'page': query.pageNumber,
      'pageSize': query.pageSize,
    });
    final matches = members
        .where(
          (row) => '${row.callsign} ${row.gameId} ${row.officialRankName}'
              .toLowerCase()
              .contains(query.search.toLowerCase()),
        )
        .toList();
    final start = (query.pageNumber - 1) * query.pageSize;
    return OfficialFleetMemberDirectorySnapshot.available(
      query: query,
      members: matches.skip(start).take(query.pageSize).toList(),
      totalCount: matches.length,
      onlineCount: null,
      inGameCount: null,
      totalPages: matches.isEmpty
          ? 1
          : (matches.length / query.pageSize).ceil(),
      coverage: OfficialFleetRosterCoverage.completeOfficialRoster,
      supportedFilters: const {OfficialFleetMemberFilter.all},
      runtimeCapabilities: const OfficialFleetMemberRuntimeCapabilities.none(),
    );
  }

  @override
  Future<void> close() async {}
}

Map<String, Object?> _communityInput() {
  final seed = workspacePayload(target: _communityRef);
  final template = Map<String, Object?>.from(
    (seed['members'] as List).single as Map,
  );
  return {
    ...seed,
    'code': 'ROUND4',
    'name': '合成对照组织',
    'hasLogo': false,
    'description': '第四轮全应用对照，全部为合成资料。',
    'websiteUrl': null,
    'fetchedAt': _communityTime.toIso8601String(),
    'offset': 0,
    'next': null,
    'totalCount': 3,
    'matchedCount': 3,
    'access': {
      for (final key in [
        'isOwner',
        'canEditProfile',
        'canEditLogo',
        'canEditBanner',
        'canReviewApplications',
        'canRemoveMembers',
        'canCreateInvite',
        'canManageAnnouncements',
        'canViewLogs',
      ])
        key: false,
    },
    'members': [
      for (var index = 1; index <= 3; index++)
        {
          ...template,
          'memberRef': index.toRadixString(16).padLeft(32, '0'),
          'callsign': '合成参照成员 ${index.toString().padLeft(3, '0')}',
          'gameName': 'Fixture_Community_$index',
          'roleTitle': '合成队员',
          'roleColor': '#4CA2D1',
          'isSelf': false,
          'isOwner': false,
          'hasAvatar': false,
          'online': true,
          'liveStatus': 'InGame',
          'serverRegion': 'USA',
          'hasServerSession': true,
          'ship': 'C2 Hercules',
          'location': 'Orison',
          'arrivalPendingConfirmation': false,
          'arrivalTargetCode': null,
        },
    ],
  };
}

class _JoinedCommunity implements CommunitiesPort, CommunityWorkspacePort {
  int writes = 0;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async => CommunityDirectory(view, query, const [
    CommunityCard(
      targetRef: _communityRef,
      organizationRef: _communityRef,
      name: '合成对照组织',
      relationship: 'member',
      memberCount: 3,
    ),
  ], totalCount: 1);
  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) async => CommunityWorkspace.parse(_communityInput());
  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async => throw const CommunityFailure('unavailable');
  @override
  Future<String> execute(String action, String targetRef) async {
    writes++;
    throw UnsupportedError('Visual fixture never writes');
  }

  @override
  Future<void> close() async {}
}

AppComposition _composition(_Roster roster, _JoinedCommunity community) =>
    AppComposition.forTest(
      windowChrome: InMemoryWindowChrome(),
      shellChrome: InMemoryShellChrome(
        initial: InMemoryShellChrome.connectedProjection,
      ),
      accountPort: InMemoryAccountAdapter.forReview(
        AccountReviewState.signedIn,
      ),
      preferences: InMemoryAppPreferences(
        initial: AppPreferences.defaults.copyWith(
          appearanceMode: AppearanceMode.dark,
          interactionStyle: InteractionStyle.standard,
        ),
      ),
      communitiesPortFactory: () => community,
      officialFleetMembersPort: roster,
      officialFleetPort: InMemoryOfficialFleetAdapter(
        initial: OfficialFleetSnapshot.available(
          fleet: OfficialFleetSummary(
            sourceRef: _sourceRef,
            sid: 'ROUND4',
            name: '合成主舰队',
            officialRankName: 'Officer',
            officialRankValue: 4,
            profile: OfficialFleetProfileDetails(
              memberCount: roster.count,
              rsiDescription: '第四轮完整页面合成资料。',
              languageLabels: const ['简体中文'],
            ),
          ),
          freshness: OfficialFleetFreshness.live,
          observedAtUtc: _communityTime,
          profileReadState: OfficialFleetProfileReadState.available,
          profileObservedAtUtc: _communityTime,
          resourceVersion: 1,
        ),
      ),
    );

Map<String, double> _rect(Rect value) => {
  'left': value.left,
  'top': value.top,
  'right': value.right,
  'bottom': value.bottom,
  'width': value.width,
  'height': value.height,
};
Map<String, Object?> _style(WidgetTester tester, Finder finder) {
  final element = finder.evaluate().single;
  final value = element.widget as Text;
  final style = DefaultTextStyle.of(element).style.merge(value.style);
  return {
    'fontSize': style.fontSize,
    'fontWeight': style.fontWeight?.value,
    'colorArgb': style.color?.toARGB32(),
    'height': style.height,
    'letterSpacing': style.letterSpacing,
    'fontFamily': style.fontFamily,
  };
}

Finder _key(String value) => find.byKey(Key(value));
Finder _coverage() => find.byWidgetPredicate(
  (widget) => widget is Text && (widget.data?.startsWith('名单来源') ?? false),
);
Finder _pageSize() => _key('official-fleet-members-page-size');
Finder _viewport(String kind) => find
    .ancestor(
      of: find.byType(OrganizationMemberBoard),
      matching: kind == 'fleet'
          ? find.byType(SingleChildScrollView)
          : find.byType(ListView),
    )
    .first;
ScrollPosition _position(WidgetTester tester, String kind) => tester
    .state<ScrollableState>(
      find
          .descendant(of: _viewport(kind), matching: find.byType(Scrollable))
          .first,
    )
    .position;

Map<String, Object?> _geometry(WidgetTester tester, String kind) {
  final prefix = kind == 'fleet'
      ? 'official-fleet-members'
      : 'community-member';
  final header = _key(
    // Both member lists sit on the holo shell's lower screen, under the
    // same bar (communities adopted the shell on 2026-10-23).
    'official-fleet-header-compact',
  );
  final nav = _key(
    kind == 'fleet'
        ? 'official-fleet-tab-members'
        : 'community-section-members',
  );
  final search = _key('$prefix-search');
  final submit = _key('$prefix-search-submit');
  final label = find.descendant(
    of: find.byType(OrganizationMemberHeader),
    matching: find.text('成员'),
  );
  final summary = _key('$prefix-summary');
  final updated = _key('$prefix-updated');
  return {
    'headerCard': _rect(tester.getRect(header)),
    'membersNavigation': _rect(tester.getRect(nav)),
    'headerToNavigationGap':
        tester.getRect(nav).top - tester.getRect(header).bottom,
    'search': _rect(tester.getRect(search)),
    'inputDecorator': _rect(
      tester.getRect(
        find.descendant(of: search, matching: find.byType(InputDecorator)),
      ),
    ),
    'searchSubmit': _rect(tester.getRect(submit)),
    'memberColumnLabel': _rect(tester.getRect(label)),
    'allHeaderLabels': [
      for (final element
          in find
              .descendant(
                of: find.byType(OrganizationMemberHeader),
                matching: find.byType(Text),
              )
              .evaluate())
        {
          'text': (element.widget as Text).data,
          'rect': _rect(tester.getRect(find.byWidget(element.widget))),
          'style': _style(tester, find.byWidget(element.widget)),
        },
    ],
    'searchToHeaderTextGap':
        tester.getRect(label).top - tester.getRect(search).bottom,
    'summary': {
      'rect': _rect(tester.getRect(summary)),
      'text': tester.widget<Text>(summary).data,
      'style': _style(tester, summary),
    },
    'updated': {
      'rect': _rect(tester.getRect(updated)),
      'text': tester.widget<Text>(updated).data,
      'style': _style(tester, updated),
    },
    'searchSubmitText': find
        .descendant(of: submit, matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .toList(),
  };
}

void _sharedPresentation(WidgetTester tester, int expectedRows) {
  expect(find.byType(StarBridgeShell), findsOneWidget);
  // The main fleet's holo header is full-bleed (approved 2026-10-21), so it
  // skips the community page inset; the work surface below is shared.
  expect(
    find.byType(OrganizationWorkspacePage).evaluate().length,
    lessThanOrEqualTo(1),
  );
  expect(find.byType(OrganizationWorkspaceSurface), findsOneWidget);
  expect(find.byType(OrganizationWorkspaceFrame), findsOneWidget);
  expect(find.byType(OrganizationMemberBoard), findsOneWidget);
  expect(find.byType(OrganizationMemberHeader), findsOneWidget);
  expect(find.byType(OrganizationMemberRow), findsNWidgets(expectedRows));
  expect(find.byType(OrganizationMemberRoleBadge), findsNWidgets(expectedRows));
  expect(find.textContaining('组织暂时无法加载'), findsNothing);
  expect(find.textContaining('组织暂時無法載入'), findsNothing);
  expect(
    find.byKey(const ValueKey('community-shortcut-$_communityRef')),
    findsOneWidget,
  );
}

Future<void> _scroll(
  WidgetTester tester,
  String kind, {
  required bool bottom,
}) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final position = _position(tester, kind);
    if (bottom
        ? position.pixels >= position.maxScrollExtent - .1
        : position.pixels <= .1) {
      return;
    }
    await tester.timedDrag(
      _viewport(kind),
      Offset(0, bottom ? -900 : 900),
      const Duration(milliseconds: 650),
    );
    await settleCommunityImages(tester);
  }
  fail('Real scroll did not reach ${bottom ? 'footer' : 'top'}');
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  AppComposition composition,
  _Roster roster,
  String scenario,
  String kind,
  String frame,
) async {
  final directory = Platform.environment['OFFICIAL_FLEET_ROUND4_CAPTURE_DIR'];
  if (directory == null) return;
  final board = tester.widget<OrganizationMemberBoard>(
    find.byType(OrganizationMemberBoard),
  );
  final projection = composition.officialFleet.members.projection.value;
  final viewport = tester.getRect(_viewport(kind));
  final position = _position(tester, kind);
  final pagination = find.byType(OrganizationMemberPaginationBar);
  final footer = _coverage();
  final input = {
    'fleetCount': roster.count,
    'sourceRef': _sourceRef,
    'members': roster.members
        .map(
          (row) => {
            'reference': row.memberRef,
            'callsign': row.callsign,
            'gameId': row.gameId,
            'rank': row.officialRankName,
            'rankValue': row.officialRankValue,
          },
        )
        .toList(),
    'runtimeCapabilities': 'none',
    'community': _communityInput(),
  };
  final rows = [
    for (final row in tester.widgetList<OrganizationMemberRow>(
      find.byType(OrganizationMemberRow),
    ))
      {
        'reference': row.entry.reference,
        'role': row.entry.role,
        'rect': _rect(
          tester.getRect(
            find.byKey(ValueKey('member-row-${row.entry.reference}')),
          ),
        ),
        'fullyVisible':
            viewport.contains(
              tester
                  .getRect(
                    find.byKey(ValueKey('member-row-${row.entry.reference}')),
                  )
                  .topLeft,
            ) &&
            viewport.contains(
              tester
                      .getRect(
                        find.byKey(
                          ValueKey('member-row-${row.entry.reference}'),
                        ),
                      )
                      .bottomRight -
                  const Offset(.01, .01),
            ),
        'rowWidget': row.runtimeType.toString(),
        'identityWidget': row.entry.identity.runtimeType.toString(),
      },
  ];
  final geometry = _geometry(tester, kind);
  final filename = '$scenario-$frame-1280x1000-dark.png';
  final fingerprints = <String, String>{};
  for (final path in [
    'lib/features/common/organization_workspace_frame.dart',
    'lib/features/common/organization_member_row.dart',
    'lib/features/common/organization_member_board.dart',
    'lib/features/common/organization_member_controls.dart',
    'lib/features/official_fleet/official_fleet_page.dart',
    'lib/features/official_fleet/official_fleet_members_section.dart',
    'lib/features/official_fleet/official_fleet_members_controls.dart',
    'lib/features/official_fleet/official_fleet_workspace_sync_notice.dart',
    'lib/features/official_fleet/official_fleet_members_module.dart',
    'lib/features/communities/community_workspace_controller.dart',
    'lib/features/communities/community_workspace_view.dart',
  ]) {
    fingerprints[path] = sha256
        .convert(File(path).readAsBytesSync())
        .toString();
  }
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    expect(Size(image.width.toDouble(), image.height.toDouble()), _size);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    await Directory(directory).create(recursive: true);
    await File('$directory/$filename').writeAsBytes(bytes);
    _images.add({
      'file': filename,
      'scenario': scenario,
      'kind': kind,
      'frame': frame,
      'width': 1280,
      'height': 1000,
      'mode': 'dark',
      'locale': 'zh-CN',
      'devicePixelRatio': 1,
      'textScale': 1,
      'nativeViewport': true,
      'viewportExpanded': false,
      'croppedOrStitched': false,
      'sha256': sha256.convert(bytes).toString(),
      'sourceHashes': fingerprints,
      'inputSha256': sha256.convert(utf8.encode(jsonEncode(input))).toString(),
      'sourceRef': _sourceRef,
      'sourceRequests': List.of(roster.requests),
      'actualLastReadAtUtc': projection.lastReadAtUtc?.toIso8601String(),
      'clockPolicy': 'production module actual DateTime.now owner retained; UI must equal community roomDate(actualLastReadAtUtc)',
      'page': kind == 'fleet' ? projection.query?.pageNumber : 1,
      'pageSize': kind == 'fleet' ? projection.query?.pageSize : null,
      'totalCount': kind == 'fleet' ? projection.totalCount : 3,
      'loadedRowCount': rows.length,
      'visibleColumns': board.columns.keys,
      'geometry': geometry,
      'members': rows,
      'viewport': {
        ..._rect(viewport),
        'offset': position.pixels,
        'maxScrollExtent': position.maxScrollExtent,
      },
      'paginationRect': _rect(tester.getRect(pagination)),
      'pageSizeRect': _pageSize().evaluate().isEmpty
          ? null
          : _rect(tester.getRect(_pageSize())),
      'coverageRect': footer.evaluate().isEmpty
          ? null
          : _rect(tester.getRect(footer)),
      'coverageText': footer.evaluate().isEmpty
          ? null
          : tester.widget<Text>(footer).data,
      'renderedBoardText': find
          .descendant(
            of: find.byType(OrganizationMemberBoard),
            matching: find.byType(Text),
          )
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .toList(),
    });
    await File('$directory/manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'synthetic': true,
        'realAccountAcceptance': false,
        'fixtureSha256': sha256
            .convert(
              await File(
                'test/features/official_fleet/official_fleet_round4_visual_acceptance_test.dart',
              ).readAsBytes(),
            )
            .toString(),
        'source': 'canonical shared production pages through StarBridgeApp and real navigation',
        'navigationAndScrolling': 'Actual sidebar activation, joined shortcut, previous/next buttons and drag gestures; no direct command invocation or scroll mutation',
        'visibleClientLaunched': false,
        'accountOperations': false,
        'images': _images,
        'geometryComparisons': _comparisons,
      }),
    );
  });
}

Future<(GlobalKey, AppComposition, _JoinedCommunity)> _open(
  WidgetTester tester,
  _Roster roster,
) async {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final community = _JoinedCommunity();
  final composition = _composition(roster, community);
  final boundary = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: StarBridgeApp(
        composition: composition,
        canPresentIdentityPrompt: () => false,
      ),
    ),
  );
  await settleCommunityImages(tester);
  await tester.tap(find.byKey(const ValueKey('/fleet')));
  await settleCommunityImages(tester);
  expect(find.byType(OfficialFleetPage), findsOneWidget);
  // Two screens: the top screen's rail opens the member list.
  await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
  await settleCommunityImages(tester);
  return (boundary, composition, community);
}

void _fleetText(WidgetTester tester, AppComposition composition, int total) {
  final projection = composition.officialFleet.members.projection.value;
  expect(projection.query?.pageSize, 50);
  expect(projection.totalCount, total);
  expect(projection.lastReadAtUtc, isNotNull);
  final context = tester.element(find.byType(OrganizationMemberBoard));
  expect(
    tester.widget<Text>(_key('official-fleet-members-summary')).data,
    '舰队成员 · $total / $total',
  );
  expect(
    tester.widget<Text>(_key('official-fleet-members-updated')).data,
    '资料更新 · ${roomDate(context, projection.lastReadAtUtc!)}',
  );
  final board = tester.widget<OrganizationMemberBoard>(
    find.byType(OrganizationMemberBoard),
  );
  expect(board.columns.keys, ['member', 'role']);
  expect(board.onlineCount, isNull);
  expect(board.inGameCount, isNull);
  expect(
    find.descendant(
      of: _key('official-fleet-members-search-submit'),
      matching: find.text('搜索'),
    ),
    findsOneWidget,
  );
}

void _footerVisible(WidgetTester tester) {
  final viewport = tester.getRect(_viewport('fleet'));
  final pagination = tester.getRect(
    find.byType(OrganizationMemberPaginationBar),
  );
  final coverage = tester.getRect(_coverage());
  expect(pagination.top, greaterThanOrEqualTo(viewport.top));
  expect(coverage.bottom, lessThanOrEqualTo(viewport.bottom + .1));
  // Holo work surfaces (2026-10-23) keep the source note beside the paging
  // controls when there is room, below them otherwise.
  expect(
    coverage.top >= pagination.bottom || coverage.left >= pagination.right,
    isTrue,
  );
  final previous = tester.getRect(_key('official-fleet-members-previous-page'));
  final pageSize = tester.getRect(_pageSize());
  expect(pageSize.left, greaterThan(previous.right));
  expect(pageSize.center.dy, closeTo(previous.center.dy, 1));
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'round4 single-page fleet matches community control spacing and shared presentation',
    (tester) async {
      final roster = _Roster(3);
      final (boundary, composition, community) = await _open(tester, roster);
      _sharedPresentation(tester, 3);
      _fleetText(tester, composition, 3);
      expect(_key('official-fleet-members-jump-input'), findsNothing);
      expect(_key('official-fleet-members-jump'), findsNothing);
      expect(find.text('第 1 / 1 页'), findsNothing);
      for (final direction in ['previous', 'next']) {
        final button = find.byWidgetPredicate(
          (w) =>
              w is StarBridgeActionButton &&
              w.controlKey == Key('official-fleet-members-$direction-page'),
        );
        expect(
          tester.widget<StarBridgeActionButton>(button).onActivate,
          isNull,
        );
      }
      final fleetGeometry = _geometry(tester, 'fleet');
      await _capture(
        tester,
        boundary,
        composition,
        roster,
        'fleet-single-3',
        'fleet',
        'top',
      );
      await _scroll(tester, 'fleet', bottom: true);
      _footerVisible(tester);
      await _capture(
        tester,
        boundary,
        composition,
        roster,
        'fleet-single-3',
        'fleet',
        'footer',
      );
      await tester.tap(find.byKey(const ValueKey('/communities')));
      await settleCommunityImages(tester);
      await tester.tap(
        find.byKey(const ValueKey('community-shortcut-$_communityRef')),
      );
      await settleCommunityImages(tester);
      await enterCommunitySection(tester);
      expect(find.byType(CommunityWorkspaceView), findsOneWidget);
      _sharedPresentation(tester, 3);
      final communityGeometry = _geometry(tester, 'community');
      final fleetSubmit = fleetGeometry['searchSubmit'] as Map<String, double>;
      final communitySubmit =
          communityGeometry['searchSubmit'] as Map<String, double>;
      _comparisons.add({
        'kind': 'single-fleet-vs-community',
        'fleet': fleetGeometry,
        'community': communityGeometry,
        'headerGapEqual':
            fleetGeometry['headerToNavigationGap'] ==
            communityGeometry['headerToNavigationGap'],
        'searchHeaderGapEqual':
            fleetGeometry['searchToHeaderTextGap'] ==
            communityGeometry['searchToHeaderTextGap'],
        'searchButtonSizeEqual':
            fleetSubmit['width'] == communitySubmit['width'] &&
            fleetSubmit['height'] == communitySubmit['height'],
        'summaryAndUpdatedStyleEqual': ['summary', 'updated'].every(
          (field) =>
              jsonEncode((fleetGeometry[field] as Map)['style']) ==
              jsonEncode((communityGeometry[field] as Map)['style']),
        ),
        'dateValuesIntentionallyDiffer': true,
      });
      await _capture(
        tester,
        boundary,
        composition,
        roster,
        'community-reference-3',
        'community',
        'top',
      );
      // The header itself intentionally differs (main-fleet holo header).
      for (final gap in ['searchToHeaderTextGap']) {
        expect(
          fleetGeometry[gap] as double,
          closeTo(communityGeometry[gap] as double, .01),
          reason: gap,
        );
      }
      expect(fleetSubmit['width'], communitySubmit['width']);
      expect(fleetSubmit['height'], communitySubmit['height']);
      for (final field in ['summary', 'updated']) {
        expect(
          (fleetGeometry[field] as Map)['style'],
          (communityGeometry[field] as Map)['style'],
        );
      }
      expect(community.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'round4 real 120-member source paginates 50-50-20 with footer after rows',
    (tester) async {
      final roster = _Roster(120);
      final (boundary, composition, community) = await _open(tester, roster);
      for (var page = 1; page <= 3; page++) {
        await _scroll(tester, 'fleet', bottom: false);
        final projection = composition.officialFleet.members.projection.value;
        expect(projection.query?.pageNumber, page);
        expect(projection.totalPages, 3);
        expect(projection.members.length, page < 3 ? 50 : 20);
        expect(
          projection.members.first.gameId,
          'Fixture_Fleet_${((page - 1) * 50 + 1).toString().padLeft(3, '0')}',
        );
        expect(
          projection.members.last.gameId,
          'Fixture_Fleet_${(page < 3 ? page * 50 : 120).toString().padLeft(3, '0')}',
        );
        _sharedPresentation(tester, page < 3 ? 50 : 20);
        _fleetText(tester, composition, 120);
        expect(_key('official-fleet-members-jump-input'), findsOneWidget);
        expect(_key('official-fleet-members-jump'), findsOneWidget);
        expect(find.text('第 $page / 3 页'), findsOneWidget);
        await _capture(
          tester,
          boundary,
          composition,
          roster,
          'fleet-120-page$page',
          'fleet',
          'top',
        );
        await _scroll(tester, 'fleet', bottom: true);
        _footerVisible(tester);
        await _capture(
          tester,
          boundary,
          composition,
          roster,
          'fleet-120-page$page',
          'fleet',
          'footer',
        );
        if (page < 3) {
          await tester.tap(_key('official-fleet-members-next-page'));
          await settleCommunityImages(tester);
        }
        expect(tester.takeException(), isNull);
      }
      expect(
        roster.requests
            .where((r) => r['pageSize'] == 50)
            .map((r) => r['page'])
            .toSet(),
        containsAll([1, 2, 3]),
      );
      expect(community.writes, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
