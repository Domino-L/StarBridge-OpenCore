import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/menu_overlay_strings.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_text.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_room_member_menu.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_room_view.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_member_menu.dart';
import 'package:starbridge_flutter/features/communities/community_fleet_statistics_dialog.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_header.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_dock.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/platform/window/menu_interaction_presentation.dart';

import 'menu_organizations_test.dart' show fixture;
import 'menu_browser_tabs_test.dart' show BrowserFake;
import 'menu_chat_media_test.dart' show photo;
import 'menu_english_session_test_support.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts;

final cjk = RegExp(r'[\u3400-\u9fff\uf900-\ufaff\u3000-\u303f\uff00-\uffef]');
Object? englishFixture(Object? value) {
  if (value is String) return cjk.hasMatch(value) ? 'Fixture' : value;
  if (value is Map) {
    return <String, Object?>{
      for (final e in value.entries) e.key as String: englishFixture(e.value),
    };
  }
  if (value is List) return [for (final e in value) englishFixture(e)];
  return value;
}

Widget host(Widget child) => MaterialApp(
  locale: const Locale('en', 'US'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildMenuOverlayTheme(const Locale('en', 'US')),
  home: Scaffold(body: child),
);
void englishOnly(WidgetTester tester) {
  final values = <String>[];
  for (final w in tester.allWidgets) {
    if (w is Text) values.add(w.data ?? w.textSpan?.toPlainText() ?? '');
    if (w is RichText) values.add(w.text.toPlainText());
    if (w is Tooltip) {
      values.add(w.message ?? w.richMessage?.toPlainText() ?? '');
    }
    if (w is Semantics) {
      values.addAll([w.properties.label ?? '', w.properties.tooltip ?? '']);
    }
  }
  expect(values.where((v) => cjk.hasMatch(v)), isEmpty);
  expect(
    values.where(
      (v) => v.contains('menu.overlay.') || v.contains('Instance of'),
    ),
    isEmpty,
  );
  expect(tester.takeException(), isNull);
}

class Session extends MenuFeatureSession {
  Session(void Function(Map<String, Object?>) publish, Locale Function() locale)
    : super(publish, const Stream.empty(), locale: locale);
  @override
  void reset() {}
  @override
  Future<void> closePort() async {}
  @override
  Future<Map<String, Object?>> read() async => {
    'state': 'ready',
    'title': const MenuOverlayText('menu.overlay.organizations.members'),
  };
}

void main() {
  setUpAll(loadFonts);
  test('three language key sets match and English contains no CJK', () {
    expect(menuOverlayEn.keys.toSet(), menuOverlayZhCn.keys.toSet());
    expect(menuOverlayEn.keys.toSet(), menuOverlayZhTw.keys.toSet());
    expect(menuOverlayEn.values.where(cjk.hasMatch), isEmpty);
    expect(menuOverlayEn.length, 335);
    // Every phrase exists in all three languages; none falls back to its key.
    for (final table in [menuOverlayZhCn, menuOverlayZhTw, menuOverlayEn]) {
      for (final entry in table.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
        expect(entry.value, isNot(contains('menu.overlay.')), reason: entry.key);
      }
    }
    for (final (key, zhCn, zhTw, en) in const [
      ('menu.overlay.window.recover', '移回当前屏幕', '移回目前螢幕', 'Move to this screen'),
      ('menu.overlay.rooms.leave', '退出房间', '離開房間', 'Leave room'),
    ]) {
      expect(
        (menuOverlayZhCn[key], menuOverlayZhTw[key], menuOverlayEn[key]),
        (zhCn, zhTw, en),
      );
    }
  });
  test('legacy and supported language envelopes round trip strictly', () {
    expect(
      MenuInteractionPresentation.parse(
        jsonEncode({
          'schemaVersion': 1,
          'style': 'standard',
          'reduceMotion': false,
        }),
      ),
      isNotNull,
    );
    for (final language in ['zh-CN', 'zh-TW', 'en-US', 'en']) {
      expect(
        MenuInteractionPresentation.parse(
          MenuInteractionPresentation(language: language).encode(),
        )!.language,
        language,
      );
    }
    for (final language in [null, 3, '', 'fr', 'EN']) {
      expect(
        MenuInteractionPresentation.parse(
          jsonEncode({
            'schemaVersion': 1,
            'style': 'standard',
            'reduceMotion': false,
            'language': language,
          }),
        ),
        isNull,
      );
    }
  });
  testWidgets('cached templates resolve on next emit without another read', (
    tester,
  ) async {
    var locale = const Locale('zh', 'CN');
    final views = <Map<String, Object?>>[];
    final session = Session(views.add, () => locale)..visible = true;
    final cached = await session.read();
    session.emit(cached);
    expect(views.last['title'], '成员');
    locale = const Locale('en');
    session.emit(session.currentView);
    expect(views.last['title'], 'Members');
    session.dispose();
    await verifyEnglishSessions(tester);
  });
  test('explicit templates preserve user strings and substitute once', () {
    final strings = AppStrings.resolve(const Locale('en'));
    final result = resolveMenuOverlayValue({
      'user': '发送消息 {count}',
      'copy': const MenuOverlayText('menu.overlay.friends.requestCount', {
        'count': '{name}',
      }),
    }, strings) as Map;
    expect(result['user'], '发送消息 {count}');
    expect(result['copy'], 'Friend requests · {name}');
  });
  for (final width in [1280.0, 640.0]) {
    for (final scenario in [
      'friends',
      'comms',
      'organizations',
      'rooms',
      'browser',
      'images',
      'header',
      'dock',
    ]) {
      testWidgets('English $scenario at $width', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.reset);
        Future<void> show(Widget child) async {
          await tester.pumpWidget(host(child));
          await tester.pumpAndSettle();
          englishOnly(tester);
        }

        switch (scenario) {
          case 'friends':
            await show(
              MenuFriendsPanel(
                view: const MenuFriendsView(
                  'ready',
                  interactive: true,
                  confirmation: (token: 'confirm1', name: 'Pilot', action: 'remove'),
                  rows: [
                    (
                      name: 'Pilot',
                      presence: 'online',
                      key: 'f1',
                      avatar: null,
                    ),
                  ],
                ),
                onClose: () {},
                onAction: (_, _, _) {},
              ),
            );
          case 'comms':
            for (final selected in [false, true]) {
              await show(
                MenuCommsPanel(
                  view: MenuCommsView(
                    'ready',
                    name: selected ? 'Pilot' : null,
                    rows: [
                      (
                        key: 'c1',
                        name: 'Pilot',
                        time: DateTime(2026),
                        unread: 1,
                        request: true,
                      ),
                    ],
                    compose: selected,
                    canSend: selected,
                  ),
                  onClose: () {},
                  onAction: (_, _) {},
                ),
              );
            }
          case 'organizations':
            for (final tab in ['directory', 'members', 'ships']) {
              final value =
                  englishFixture(fixture(tab: tab)) as Map<String, Object?>;
              await show(
                MenuOrganizationsPanel(
                  view: MenuFeatureView.parse(value),
                  onAction: (_, _) {},
                ),
              );
              if (tab == 'ships') {
                (value['buttons'] as List).addAll([
                  {
                    'key': 'a7',
                    'label': 'Fleet statistics',
                    'role': 'fleetStatistics',
                    'limit': 128,
                  },
                  {
                    'key': 'a8',
                    'label': 'Close statistics',
                    'role': 'closeStatistics',
                    'limit': 128,
                  },
                ]);
                (value['organization'] as Map)['fleetStatistics'] = {
                  'shipCount': 0,
                  'modelCount': 0,
                  'sharingMemberCount': 0,
                  'pricedCount': 0,
                  'totalCents': 0,
                  'sizes': {},
                  'roles': {},
                  'matrix': {},
                };
                await show(
                  MenuOrganizationsPanel(
                    view: MenuFeatureView.parse(value),
                    onAction: (_, _) {},
                  ),
                );
                expect(
                  find.byType(CommunityFleetStatisticsDialog),
                  findsOneWidget,
                );
                await tester.tap(find.text('Close').last);
                await tester.pumpAndSettle();
                englishOnly(tester);
              }
            }
          case 'rooms':
            await show(
              MenuRoomsPanel(
                view: const MenuFeatureView('ready'),
                onAction: (_, _) {},
              ),
            );
            await show(
              MenuRoomsPanel(
                view: const MenuFeatureView(
                  'ready',
                  title: 'Room',
                  room: MenuRoomView(
                    'members',
                    'ABC',
                    'Explore',
                    8,
                    1,
                    [
                      RoomMember(
                        callsign: 'Pilot',
                        gameId: 'Pilot',
                        isHost: false,
                        presence: '',
                        location: '',
                        ship: '',
                        shard: '',
                      ),
                    ],
                    false,
                    false,
                  ),
                ),
                onAction: (_, _) {},
              ),
            );
            await show(
              MenuRoomMemberMenu(
                enabled: true,
                action: (
                  key: 'a1',
                  label: 'Remove member',
                  role: 'removeMember',
                  secret: false,
                  confirm: 'Remove Pilot?',
                  input: null,
                  limit: 128,
                ),
                transferAction: (
                  key: 'a2',
                  label: 'Transfer host',
                  role: 'transferOwner',
                  secret: false,
                  confirm: 'Transfer to Pilot?',
                  input: null,
                  limit: 128,
                ),
                dispatch: (_, _) {},
              ),
            );
            await tester.tap(find.byType(RoomMemberMenu));
            await tester.pumpAndSettle();
            englishOnly(tester);
            expect(find.text('Transfer host'), findsOneWidget);
          case 'browser':
            final fake = BrowserFake();
            for (final tab in fake.tabs) {
              tab['title'] = 'Example';
            }
            final workspace = MenuWorkspaceController(
              scope: Object(),
              panels: [],
            );
            await show(MenuBrowserTool(call: fake.call, workspace: workspace));
            await tester.pumpWidget(const SizedBox());
            workspace.dispose();
          case 'images':
            final tools = MenuLocalToolsController(
              (_, _) async => null,
              locale: () => const Locale('en'),
            );
            await show(MenuImageTool(tools: tools));
            tools.reference = Uint8List.fromList(
              base64Decode(photo.split(',').last),
            );
            tools.notifyListeners();
            await tester.pumpAndSettle();
            englishOnly(tester);
            await tester.pumpWidget(const SizedBox());
            tools.dispose();
          case 'header':
            await show(
              MenuBridgeHeader(
                onDismiss: () {},
                onSettings: () {},
                onHud: () {},
                onToggleWindows: () {},
              ),
            );
          case 'dock':
            await show(
              BridgePreviewDock(
                selected: null,
                onToggle: (_) {},
                featuresEnabled: true,
                localToolsEnabled: true,
              ),
            );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }
}
