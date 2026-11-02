import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_member_role_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import '../friends/social_layout_test.dart' show loadFonts;
import 'community_image_test_support.dart' show settleCommunityImages;
import 'community_workspace_test.dart' show mediaChunk, workspacePayload;
import 'community_holo_test_support.dart';

// Portable to the verified 0.7.1 release source and the current source. No
// member-board implementation or release-specific row type is imported here.
const _organization = '00000000000000000000000000000001';
const _otherOrganization = '00000000000000000000000000000002';
const _organizationName = '合成远航组织';
const _announcementTitle = '合成公告 · 出发前确认集合安排';
const _time = '2026-10-16T20:30:00Z';
const _names = ['合成指挥员', '合成领航员', '合成后勤员'];
const _gameIds = [
  'Fixture_Commander',
  'Fixture_Navigator',
  'Fixture_Logistics',
];
final _members = List.generate(
  3,
  (i) => (i + 11).toRadixString(16).padLeft(32, '0'),
);
late List<Uint8List> _media;
final _captures = <Map<String, Object?>>[];

Future<Uint8List> _syntheticPortrait(int index) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const colors = [
    Color(0xff2e6081),
    Color(0xff48735b),
    Color(0xff735f88),
    Color(0xff626a78),
  ];
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 64, 64),
    Paint()..color = colors[index],
  );
  canvas.drawCircle(
    const Offset(32, 23),
    11,
    Paint()..color = const Color(0xffe6edf2),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(13, 39, 38, 30),
      const Radius.circular(18),
    ),
    Paint()..color = const Color(0xffe6edf2),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

Map<String, Object?> _workspaceInput(String target, String query) {
  final input = workspacePayload(target: target, query: query);
  final template = Map<String, Object?>.from(
    (input['members'] as List).single as Map,
  );
  return {
    ...input,
    'code': 'VISUAL071',
    'name': _organizationName,
    'description': '仅用于整页视觉对照的合成组织资料。',
    'hasLogo': true,
    'hasBanner': false,
    'timeZoneId': 'America/Regina',
    'timeZoneStandardOffsetMinutes': -360,
    'timeZoneUsesDaylightSaving': false,
    'activityWindows': [
      {
        'days': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
        'startTime': '19:00',
        'endTime': '22:30',
        'endsNextDay': false,
      },
      {
        'days': ['Sat', 'Sun'],
        'startTime': '08:00',
        'endTime': '22:00',
        'endsNextDay': false,
      },
    ],
    'websiteUrl': null,
    'externalContacts': [
      {'platform': 'QQ', 'value': 'SYNTHETIC-001'},
      {'platform': 'Discord', 'value': 'fixture-only'},
    ],
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
        key: true,
    },
    'offset': 0,
    'next': null,
    'totalCount': 3,
    'matchedCount': 3,
    'fetchedAt': _time,
    'members': [
      for (var i = 0; i < 3; i++)
        {
          ...template,
          'memberRef': _members[i],
          'callsign': _names[i],
          'gameName': _gameIds[i],
          'roleTitle': ['组织指挥官', '领航员', '后勤员'][i],
          'roleColor': ['#F2B84B', '#4CA2D1', '#A57FE5'][i],
          'isSelf': i == 0,
          'isOwner': i == 0,
          'hasAvatar': true,
          'avatarVersion': sha256.convert(_media[i + 1]).toString(),
          'online': true,
          'liveStatus': 'InGame',
          'ship': ['C2 Hercules', 'Avenger Titan', 'Cutlass Black'][i],
          'location': ['Orison', 'New Babbage', 'Everus Harbor'][i],
          'serverRegion': ['USA', 'EUROPE', 'AUSTRALIA'][i],
          'hasServerSession': true,
          'arrivalPendingConfirmation': false,
          'arrivalTargetCode': null,
          'joinedAt': _time,
          'lastUpdated': _time,
        },
    ],
  };
}

Map<String, Object?> _announcementInput(String target) {
  final author = {
    'memberRef': _members.first,
    'callsign': _names.first,
    'gameId': _gameIds.first,
    'roleTitle': '组织指挥官',
    'roleColor': '#F2B84B',
    'hasAvatar': true,
  };
  return {
    'schemaVersion': 1,
    'targetRef': target,
    'revision': 1,
    'canManage': true,
    'current': {
      'announcementRef': 'c' * 32,
      'title': _announcementTitle,
      'content': '合成公告正文：请在出发前确认成员和集合时间。',
      'state': 'published',
      'revision': 1,
      'publishedAt': _time,
      'updatedAt': _time,
      'archivedAt': null,
      'withdrawnAt': null,
      'author': author,
      'editor': author,
    },
    'history': [],
    'offset': 0,
    'next': null,
    'totalHistoryCount': 0,
    'refreshedAt': _time,
  };
}

final class _VisualOrganizationPort
    implements
        CommunitiesPort,
        CommunityWorkspacePort,
        CommunityAnnouncementsPort,
        CommunityChatPort,
        CommunityShipsPort,
        CommunityMemberRolePort {
  final _changes = StreamController<void>.broadcast(sync: true);
  final _example = ExampleCommunities();
  int writes = 0, workspaceReads = 0, mediaReads = 0;
  bool _closed = false;
  final unexpected = <String>[];
  @override
  Stream<void> get invalidations => _changes.stream;
  @override
  bool get announcementsAvailable => true;
  @override
  bool get chatAvailable => true;
  @override
  bool get chatReadReceiptsAvailable => false;
  @override
  bool get shipsAvailable => true;
  @override
  bool get memberRoleAvailable => true;

  List<CommunityCard> get cards => [
    CommunityCard(
      targetRef: _organization,
      organizationRef: _organization,
      name: _organizationName,
      relationship: 'owner',
      memberCount: 3,
      description: '合成组织资料',
      logo: 'data:image/png;base64,${base64Encode(_media.first)}',
    ),
    CommunityCard(
      targetRef: _otherOrganization,
      organizationRef: _otherOrganization,
      name: '合成协作组织',
      relationship: 'member',
      memberCount: 3,
      logo: 'data:image/png;base64,${base64Encode(_media.last)}',
    ),
  ];
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async => CommunityDirectory(view, query, cards, totalCount: 2);
  @override
  Future<String> execute(String action, String targetRef) async {
    writes++;
    throw UnsupportedError('Visual fixture never writes community data');
  }

  @override
  Future<CommunityWorkspace> readWorkspace(
    String target,
    String query,
    int offset,
  ) async {
    workspaceReads++;
    return CommunityWorkspace.parse(_workspaceInput(target, query));
  }

  @override
  Future<Map<String, Object?>> readMedia(
    String target,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async {
    mediaReads++;
    final index = kind == 'logo' ? 0 : _members.indexOf(memberRef!) + 1;
    return mediaChunk(_media[index], offset, kind: kind, memberRef: memberRef);
  }

  @override
  Future<CommunityAnnouncementsPage> readAnnouncements(
    String target, {
    int offset = 0,
    int? expectedRevision,
  }) async => CommunityAnnouncementsPage.parse(_announcementInput(target));
  @override
  Future<CommunityChatPage> readChat(
    String target, {
    int after = 0,
    int before = 0,
  }) async => CommunityChatPage.parse({
    'schemaVersion': 1,
    'targetRef': target,
    'unreadCount': 0,
    'latestSequence': 0,
    'oldestSequence': 0,
    'canSend': false,
    'hasOlder': false,
    'serverTime': _time,
    'messages': [],
  });
  @override
  Future<CommunityShipsPage> readShips(
    String target, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) => _example.readShips(
    target,
    offset: offset,
    revision: revision,
    query: query,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add(invocation.memberName.toString());
    throw UnsupportedError(
      'No detail or write command is used in the visual fixture',
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _example.close();
    await _changes.close();
  }
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  Size physicalSize,
  AppearanceMode mode,
) async {
  final directory = Platform.environment['ORGANIZATION_071_CAPTURE_DIR'];
  if (directory == null) return;
  final source =
      Platform.environment['ORGANIZATION_071_SOURCE_LABEL'] ?? 'current';
  Map<String, double>? rect(Finder finder) {
    if (finder.evaluate().isEmpty) return null;
    final bounds = tester.getRect(finder.first);
    return {
      'left': bounds.left,
      'top': bounds.top,
      'width': bounds.width,
      'height': bounds.height,
      'right': bounds.right,
      'bottom': bounds.bottom,
    };
  }

  final workspace = find.byType(CommunityWorkspaceView);
  final memberViewport = find.descendant(
    of: workspace,
    matching: find.byType(ListView),
  );
  final anchorRects = <String, Object?>{
    'shell': rect(find.byType(StarBridgeShell)),
    'outerOrganizationCard': rect(
      find.ancestor(of: workspace, matching: find.byType(Card)),
    ),
    'workspace': rect(workspace),
    'header': rect(find.byKey(const Key('community-header-information'))),
    'membersTab': rect(find.byKey(const Key('community-section-members'))),
    'search': rect(find.byKey(const Key('community-member-search'))),
    'searchSubmit': rect(
      find.byKey(const Key('community-member-search-submit')),
    ),
    'memberViewport': rect(memberViewport),
    for (var i = 0; i < _members.length; i++) ...{
      'member${i + 1}Identity': rect(
        find.descendant(
          of: memberViewport,
          matching: find.textContaining(_names[i]),
        ),
      ),
      'member${i + 1}Card': rect(
        find.descendant(
          of: find.byKey(ValueKey('member-row-${_members[i]}')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).border != null,
          ),
        ),
      ),
    },
  };
  final scrollables = tester
      .stateList<ScrollableState>(
        find.descendant(of: memberViewport, matching: find.byType(Scrollable)),
      )
      .where(
        (state) => const [
          AxisDirection.down,
          AxisDirection.up,
        ].contains(state.position.axisDirection),
      );
  final viewportGeometry = [
    for (final state in scrollables)
      {
        'axis': state.position.axisDirection.name,
        'pixels': state.position.pixels,
        'viewportDimension': state.position.viewportDimension,
        'maxScrollExtent': state.position.maxScrollExtent,
      },
  ];
  final name =
      'organization-full-${physicalSize.width.toInt()}x${physicalSize.height.toInt()}-${mode.name}';
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    expect(Size(image.width.toDouble(), image.height.toDouble()), physicalSize);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(bytes);
    _captures.add({
      'file': '$name.png',
      'source': source,
      'sourceRef':
          Platform.environment['ORGANIZATION_071_SOURCE_REF'] ?? 'working-tree',
      'width': image.width,
      'height': image.height,
      'mode': mode.name,
      'devicePixelRatio': 1,
      'textScale': 1,
      'sha256': sha256.convert(bytes).toString(),
      'scope': 'StarBridgeApp / StarBridgeShell / CommunitiesPage / CommunityWorkspaceView with header, tabs and members',
      'nativeViewport': true,
      'viewportExpanded': false,
      'croppedOrStitched': false,
      'anchorRects': anchorRects,
      'memberViewportGeometry': viewportGeometry,
      'headerState':
          'full; narrower initial overview expanded through its actual control',
    });
    image.dispose();
    final input = {
      'workspace': _workspaceInput(_organization, ''),
      'announcements': _announcementInput(_organization),
      'mediaSha256': _media
          .map((bytes) => sha256.convert(bytes).toString())
          .toList(),
    };
    await File('$directory/organization-full-manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'source': source,
        'verifiedReleaseBaseline': 'cf0cf8f8e482238dd16a99e9a2c1c3b3f8a69cb3',
        'synthetic': true,
        'realAccountAcceptance': false,
        'visibleClientLaunched': false,
        'userAccountScreenshotCopied': false,
        'inputSha256': sha256
            .convert(utf8.encode(jsonEncode(input)))
            .toString(),
        'fixtureSha256': sha256
            .convert(
              await File(
                'test/features/communities/community_071_visual_acceptance_test.dart',
              ).readAsBytes(),
            )
            .toString(),
        'theme': 'future-restraint-a',
        'locale': 'zh-CN',
        'interaction': 'standard',
        'navigation':
            'real primary navigation followed by joined-organization shortcut',
        'coverage': [
          'shell chrome and navigation',
          'two joined-organization shortcuts',
          'outer organization container',
          'full identity/presence/activity/announcement/contact header',
          'section navigation and permissions',
          'three synthetic member identities and avatars',
          'one member-area vertical viewport',
          'no data writes or account operations',
        ],
        'images': _captures,
      }),
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadFonts();
    _media = await Future.wait(List.generate(4, _syntheticPortrait));
  });
  final sizes = [
    const Size(2560, 1392),
    if (Platform.environment['ORGANIZATION_071_CAPTURE_COMPACT'] == '1') ...[
      const Size(1280, 1000),
      const Size(900, 1000),
    ],
  ];
  for (final physicalSize in sizes) {
    testWidgets(
      'full organization page from shell navigation at ${physicalSize.width.toInt()}x${physicalSize.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = physicalSize;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final port = _VisualOrganizationPort();
        final composition = AppComposition.forTest(
          windowChrome: InMemoryWindowChrome(),
          communitiesPortFactory: () => port,
          shellChrome: InMemoryShellChrome(
            initial: InMemoryShellChrome.connectedProjection,
          ),
          preferences: InMemoryAppPreferences(
            initial: AppPreferences.defaults.copyWith(
              appearanceMode: AppearanceMode.dark,
              interactionStyle: InteractionStyle.standard,
            ),
          ),
          accountPort: InMemoryAccountAdapter.forReview(
            AccountReviewState.signedIn,
          ),
        );
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
        await tester.tap(find.byKey(const ValueKey('/communities')));
        await settleCommunityImages(tester);
        final shortcut = find.byKey(
          const ValueKey('community-shortcut-$_organization'),
        );
        await tester.ensureVisible(shortcut);
        await tester.tap(shortcut);
        await settleCommunityImages(tester);
        // Open the same full information header through its real control when
        // the narrower shell starts in its compact overview state.
        final expandHeader = find.byKey(const Key('community-header-expand'));
        if (expandHeader.evaluate().isNotEmpty) {
          await tester.tap(expandHeader);
          await settleCommunityImages(tester);
        }
        expect(find.byType(StarBridgeShell), findsOneWidget);
        expect(find.byType(CommunityWorkspaceView), findsOneWidget);
        expect(composition.communities.selected?.key, _organization);
        // Holo shell (2026-10-23): the name and announcement sit on the deck,
        // the online, activity and contact facts right below it.
        final header = find.byKey(const Key('community-header-information'));
        expect(header, findsOneWidget);
        expect(find.text(_organizationName), findsWidgets);
        expect(find.textContaining(_announcementTitle), findsWidgets);
        expect(
          find.descendant(
            of: header,
            matching: find.textContaining('SYNTHETIC-001'),
          ),
          findsWidgets,
        );
        await enterCommunitySection(tester);
        for (final section in [
          'members',
          'chat',
          'ships',
          'broadcast',
          'manage',
        ]) {
          expect(
            find.byKey(ValueKey('community-section-$section')),
            findsOneWidget,
          );
        }
        final memberList = find.byKey(
          PageStorageKey((
            port as CommunityWorkspacePort,
            _organization,
            'members',
          )),
        );
        expect(memberList, findsOneWidget);
        for (final name in _names) {
          expect(
            find.descendant(
              of: memberList,
              matching: find.textContaining(name),
            ),
            findsOneWidget,
          );
        }
        final vertical = tester
            .stateList<ScrollableState>(
              find.descendant(
                of: memberList,
                matching: find.byType(Scrollable),
              ),
            )
            .where(
              (state) => const [
                AxisDirection.down,
                AxisDirection.up,
              ].contains(state.position.axisDirection),
            );
        expect(
          vertical,
          hasLength(1),
          reason: 'The complete member region has one vertical viewport',
        );
        expect(port.workspaceReads, greaterThan(0));
        expect(port.mediaReads, greaterThanOrEqualTo(4));
        expect(port.writes, 0);
        expect(port.unexpected, isEmpty);
        expect(
          MediaQuery.textScalerOf(
            tester.element(find.byType(CommunityWorkspaceView)),
          ).scale(1),
          1,
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, boundary, physicalSize, AppearanceMode.dark);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}
