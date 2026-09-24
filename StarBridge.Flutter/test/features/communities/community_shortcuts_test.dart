import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_pane.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/communities_feature.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_shortcuts.dart';
import 'package:starbridge_flutter/features/communities/community_logo.dart';

import '../friends/social_layout_test.dart' show loadFonts;

class QueuedPort implements CommunitiesPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final reads = <Completer<CommunityDirectory>>[];
  final writes = <String>[];
  bool queued = false;
  List<CommunityCard> rows = List.generate(
    40,
    (i) => CommunityCard(
      targetRef: '$i',
      organizationRef: '$i',
      name: '组织 $i',
      relationship: 'member',
      actions: const ['leave'],
    ),
  );
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) {
    if (!queued) return Future.value(CommunityDirectory(view, query, rows));
    final request = Completer<CommunityDirectory>();
    reads.add(request);
    return request.future;
  }

  @override
  Future<String> execute(String action, String targetRef) async {
    writes.add(action);
    rows = rows.where((row) => row.targetRef != targetRef).toList();
    return 'accepted';
  }

  @override
  Future<void> close() => changes.close();
}

void main() {
  setUpAll(loadFonts);
  test('Old joined reads cannot restore memberships after a write or account change', () async {
    final port = QueuedPort()..queued = true;
    final model = CommunitiesModule(port);
    final old = model.refreshJoined();
    final oldRows = List<CommunityCard>.of(port.rows);
    port.queued = false;
    await model.execute(oldRows.first, 'leave');
    port.reads.single.complete(CommunityDirectory('mine', '', oldRows));
    await old;
    expect(model.joined.any((row) => row.targetRef == '0'), isFalse);
    port.queued = true;
    final late = model.refreshJoined();
    port.changes.add(null);
    port.reads.last.complete(CommunityDirectory('mine', '', oldRows));
    await late;
    expect(model.joined, isEmpty);
    expect(model.joinedLoaded, isFalse);
    model.dispose();
  });

  for (final mode in [ShellLayoutMode.wide, ShellLayoutMode.iconOnly]) {
    testWidgets(
      'Organization shortcuts fit $mode, respect navigation guard and virtualize',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = QueuedPort();
        final shared = CommunitiesModule(port);
        final feature = createCommunitiesFeature(module: shared);
        final home = FeatureDescriptor(
          id: 'home',
          route: '/',
          labelKey: 'navigation.home',
          descriptionKey: 'navigation.home',
          icon: StarBridgeIconSemantic.community,
          navigationRegion: NavigationRegion.brand,
          order: 0,
          buildDestination: (_) => const SizedBox(),
        );
        final registry = FeatureRegistry([home, feature]);
        var allow = false;
        await tester.pumpWidget(
          MaterialApp(
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
                    mode: mode,
                    selected: feature,
                    onSelect: (_, _) {},
                    onActivate: (_) async => allow,
                  ),
                  Expanded(child: Builder(builder: feature.buildDestination)),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final shortcuts = find.byType(CommunityShortcuts);
        final firstLogo = find
            .descendant(of: shortcuts, matching: find.byType(CommunityLogo))
            .first;
        final logoBox = tester.getSize(firstLogo);
        final logoContent = find.descendant(
          of: firstLogo,
          matching: find.byType(StarBridgeIcon),
        );
        expect(logoBox, const Size(28, 28));
        expect(tester.getSize(logoContent), logoBox);
        expect(
          find.descendant(of: shortcuts, matching: find.text('组织 39')),
          findsNothing,
        );
        await tester.tap(firstLogo);
        await tester.pumpAndSettle();
        expect(shared.selected, isNull);
        allow = true;
        await tester.tap(firstLogo);
        await tester.pumpAndSettle();
        expect(shared.selected?.name, '组织 0');
        expect(port.writes, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        shared.dispose();
      },
    );
  }
}
