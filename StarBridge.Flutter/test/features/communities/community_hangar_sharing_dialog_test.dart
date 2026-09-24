import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import '../friends/social_layout_test.dart' show loadFonts;

class _Port implements CommunityHangarSharingPort {
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool get hangarSharingAvailable => true;
  int reads = 0, writes = 0;
  List<String> selected = ['a' * 32];
  String result = 'accepted';
  String? readError;
  @override
  Future<CommunityHangarSharing> readHangarSharing() async {
    reads++;
    if (readError != null) throw CommunityFailure(readError!);
    return CommunityHangarSharing.parse({
      'schemaVersion': 1,
      'maximumTargets': 64,
      'editRef': 'c' * 32,
      'usesExplicitTargets': true,
      'options': [
        for (final id in ['a', 'b'])
          {
            'targetRef': id * 32,
            'name': 'Org $id',
            'selected': selected.contains(id * 32),
          },
      ],
    });
  }

  @override
  Future<CommunityHangarSharingOutcome> saveHangarSharing(
    String editRef,
    List<String> selectedRefs,
  ) async {
    writes++;
    selected = List.of(selectedRefs);
    return CommunityHangarSharingOutcome(result);
  }
}

Widget _host(_Port port, Locale locale) => MaterialApp(
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<bool>(
          context: context,
          builder: (_) => CommunityHangarSharingDialog(port: port),
        ),
        child: const Text('Open'),
      ),
    ),
  ),
);

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'missing server capability explains availability without retry loop',
    (tester) async {
      final port = _Port()..readError = 'upgradeRequired';
      addTearDown(port.changes.close);
      await tester.pumpWidget(_host(port, const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('机库共享暂未开放，请稍后再试。现有共享设置未改变。'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(port.writes, 0);
    },
  );
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    testWidgets('multi-select fits narrow window ${locale.toLanguageTag()}', (
      tester,
    ) async {
      tester.view.reset();
      tester.view.physicalSize = const Size(420, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = _Port();
      addTearDown(port.changes.close);
      await tester.pumpWidget(_host(port, locale));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(port.writes, 0);
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      await tester.ensureVisible(find.text('Org b'));
      await tester.tap(find.text('Org b'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(port.selected.toSet(), {'a' * 32, 'b' * 32});
      expect(port.writes, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'unknown write cannot repeat until refreshed; invalidation removes draft',
    (tester) async {
      final port = _Port()..result = 'unknown';
      addTearDown(port.changes.close);
      await tester.pumpWidget(_host(port, const Locale('en')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Org a'));
      await tester.pump();
      expect(find.text('Stop organization sharing'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(port.selected, isEmpty);
      expect(find.byType(FilledButton), findsNothing);
      expect(port.writes, 1);
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(port.reads, 2);
      port.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    },
  );
}
