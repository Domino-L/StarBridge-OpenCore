import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/routing/coming_soon_destination.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_item.dart';
import 'package:starbridge_flutter/design_system/components/coming_soon.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/operations/operations_feature.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_feature.dart';
import 'package:starbridge_flutter/features/tools/tools_feature.dart';
import 'package:starbridge_flutter/features/notifications/notifications_feature.dart';
import 'package:starbridge_flutter/features/settings/settings_capability_catalog.dart';
import 'package:starbridge_flutter/features/settings/settings_entry_dialog.dart';

import '../features/friends/social_layout_test.dart'
    show app, size, capture, loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final feature in [
    operationsFeature,
    marketplaceFeature,
    toolsFeature,
    notificationsFeature,
  ]) {
    testWidgets('${feature.id} renders coming soon instead of blank content', (
      tester,
    ) async {
      await tester.pumpWidget(app(Builder(builder: feature.buildDestination)));
      await tester.pumpAndSettle();
      expect(feature.availability, FeatureAvailability.comingSoon);
      expect(find.byType(ComingSoonDestination), findsOneWidget);
      expect(find.text('即将推出'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is ButtonStyleButton), findsNothing);
    });
  }
  testWidgets('working notifications keep their real content', (tester) async {
    final feature = createNotificationsFeature(
      buildContent: (_) => const Text('真实通知'),
    );
    await tester.pumpWidget(app(Builder(builder: feature.buildDestination)));
    await tester.pumpAndSettle();
    expect(feature.availability, FeatureAvailability.available);
    expect(find.text('真实通知'), findsOneWidget);
    expect(find.byType(ComingSoonDestination), findsNothing);
  });
  for (final mode in AppearanceMode.values) {
    if (mode != AppearanceMode.dark && mode != AppearanceMode.light) continue;
    testWidgets('coming soon ${mode.name} presentation', (tester) async {
      size(tester, const Size(800, 500));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: boundary,
            child: Builder(builder: operationsFeature.buildDestination),
          ),
          mode,
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, boundary, 'coming-soon-${mode.name}');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('availability drives both navigation badge and destination', (
    tester,
  ) async {
    for (final availability in FeatureAvailability.values) {
      final feature = FeatureDescriptor(
        id: 'tools',
        route: '/tools',
        labelKey: 'navigation.tools',
        descriptionKey: 'navigation.tools.description',
        icon: StarBridgeIconSemantic.tools,
        navigationRegion: NavigationRegion.personal,
        order: 0,
        availability: availability,
        buildDestination: (_) => const Text('可用工具'),
      );
      await tester.pumpWidget(
        app(
          Center(
            child: SizedBox(
              width: 220,
              child: ShellNavigationItem(
                descriptor: feature,
                mode: ShellLayoutMode.wide,
                selected: false,
                onPressed: () {},
                onKeyboardPressed: () {},
                onPrevious: () {},
                onNext: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(ComingSoonBadge),
        availability == FeatureAvailability.comingSoon
            ? findsOneWidget
            : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'settings placeholder has no fake disabled controls and live override still opens',
    (tester) async {
      final capability = SettingsCapabilityCatalog.planned.first;
      await tester.pumpWidget(
        app(SettingsCapabilityEntryDialog(capability: capability)),
      );
      await tester.pumpAndSettle();
      final section = find.byType(ComingSoonSection);
      expect(section, findsOneWidget);
      for (final type in [
        IconButton,
        Switch,
        Checkbox,
        TextField,
      ]) {
        expect(
          find.descendant(of: section, matching: find.byType(type)),
          findsNothing,
        );
      }
      expect(find.descendant(of: section,
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)), findsNothing);
      var opened = false;
      await tester.pumpWidget(
        app(
          SettingsEntryOverrides(
            openers: {
              capability.id: (_) async {
                opened = true;
              },
            },
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showSettingsCapabilityEntry(context, capability),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开'));
      expect(opened, isTrue);
      expect(find.byType(ComingSoonSection), findsNothing);
    },
  );
  test('coming soon wording is complete in all three locales', () {
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings.resolve(locale);
      for (final key in [
        'deferredFeature.title',
        'comingSoon.body',
        'comingSoon.section',
        'navigation.operations.description',
        'navigation.marketplace.description',
        'navigation.tools.description',
      ]) {
        final value = strings.text(key);
        expect(value, isNot(key));
        expect(
          RegExp('Flutter|首发|首發|initial release|尚未|暫未|暂未').hasMatch(value),
          isFalse,
        );
      }
    }
  });
}
