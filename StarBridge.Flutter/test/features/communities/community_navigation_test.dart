import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_pane.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_item.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/communities_feature.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/communities_page.dart';
import 'package:starbridge_flutter/features/communities/community_shortcuts.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';

import '../friends/social_layout_test.dart' show loadFonts;
import 'community_workspace_view_test.dart' show host;

Widget shell(CommunitiesModule module) {
  final feature = createCommunitiesFeature(module: module);
  final registry = FeatureRegistry([
    FeatureDescriptor(
      id: 'home',
      route: '/',
      labelKey: 'navigation.home',
      descriptionKey: 'navigation.home',
      icon: StarBridgeIconSemantic.community,
      navigationRegion: NavigationRegion.brand,
      order: 0,
      buildDestination: (_) => const SizedBox(),
    ),
    feature,
  ]);
  return MaterialApp(
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
    home: Scaffold(
      body: Row(
        children: [
          StarBridgeNavigationPane(
            registry: registry,
            mode: ShellLayoutMode.wide,
            selected: feature,
            onSelect: (_, _) {},
            onActivate: (_) async => true,
          ),
          Expanded(
            child: CommunitiesPage(
              createPort: () => module.port,
              module: module,
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'primary destination discovers; joined shortcuts own internal pages',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final module = CommunitiesModule(ExampleCommunities());
      addTearDown(module.dispose);
      await tester.pumpWidget(shell(module));
      await tester.pumpAndSettle();
      expect(module.view, 'discover');
      expect(find.text('我的组织'), findsNothing);
      expect(
        find.byKey(const Key('community-internal-workspace')),
        findsNothing,
      );
      final shortcut = find.descendant(
        of: find.byType(CommunityShortcuts),
        matching: find.text(module.joined.last.name),
      );
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(module.selected?.key, module.joined.last.key);
      expect(
        find.byKey(const Key('community-internal-workspace')),
        findsOneWidget,
      );
      expect(find.text('寻找组织'), findsNothing);
      final primary = find.byKey(const ValueKey('/communities'));
      expect(tester.widget<ShellNavigationItem>(primary).selected, isFalse);
      await tester.tap(find.byKey(const ValueKey('community-section-manage')));
      await tester.pumpAndSettle();
      expect(find.text('数据与日志'), findsOneWidget);
      expect(find.byKey(const ValueKey('disband-community')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('settings-nav-danger')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('disband-community')), findsOneWidget);
      await tester.tap(primary);
      await tester.pumpAndSettle();
      expect(module.selected, isNull);
      expect(module.view, 'discover');
      expect(find.text('寻找组织'), findsOneWidget);
      expect(tester.widget<ShellNavigationItem>(primary).selected, isTrue);
      expect(module.joined.length, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'internal tabs protect chat draft and keep organization context',
    (tester) async {
      final port = ExampleCommunities();
      addTearDown(port.close);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          port,
          const Locale('zh', 'CN'),
          target: '00000000000000000000000000000002',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('community-section-chat')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('community-chat-input')),
        '保留草稿',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('community-section-members')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CommunityChatPanel), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '继续编辑'));
      await tester.pumpAndSettle();
      expect(find.text('保留草稿'), findsOneWidget);
      final chat = tester.state<CommunityChatPanelState>(find.byType(CommunityChatPanel));
      await tester.tap(find.byKey(const ValueKey('community-section-members')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '丢弃草稿并返回'));
      await tester.pumpAndSettle();
      expect(chat.model.draft, isEmpty);
      await tester.tap(find.byKey(const ValueKey('community-section-chat')));
      await tester.pumpAndSettle();
      expect(find.text('保留草稿'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('cancelled root or organization navigation leaves current membership untouched', () async {
    final model = CommunitiesModule(ExampleCommunities());
    addTearDown(model.dispose);
    await model.refreshJoined();
    model.open(model.joined.first);
    model.confirmWorkspaceLeave = () async => false;
    await model.openDiscovery();
    await model.openJoined(model.joined.last);
    expect(model.selected?.key, model.joined.first.key);
    expect(model.primaryNavigationSelected.value, isFalse);
    expect(model.joined.length, 2);
  });
}
