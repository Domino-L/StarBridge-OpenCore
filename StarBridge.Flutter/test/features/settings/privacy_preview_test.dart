// Offline screenshots of the actual settings workspaces. No Host, account,
// transport, persistence, or product feature flags are involved.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_communication.dart';
import 'package:starbridge_flutter/features/communities/community_settings_workspace.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_audience_picker.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_manage_workspace.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rally.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_sources.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_port.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/notification_organization_options.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/official_runtime_privacy_port.dart';
import 'package:starbridge_flutter/features/settings/organization_personal_settings.dart';
import 'package:starbridge_flutter/features/settings/organization_privacy_pane.dart';
import 'package:starbridge_flutter/features/settings/player_activity_controller.dart';
import 'package:starbridge_flutter/features/settings/player_activity_dialog.dart';
import 'package:starbridge_flutter/features/settings/privacy_scope_editor.dart';

import '../friends/social_layout_test.dart' show app, loadFonts, size;

const _joinedAt = '2026-01-01T00:00:00Z';
const _officialSource = 'officialFleet:7';
const _communitySource = 'organization:preview';
final _output = _previewOutput();

Directory _previewOutput() {
  final configured = Platform.environment['STARBRIDGE_TEST_VISUAL_DIR'];
  if (configured != null && configured.trim().isNotEmpty) {
    return Directory('$configured/privacy-preview');
  }
  return Directory.systemTemp.createTempSync('starbridge-privacy-preview-');
}

final _captions = <String>[];

// Read-only fixtures: an unexpected save fails instead of manufacturing a
// successful receipt. Every identifier and membership here is synthetic.
class _Privacy
    implements
        LocalPrivacyPort,
        CommunitySharingPort,
        OfficialRuntimePrivacyPort {
  _Privacy(this.code, this.name);
  final String code, name;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get communitySharingSupported => true;
  @override
  bool get officialRuntimePrivacySupported => true;
  @override
  Stream<void> get officialRuntimePrivacyInvalidations => const Stream.empty();
  @override
  Future<LocalPrivacySnapshot> read() async => LocalPrivacySnapshot(
    revision: 1,
    savedAt: DateTime.utc(2026, 1, 1),
    settings: LocalPrivacySettings.editorDefaults.copyWith(
      communities: [
        CommunitySharingScope(
          code: code,
          joinedAt: _joinedAt,
          fields: 15,
          administratorsCanView: false,
          allMembersCanView: true,
        ),
      ],
    ),
  );
  @override
  Future<CommunitySharingTargets> readCommunityTargets() async =>
      CommunitySharingTargets(
        communities: [
          CommunitySharingTarget(code: code, name: name, joinedAt: _joinedAt),
        ],
      );
  @override
  Future<OfficialRuntimePrivacySnapshot> readOfficialRuntimePrivacy() async =>
      const OfficialRuntimePrivacySnapshot(
        state: 'available',
        revision: 1,
        fields: 15,
        savedFields: 15,
        savedForCurrentSource: true,
        canSave: true,
        canCancel: true,
        sourceRef: _officialSource,
        scopeRef: '11111111111111111111111111111111',
        contextRef: '22222222222222222222222222222222',
        cancelContextRef: '33333333333333333333333333333333',
        maximumRankValue: 2,
        audienceRankSupported: true,
      );
  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings settings) async =>
      throw StateError('Preview must not save');
  @override
  Future<OfficialRuntimePrivacySaveReceipt> saveOfficialRuntimePrivacy({
    required OfficialRuntimePrivacySnapshot scope,
    required int expectedRevision,
    required int fields,
    required bool cancelSavedScope,
    OfficialFleetAudience? audience,
  }) async => throw StateError('Preview must not save');
  @override
  Future<void> close() async {}
}

class _Notifications implements OrganizationNotificationSourcesPort {
  _Notifications(this.code, this.name);
  final String code, name;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<NotificationSourcesValue> read() async => NotificationSourcesValue(1, [
    const NotificationSourceRule(
      sourceRef: _officialSource,
      kind: NotificationSourceKind.officialFleet,
      displayName: '示例主舰队',
      contextLabel: '主舰队',
      mode: NotificationSourceMode.normal,
      organizationOptions: NotificationOrganizationOptions(quietEnabled: true),
    ),
    NotificationSourceRule(
      sourceRef: _communitySource,
      kind: NotificationSourceKind.community,
      displayName: name,
      contextLabel: '社区组织',
      organizationCode: code,
      mode: NotificationSourceMode.normal,
      organizationOptions: const NotificationOrganizationOptions(
        quietEnabled: true,
      ),
    ),
  ], supportsOrganizationOptions: true);
  @override
  Future<NotificationSourcesValue> save(
    NotificationSourcesValue original,
    Map<String, NotificationSourceMode> modes,
  ) async => throw StateError('Preview must not save');
  @override
  Future<NotificationSourcesValue> saveOrganizationOptions(
    NotificationSourcesValue original,
    Map<String, NotificationSourceMode> modes,
    Map<String, NotificationOrganizationOptions> options,
  ) async => throw StateError('Preview must not save');
  @override
  void dispose() {}
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
  String caption,
) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      expect(image.width, 1440);
      expect(image.height, 900);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await _output.create(recursive: true);
      await File('${_output.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
    _captions.add('- [$name.png]($name.png)：$caption');
    await File('${_output.path}/README.md').writeAsString(
      '# 隐私与通知页面预览\n\n'
      '当前工作区真实 Flutter 页面和组件，简体中文、深色主题、1440×900、项目字体。'
      '全部为内存示例数据；主舰队示例选择四星及以上可见，免打扰示例为每日 22:00–08:00。'
      '未连接 Host、账号或服务，未保存设置。截图仅说明当前实现，不代表线上或主树验收。\n\n'
      '${_captions.join('\n')}\n\n'
      '隐私内容超过一屏时按实际滚动位置连续截图，所有字段保持展开。'
      '聊天下拉图展示真实菜单，常态图展示未被菜单遮挡的说明与时段。\n\n'
      '运行（StarBridge.Flutter 目录；先检查测试占用并精简当前进程 PATH）：\n\n'
      '```powershell\n'
      "\$env:STARBRIDGE_TEST_VISUAL_DIR='<截图输出目录>'\n"
      "\$env:FLUTTER_ROOT='<Flutter SDK 目录>'\n"
      "& (Join-Path \$env:FLUTTER_ROOT 'bin/cache/dart-sdk/bin/dart.exe') "
      "(Join-Path \$env:FLUTTER_ROOT 'bin/cache/flutter_tools.snapshot') "
      'test --no-pub test/features/settings/privacy_preview_test.dart\n'
      '```\n',
    );
  });
}

// Preserve the window size and real scroll layout; do not shrink or stitch UI.
Future<void> _capturePrivacy(
  WidgetTester tester,
  GlobalKey key,
  String prefix,
  String caption,
) async {
  final pane = find.byType(OrganizationPrivacyPane);
  expect(find.byKey(const Key('organization-personal-result')), findsOneWidget);
  expect(find.byType(PrivacyScopeEditor), findsOneWidget);
  expect(
    tester.widget<PrivacyScopeEditor>(find.byType(PrivacyScopeEditor)).fields,
    hasLength(4),
  );
  final scroll = find
      .ancestor(of: pane, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scroll).position;
  position.jumpTo(0);
  await _capture(tester, key, '$prefix-01', caption);
  var index = 2;
  while (position.pixels < position.maxScrollExtent) {
    final next = (position.pixels + position.viewportDimension * .75).clamp(
      0.0,
      position.maxScrollExtent,
    );
    position.jumpTo(next);
    await _capture(
      tester,
      key,
      '$prefix-${index.toString().padLeft(2, '0')}',
      '$caption（向下滚动，续图；字段未折叠。）',
    );
    index++;
  }
}

Future<void> _captureNotifications(
  WidgetTester tester,
  GlobalKey key,
  bool official,
) async {
  final source = official ? _officialSource : _communitySource;
  final prefix = official
      ? '02-main-fleet-notifications'
      : '04-community-notifications';
  expect(
    find.byKey(ValueKey('organization-announcement-$source')),
    findsOneWidget,
  );
  expect(find.textContaining('按组织汇总为一条提醒'), findsOneWidget);
  expect(find.textContaining('首次使用不汇总'), findsOneWidget);
  expect(find.textContaining('跳过的提醒不补发'), findsOneWidget);
  expect(find.textContaining('当前没有独立活动提醒'), findsOneWidget);
  expect(find.text('每天定时免打扰'), findsOneWidget);
  expect(
    find.textContaining('Ctrl+Alt+Y'),
    official ? findsOneWidget : findsNothing,
  );
  await _capture(
    tester,
    key,
    prefix,
    '新增聊天设置、公告选择及启动／恢复汇总说明、当前活动提醒说明、每日免打扰时段；'
    '${official ? '保留主舰队召集提醒独立说明。' : '社区组织没有召集及其提醒说明。'}',
  );
  await tester.tap(find.byKey(ValueKey('organization-chat-$source')));
  await tester.pumpAndSettle();
  expect(find.text('提醒'), findsWidgets);
  expect(find.text('不提醒'), findsWidgets);
  expect(find.text('跟随上方提醒模式'), findsWidgets);
  await _capture(
    tester,
    key,
    '$prefix-chat-options',
    '新增聊天下拉选项：跟随上方提醒模式、提醒、不提醒。',
  );
}

void main() {
  setUpAll(loadFonts);
  testWidgets('preview main fleet privacy and notifications', (tester) async {
    size(tester, const Size(1440, 900));
    final privacy = LocalPrivacyController(_Privacy('PREVIEW', '示例社区'));
    final communication = OrganizationCommunication(null);
    final rally = OfficialFleetRallyController(
      const UnavailableOfficialFleetRallyPort(),
    );
    addTearDown(privacy.dispose);
    addTearDown(communication.dispose);
    addTearDown(rally.dispose);
    const fleet = OfficialFleetSummary(
      sourceRef: _officialSource,
      sid: 'PREVIEW',
      name: '示例主舰队',
      officialRankName: '示例成员',
      officialRankValue: 3,
    );
    final projection = OfficialFleetProjection.fromSnapshot(
      OfficialFleetSnapshot.available(
        fleet: fleet,
        freshness: OfficialFleetFreshness.live,
        resourceVersion: 1,
        observedAtUtc: DateTime.utc(2026, 1, 1),
      ),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: app(
          OrganizationPersonalSettings(
            privacy: privacy,
            notificationSources: () => _Notifications('PREVIEW', '示例社区'),
            child: OfficialFleetManageWorkspace(
              fleet: fleet,
              projection: projection,
              communication: communication,
              rally: rally,
              onBack: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('official-fleet-settings-nav-privacy')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OfficialFleetAudiencePicker), findsOneWidget);
    await _capturePrivacy(
      tester,
      key,
      '01-main-fleet-privacy',
      '新增“我自己”的结果说明；真实主舰队隐私分区完整展开，包含四项实时共享及星级可见门槛。',
    );
    await tester.tap(
      find.byKey(const ValueKey('official-fleet-settings-nav-notifications')),
    );
    await tester.pumpAndSettle();
    await _captureNotifications(tester, key, true);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('preview community privacy and notifications', (tester) async {
    size(tester, const Size(1440, 900));
    final port = ExampleCommunities();
    addTearDown(port.close);
    const target = '00000000000000000000000000000002';
    final workspace = await port.readWorkspace(target, '', 0);
    final privacy = LocalPrivacyController(
      _Privacy(workspace.code, workspace.name),
    );
    addTearDown(privacy.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: app(
          OrganizationPersonalSettings(
            privacy: privacy,
            notificationSources: () =>
                _Notifications(workspace.code, workspace.name),
            child: CommunitySettingsWorkspace(
              port: port,
              workspace: workspace,
              targetRef: target,
              onMembers: () {},
              hasDangerActions: false,
              dangerActions: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-privacy')));
    await tester.pumpAndSettle();
    expect(find.byType(OfficialFleetAudiencePicker), findsNothing);
    expect(find.byKey(const ValueKey('settings-nav-rally')), findsNothing);
    await _capturePrivacy(
      tester,
      key,
      '03-community-privacy',
      '新增“我自己”的结果说明；社区隐私字段完整展开，沿用社区可见范围，没有主舰队星级门槛或召集。',
    );
    await tester.tap(find.byKey(const ValueKey('settings-nav-notifications')));
    await tester.pumpAndSettle();
    await _captureNotifications(tester, key, false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('preview corrected player activity source name', (tester) async {
    size(tester, const Size(1440, 900));
    final controller = PlayerActivityController((name, payload) async {
      expect(name, 'playerActivity.read');
      return {
        'schemaVersion': 1,
        'enabled': true,
        'scope': 7,
        'position': 0,
        'online': true,
        'offline': false,
        'startedGame': true,
        'stoppedGame': true,
        'backgroundOnly': true,
        'reduceInGame': true,
        'revision': 'missing',
        'writable': true,
      };
    }, generation: () => 1);
    addTearDown(controller.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: app(
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 1100,
              child: PlayerActivityConnectedPanel(
                controller: controller,
                showClose: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('社区组织成员'), findsOneWidget);
    expect(find.textContaining('RSI'), findsNothing);
    expect(find.text('RSI 官网舰队成员'), findsNothing);
    expect(find.textContaining('主舰队动态尚未接入'), findsOneWidget);
    await _capture(
      tester,
      key,
      '05-player-activity-source',
      '第 8 项将玩家动态来源修正为“社区组织成员”，保留好友和当前房间来源，并如实说明主舰队动态尚未接入。',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
