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
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/starbridge_shell.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_port.dart';
import 'package:starbridge_flutter/features/communities/community_member_runtime.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_copy.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/party_rooms/room_display.dart'
    show roomServerRegion;
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import '../friends/social_layout_test.dart' show loadFonts;
import 'community_image_test_support.dart' show settleCommunityImages;
import 'community_workspace_test.dart' show mediaChunk, workspacePayload;
import 'community_holo_test_support.dart';

import 'package:starbridge_flutter/features/official_fleet/official_fleet_workspace_header.dart';

// A separate portable whole-app fixture. It does not modify the earlier
// three-in-game-member acceptance input, screenshots or release source.
const _target = '00000000000000000000000000000061';
const _time = '2026-10-16T20:30:00Z';
const _size = Size(1280, 1000);
const _role = '合成队员';
late Uint8List _avatar;
final _images = <Map<String, Object?>>[];
bool get _baseline =>
    Platform.environment['ORGANIZATION_071_RUNTIME_SOURCE_LABEL'] ==
    'release-0.7.1';

class _Case {
  const _Case(this.id, this.label, this.patch);
  final String id, label;
  final Map<String, Object?> patch;
  String get reference => id.codeUnits
      .fold<int>(0, (sum, item) => sum * 31 + item)
      .abs()
      .toRadixString(16)
      .padLeft(32, '0')
      .substring(0, 32);
  String get name => '合成 · $label';
  Map<String, Object?> get row => {
    ...(workspacePayload()['members'] as List).single as Map<String, Object?>,
    'memberRef': reference,
    'callsign': name,
    'gameName': 'Fixture_$id',
    'roleTitle': _role,
    'roleColor': '#4CA2D1',
    'isSelf': false,
    'isOwner': false,
    'hasAvatar': true,
    'avatarVersion': sha256.convert(_avatar).toString(),
    'online': true,
    'liveStatus': 'InGame',
    'serverRegion': 'USA',
    'hasServerSession': true,
    'ship': 'C2 Hercules',
    'location': 'Orison',
    'locationHiddenReason': null,
    'locationConfidence': null,
    'arrivalPendingConfirmation': false,
    'arrivalTargetCode': null,
    'joinedAt': _time,
    'lastUpdated': _time,
    ...patch,
  };
}

const _statusCases = [
  _Case('offline', '普通离线', {'online': false, 'liveStatus': 'Offline'}),
  _Case('online', '在线未进游戏', {'liveStatus': 'AppOnline'}),
  _Case('away', '暂离未进游戏', {'liveStatus': 'Away'}),
  _Case('manual', '手动离线', {'liveStatus': 'ManualOffline'}),
  _Case('invisible', '隐身', {'liveStatus': 'Invisible'}),
  _Case('paused', '暂停共享残留游戏', {'liveStatus': 'Paused'}),
  _Case('unknown', '未知状态', {'liveStatus': 'Unknown'}),
  _Case('playing', '游戏中对照', {}),
];
const _fieldCases = [
  _Case('hidden', '字段被隐藏', {
    'serverRegion': null,
    'ship': null,
    'location': null,
  }),
  _Case('recognition', '等待识别', {'ship': 'unknown', 'location': 'unknown'}),
  _Case('serverSync', '等待服务器同步', {
    'serverRegion': 'unknown',
    'hasServerSession': null,
    'ship': 'unknown',
    'location': 'unknown',
  }),
  _Case('pendingTarget', '地点待确认有目标', {
    'location': 'unknown',
    'arrivalPendingConfirmation': true,
    'arrivalTargetCode': 'Orison',
  }),
  _Case('pendingNoTarget', '地点待确认无目标', {
    'location': 'unknown',
    'arrivalPendingConfirmation': true,
  }),
  _Case('lowConfidence', '低可信度位置', {
    'location': 'unknown',
    'locationHiddenReason': 'lowConfidence',
  }),
  _Case('notInServer', '未进入服务器', {'hasServerSession': false}),
];

Future<Uint8List> _makeAvatar() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 64, 64),
    Paint()..color = const Color(0xff48735b),
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

Map<String, Object?> _workspaceInput(String scenario, List<_Case> cases) => {
  ...workspacePayload(target: _target),
  'code': 'RUNTIME071',
  'name': '合成运行状态组织',
  'description': '只用于相同输入的完整组织页面视觉对照。',
  'hasLogo': true,
  'hasBanner': false,
  'websiteUrl': null,
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
  ],
  'externalContacts': [
    {'platform': 'QQ', 'value': 'SYNTHETIC-RUNTIME-071'},
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
      key: false,
  },
  'offset': 0,
  'next': null,
  'totalCount': cases.length,
  'matchedCount': cases.length,
  'fetchedAt': _time,
  'members': [for (final item in cases) item.row],
};

Map<String, Object?> _announcementInput() => {
  'schemaVersion': 1,
  'targetRef': _target,
  'revision': 1,
  'canManage': false,
  'current': {
    'announcementRef': 'c' * 32,
    'title': '合成公告 · 运行状态对照',
    'content': '此页全部资料均为合成输入。',
    'state': 'published',
    'revision': 1,
    'publishedAt': _time,
    'updatedAt': _time,
    'archivedAt': null,
    'withdrawnAt': null,
    for (final who in ['author', 'editor'])
      who: {
        'memberRef': 'a' * 32,
        'callsign': '合成发布员',
        'gameId': 'Fixture_Author',
        'roleTitle': _role,
        'roleColor': '#4CA2D1',
        'hasAvatar': false,
      },
  },
  'history': [],
  'offset': 0,
  'next': null,
  'totalHistoryCount': 0,
  'refreshedAt': _time,
};

final class _RuntimePort
    implements
        CommunitiesPort,
        CommunityWorkspacePort,
        CommunityAnnouncementsPort {
  _RuntimePort(this.scenario, this.cases);
  final String scenario;
  final List<_Case> cases;
  final _changes = StreamController<void>.broadcast(sync: true);
  int reads = 0, mediaReads = 0, writes = 0;
  bool _closed = false;
  @override
  Stream<void> get invalidations => _changes.stream;
  @override
  bool get announcementsAvailable => true;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async => CommunityDirectory(view, query, [
    CommunityCard(
      targetRef: _target,
      organizationRef: _target,
      name: '合成运行状态组织',
      relationship: 'member',
      memberCount: cases.length,
      logo: 'data:image/png;base64,${base64Encode(_avatar)}',
    ),
  ], totalCount: 1);
  @override
  Future<String> execute(String action, String targetRef) async {
    writes++;
    throw UnsupportedError('Synthetic visual fixture does not write');
  }

  @override
  Future<CommunityWorkspace> readWorkspace(
    String target,
    String query,
    int offset,
  ) async {
    reads++;
    return CommunityWorkspace.parse(_workspaceInput(scenario, cases));
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
    return mediaChunk(_avatar, offset, kind: kind, memberRef: memberRef);
  }

  @override
  Future<CommunityAnnouncementsPage> readAnnouncements(
    String target, {
    int offset = 0,
    int? expectedRevision,
  }) async => CommunityAnnouncementsPage.parse(_announcementInput());
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused fixture method ${invocation.memberName}');
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _changes.close();
  }
}

Map<String, double> _rect(Rect rect) => {
  'left': rect.left,
  'top': rect.top,
  'right': rect.right,
  'bottom': rect.bottom,
  'width': rect.width,
  'height': rect.height,
};
Finder _card(String reference) => find
    .descendant(
      of: find.byKey(ValueKey('member-row-$reference')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).border != null,
      ),
    )
    .first;

Map<String, Object?> _textMetadata(WidgetTester tester, Finder finder) {
  final element = finder.evaluate().single;
  final text = element.widget as Text;
  final effective = DefaultTextStyle.of(element).style.merge(text.style);
  return {
    'text': text.data,
    'rect': _rect(tester.getRect(finder)),
    'colorArgb': effective.color?.toARGB32(),
    'fontSize': effective.fontSize,
    'fontWeight': effective.fontWeight?.value,
  };
}

List<String> _countText(String metric) {
  final keyed = find.byKey(ValueKey('community-presence-value-$metric'));
  return [
    ...keyed
        .evaluate()
        .map((element) => element.widget)
        .whereType<Text>()
        .map((text) => text.data ?? ''),
    ...find
        .descendant(of: keyed, matching: find.byType(Text))
        .evaluate()
        .map((element) => (element.widget as Text).data ?? ''),
  ];
}

Map<String, Object?> _memberMetadata(
  WidgetTester tester,
  _Case item,
  Finder viewport,
) {
  final card = _card(item.reference);
  final bounds = tester.getRect(card);
  final window = tester.getRect(viewport);
  final member = CommunityWorkspaceMember.parse(item.row);
  final context = tester.element(card);
  final runtime = communityMemberRuntime(
    member,
    text: (key) => workspaceText(context, key),
    regionText: (region) => roomServerRegion(context, region),
    locale: AppStrings.of(context).locale,
  );
  final expected = [runtime.server, runtime.ship, runtime.location];
  final matching =
      find
          .descendant(of: card, matching: find.byType(Text))
          .evaluate()
          .where((element) => expected.contains((element.widget as Text).data))
          .toList()
        ..sort(
          (a, b) => tester
              .getRect(find.byWidget(a.widget))
              .left
              .compareTo(tester.getRect(find.byWidget(b.widget)).left),
        );
  final runtimeCells = <String, Object?>{};
  // The portable read is the production runtime mapper. The recorded cells are
  // the actual rendered Text widgets, including effective inherited style.
  if (matching.length == 3) {
    for (var index = 0; index < 3; index++) {
      runtimeCells[['server', 'ship', 'location'][index]] = _textMetadata(
        tester,
        find.byWidget(matching[index].widget),
      );
    }
  }
  final texts = find
      .descendant(of: card, matching: find.byType(Text))
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .toList();
  return {
    'caseId': item.id,
    'memberRef': item.reference,
    'name': item.name,
    'raw': item.row,
    'parsed': {
      'online': member.online,
      'liveStatus': member.liveStatus,
      'server': member.serverRegion,
      'ship': member.ship,
      'location': member.location,
    },
    'cardRect': _rect(bounds),
    'identityTextRects': [
      for (final identityText in [item.name, 'Fixture_${item.id}'])
        _rect(
          tester.getRect(
            find.descendant(of: card, matching: find.text(identityText)),
          ),
        ),
    ],
    'fullyVisible':
        window.contains(bounds.topLeft) &&
        window.contains(bounds.bottomRight - const Offset(.01, .01)),
    'visibleRect': _rect(bounds.intersect(window)),
    'renderedText': texts,
    'runtimeFromProductionMapper': {
      'server': runtime.server,
      'ship': runtime.ship,
      'location': runtime.location,
    },
    'runtimeCells': runtimeCells,
    'stateText': texts
        .where(
          (value) =>
              const ['离线', '在线', '暂离', '游戏中', '共享已暂停', '—'].contains(value),
        )
        .toList(),
  };
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  _RuntimePort port,
  AppearanceMode mode,
  String frame,
  Finder viewport,
) async {
  final members = [
    for (final item in port.cases)
      if (find
          .byKey(ValueKey('member-row-${item.reference}'))
          .evaluate()
          .isNotEmpty)
        _memberMetadata(tester, item, viewport),
  ];
  final directory =
      Platform.environment['ORGANIZATION_071_RUNTIME_CAPTURE_DIR'];
  if (directory == null) return;
  final position = tester
      .state<ScrollableState>(
        find.descendant(of: viewport, matching: find.byType(Scrollable)).first,
      )
      .position;
  final header = find.byKey(const Key('community-header-information'));
  final imageInput = {
    'workspace': _workspaceInput(port.scenario, port.cases),
    'announcements': _announcementInput(),
    'mediaSha256': sha256.convert(_avatar).toString(),
  };
  final name = 'organization-runtime-${port.scenario}-${mode.name}-$frame.png';
  final sourceHashes = <String, String>{};
  for (final path in [
    'lib/features/communities/community_workspace_port.dart',
    'lib/features/communities/community_member_runtime.dart',
    'lib/features/communities/community_workspace_members.dart',
    'lib/features/communities/community_workspace_copy.dart',
    'lib/features/common/organization_member_row.dart',
    'lib/features/common/organization_member_copy.dart',
  ]) {
    if (File(path).existsSync()) {
      sourceHashes[path] = sha256
          .convert(File(path).readAsBytesSync())
          .toString();
    }
  }
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    expect(Size(image.width.toDouble(), image.height.toDouble()), _size);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name').writeAsBytes(bytes);
    image.dispose();
    _images.add({
      'file': name,
      'scenario': port.scenario,
      'mode': mode.name,
      'frame': frame,
      'source':
          Platform.environment['ORGANIZATION_071_RUNTIME_SOURCE_LABEL'] ??
          'current',
      'sourceRef':
          Platform.environment['ORGANIZATION_071_RUNTIME_SOURCE_REF'] ??
          'canonical-working-tree',
      'width': 1280,
      'height': 1000,
      'devicePixelRatio': 1,
      'textScale': 1,
      'nativeViewport': true,
      'viewportExpanded': false,
      'croppedOrStitched': false,
      'inputSha256': sha256
          .convert(utf8.encode(jsonEncode(imageInput)))
          .toString(),
      'sha256': sha256.convert(bytes).toString(),
      'sourceHashes': sourceHashes,
      'workspaceRect': _rect(
        tester.getRect(find.byType(CommunityWorkspaceView)),
      ),
      'headerRect': _rect(tester.getRect(header)),
      'viewport': {
        ..._rect(tester.getRect(viewport)),
        'scrollOffset': position.pixels,
        'maxScrollExtent': position.maxScrollExtent,
      },
      'headerCountText': {
        for (final metric in ['online', 'gaming', 'member'])
          metric: _countText(metric),
      },
      'members': members,
    });
    await File('$directory/runtime-full-manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'synthetic': true,
        'realAccountAcceptance': false,
        'releaseBaseline': 'cf0cf8f8e482238dd16a99e9a2c1c3b3f8a69cb3',
        'fixtureSha256': sha256
            .convert(
              await File(
                'test/features/communities/community_071_runtime_visual_acceptance_test.dart',
              ).readAsBytes(),
            )
            .toString(),
        'theme': 'future-restraint-a',
        'locale': 'zh-CN',
        'interaction': 'standard',
        'collection': 'complete native app frames; real shell navigation/header expansion and member-list scroll gestures',
        'intentionalDifferences': [
          'manual/invisible/paused/unknown public offline privacy projection',
          'serverSync and notInServer server cell explicit dash replacement only',
        ],
        'visibleClientLaunched': false,
        'accountOperations': false,
        'images': _images,
      }),
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadFonts();
    _avatar = await _makeAvatar();
  });
  for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
    for (final scenario in {
      'states': _statusCases,
      'fields': _fieldCases,
    }.entries) {
      testWidgets(
        'full runtime ${scenario.key} ${mode.name} from real organization navigation',
        (tester) async {
          tester.view.physicalSize = _size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final port = _RuntimePort(scenario.key, scenario.value);
          final composition = AppComposition.forTest(
            windowChrome: InMemoryWindowChrome(),
            communitiesPortFactory: () => port,
            shellChrome: InMemoryShellChrome(
              initial: InMemoryShellChrome.connectedProjection,
            ),
            preferences: InMemoryAppPreferences(
              initial: AppPreferences.defaults.copyWith(
                appearanceMode: mode,
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
          await tester.tap(
            find.byKey(const ValueKey('community-shortcut-$_target')),
          );
          await settleCommunityImages(tester);
          final expand = find.byKey(const Key('community-header-expand'));
          if (expand.evaluate().isNotEmpty) {
            await tester.tap(expand);
            await settleCommunityImages(tester);
          }
          expect(find.byType(StarBridgeShell), findsOneWidget);
          expect(find.byType(CommunityWorkspaceView), findsOneWidget);
          expect(composition.communities.selected?.key, _target);
          expect(find.textContaining('合成公告 · 运行状态对照'), findsWidgets);
          await enterCommunitySection(tester);
          final viewport = find.byKey(
            PageStorageKey((
              port as CommunityWorkspacePort,
              _target,
              'members',
            )),
          );
          expect(viewport, findsOneWidget);
          expect(
            tester
                .stateList<ScrollableState>(
                  find.descendant(
                    of: viewport,
                    matching: find.byType(Scrollable),
                  ),
                )
                .where((s) => s.position.axis == Axis.vertical),
            hasLength(1),
          );
          final covered = <String>{};
          for (final frame in ['top', 'middle', 'bottom']) {
            if (frame != 'top') {
              await tester.timedDrag(
                viewport,
                Offset(0, frame == 'middle' ? -220 : -1200),
                const Duration(milliseconds: 700),
              );
              await settleCommunityImages(tester);
            }
            for (final item in port.cases) {
              if (find
                  .byKey(ValueKey('member-row-${item.reference}'))
                  .evaluate()
                  .isEmpty) {
                continue;
              }
              final row = _memberMetadata(tester, item, viewport);
              if (row['fullyVisible'] != true) continue;
              covered.add(item.id);
              final texts = row['renderedText'] as List<String>;
              if (const ['offline', 'online', 'away'].contains(item.id)) {
                expect(texts.where((value) => value == '未进入游戏'), hasLength(3));
              }
              if (!_baseline &&
                  const [
                    'manual',
                    'invisible',
                    'paused',
                    'unknown',
                  ].contains(item.id)) {
                expect(texts.where((value) => value == '未进入游戏'), hasLength(3));
                expect(row['stateText'], ['离线']);
                expect(
                  texts.any(
                    (text) =>
                        text.contains('C2 Hercules') || text.contains('Orison'),
                  ),
                  isFalse,
                );
              }
              expect(
                (row['runtimeCells'] as Map),
                hasLength(3),
                reason:
                    '${item.id}: each actual runtime cell must match the production mapper',
              );
            }
            await _capture(tester, boundary, port, mode, frame, viewport);
            expect(tester.takeException(), isNull);
          }
          expect(
            covered,
            port.cases.map((item) => item.id).toSet(),
            reason: 'Normal native scroll frames must cover each complete card',
          );
          expect(port.reads, greaterThan(0));
          expect(port.mediaReads, greaterThan(0));
          expect(port.writes, 0);
          if (!_baseline && scenario.key == 'states') {
            // Holo shell (2026-10-23): the counts are the bar's stats.
            final stats = tester
                .widget<OfficialFleetHoloBar>(find.byType(OfficialFleetHoloBar))
                .deck
                .stats
                .map((stat) => stat.value);
            expect(stats, [8, 3, 1]);
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
  }
}
