import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_creation_controller.dart';
import 'package:starbridge_flutter/features/communities/community_filter_panel.dart';
import 'package:starbridge_flutter/features/communities/community_tag_picker.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/communities/legacy_community_tag_catalog.dart';

void main() {
  test('Every catalog field and its order match the WPF Core source', () {
    final source = File('../StarBridge.Core/Fleets/LegacyFleetTagCatalog.cs')
        .readAsStringSync();
    final rows =
        RegExp(
              r'new\(("(?:[^"\\]|\\.)*"), ("(?:[^"\\]|\\.)*"), ("(?:[^"\\]|\\.)*"), ("(?:[^"\\]|\\.)*")\)',
            )
            .allMatches(source)
            .map((m) => [for (var i = 1; i <= 4; i++) jsonDecode(m.group(i)!)])
            .toList();
    expect(rows.length, 90);
    expect(
      LegacyCommunityTagCatalog.categories
          .map((c) => [c.id, c.name, c.accentHex, c.description])
          .toList(),
      rows.take(9).toList(),
    );
    expect(
      LegacyCommunityTagCatalog.tags
          .map((t) => [t.id, t.name, t.categoryId, t.description])
          .toList(),
      rows.skip(9).toList(),
    );
    expect(LegacyCommunityTagCatalog.options.maxTags, 5);
  });

  test(
    'Example creation uses complete options and preserves other memberships',
    () async {
      final port = ExampleCommunities();
      final model = CommunityCreationController(port, port.invalidations);
      await model.load();
      expect(model.options!.tags.length, 81);
      model.update('name', 'Preview Organization');
      model.update('code', 'preview');
      model.update('tagIds', ['core_exploration', 'exploration_scouting']);
      await model.submit();
      expect(model.outcome!.status, 'accepted');
      final mine = await port.read(view: 'mine', query: '');
      expect(mine.items.map((c) => c.relationship), [
        'member',
        'owner',
        'owner',
      ]);
      expect(mine.items.last.tags, '探索 · 侦察');
      final filtered = await port.read(
        view: 'discover',
        query: '',
        filters: jsonEncode({
          'tags': ['探索', '侦察'],
          'allTags': true,
        }),
      );
      expect(filtered.items.single.name, 'Preview Organization');
      final duplicate = await port.createCommunity(
        'another-intent',
        model.draft!,
      );
      expect(duplicate.error, 'codeUnavailable');
      model.dispose();
      await port.close();
      expect((await port.read(view: 'mine', query: '')).items.length, 2);
    },
  );

  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      'Discovery picker edits privately and applies names ${locale.toLanguageTag()}',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final applied = <String>[];
        final changes = StreamController<void>.broadcast(sync: true);
        addTearDown(changes.close);
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStringsDelegate(),
              ...GlobalMaterialLocalizations.delegates,
            ],
            theme: buildStarBridgeTheme(
              FutureRestraintStyle.resolve(AppearanceMode.dark),
              locale,
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 800,
                  child: CommunityFilterPanel(
                    invalidations: changes.stream,
                    value: '{"tags":["探索"]}',
                    onApply: applied.add,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final edit = find.byKey(const ValueKey('choose-filter-tags'));
        await tester.scrollUntilVisible(
          edit,
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(edit);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('selected-core_exploration')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('tag-core_combat')));
        await tester.tap(
          find
              .descendant(
                of: find.byType(CommunityTagPicker),
                matching: find.byType(TextButton),
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(applied, isEmpty);
        expect(find.byKey(const ValueKey('filter-tag-战斗')), findsNothing);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('tag-core_combat')));
        await tester.tap(
          find.descendant(
            of: find.byType(CommunityTagPicker),
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pumpAndSettle();
        expect(applied, isEmpty);
        expect(find.byKey(const ValueKey('filter-tag-战斗')), findsOneWidget);
        await tester.tap(find.byType(FilledButton));
        expect(jsonDecode(applied.single)['tags'], ['战斗', '探索']);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        changes.add(null);
        await tester.pumpAndSettle();
        expect(find.byType(CommunityTagPicker), findsNothing);
        await tester.tap(find.byType(FilledButton));
        expect(applied.length, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
