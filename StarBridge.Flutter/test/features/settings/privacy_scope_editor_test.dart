import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/privacy_scope_editor.dart';

void main() {
  testWidgets('four compact switches keep their hit area and keyboard access', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = false;
    var writes = 0;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => PrivacyScopeEditor(
            scopeKey: 'compact',
            tone: PrivacyScopeTone.room,
            icon: StarBridgeIconSemantic.room,
            title: 'Room',
            description: 'Room members only',
            fieldsLabel: 'Shared information',
            fields: [
              for (final id in ['presence', 'ship', 'location', 'server'])
                PrivacyFieldChoice(
                  id: id,
                  icon: StarBridgeIconSemantic.activity,
                  label: id,
                  description: 'Details for $id',
                  selected: selected,
                  enabled: id != 'server',
                  onChanged: (value) => setState(() {
                    selected = value;
                    writes++;
                  }),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNWidgets(4));
    final tops = <double>[];
    for (final id in ['presence', 'ship', 'location', 'server']) {
      final rect = tester.getRect(
        find.byKey(Key('privacy-scope-compact-field-$id')),
      );
      expect(rect.height, inInclusiveRange(48, 52));
      tops.add(rect.top);
    }
    expect(tops.toSet().length, 1);
    expect(find.text('Details for ship'), findsNothing);
    final firstSwitch = find.byKey(
      const Key('privacy-scope-compact-switch-presence'),
    );
    await tester.tap(firstSwitch);
    await tester.pumpAndSettle();
    expect(selected, true);
    expect(writes, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(selected, false);
    expect(writes, 2);
    final disabled = tester.widget<Switch>(
      find.byKey(const Key('privacy-scope-compact-switch-server')),
    );
    expect(disabled.onChanged, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 620.0, 1100.0]) {
    testWidgets('switch labels wrap at width $width and double text size', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 1000),
              textScaler: const TextScaler.linear(2),
            ),
            child: PrivacyScopeEditor(
              scopeKey: 'large',
              tone: PrivacyScopeTone.organization,
              icon: StarBridgeIconSemantic.community,
              title: '组织 / Community',
              description: 'Shared information',
              fieldsLabel: '四项共享开关',
              fields: [
                for (final id in ['在线状态', '当前飞船', '当前位置', 'Server information'])
                  PrivacyFieldChoice(
                    id: id,
                    icon: StarBridgeIconSemantic.activity,
                    label: id,
                    description: id,
                    selected: true,
                    onChanged: (_) {},
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keeps every scope field visible and directly editable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(620, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var ship = false;

    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: const EdgeInsets.all(16),
            child: PrivacyScopeEditor(
              scopeKey: 'northwind',
              tone: PrivacyScopeTone.organization,
              icon: StarBridgeIconSemantic.community,
              title: 'Northwind 联合社区',
              description: '单独设置这个组织可以看到的信息。',
              badge: '社区组织',
              status: '待确认',
              statusPending: true,
              audience: PrivacyAudienceEditor(
                scopeKey: 'northwind',
                label: '共享给谁',
                choices: [
                  PrivacyAudienceChoice(
                    id: 'members',
                    label: '所有成员',
                    description: '这个组织的所有成员都可以查看。',
                    selected: false,
                    onChanged: (_) {},
                  ),
                  PrivacyAudienceChoice(
                    id: 'administrators',
                    label: '组织管理员',
                    description: '只允许组织管理员查看。',
                    selected: true,
                    onChanged: (_) {},
                  ),
                ],
              ),
              fieldsLabel: '共享哪些信息',
              fields: [
                PrivacyFieldChoice(
                  id: 'presence',
                  icon: StarBridgeIconSemantic.activity,
                  label: '在线状态',
                  description: '显示是否在线或正在游戏。',
                  selected: true,
                  onChanged: (_) {},
                ),
                PrivacyFieldChoice(
                  id: 'ship',
                  icon: StarBridgeIconSemantic.hangar,
                  label: '当前飞船',
                  description: '显示当前识别到的飞船。',
                  selected: ship,
                  onChanged: (value) => setState(() => ship = value),
                ),
                PrivacyFieldChoice(
                  id: 'location',
                  icon: StarBridgeIconSemantic.scene,
                  label: '当前位置',
                  description: '显示已确认的位置。',
                  selected: false,
                  onChanged: (_) {},
                ),
                PrivacyFieldChoice(
                  id: 'server',
                  icon: StarBridgeIconSemantic.statusNetwork,
                  label: '服务器信息',
                  description: '显示所在服务器关系。',
                  selected: false,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final field in const ['presence', 'ship', 'location', 'server']) {
      expect(
        find.byKey(Key('privacy-scope-northwind-field-$field')),
        findsOneWidget,
      );
    }
    expect(find.text('待确认'), findsOneWidget);
    expect(
      find.byKey(const Key('privacy-scope-northwind-audience-administrators')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('privacy-scope-northwind-field-ship')),
    );
    await tester.pumpAndSettle();

    expect(ship, isTrue);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
      .tokens;
  return MaterialApp(
    theme: buildStarBridgeTheme(tokens, const Locale('zh', 'CN')),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}
