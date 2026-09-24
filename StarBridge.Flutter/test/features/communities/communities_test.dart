import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/communities_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/communities_page.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/communities/bridge_communities.dart';

import '../friends/social_layout_test.dart' show loadFonts;

class PendingCommunityPort implements CommunitiesPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final pending = Completer<CommunityDirectory>();
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) => pending.future;
  @override
  Future<String> execute(String action, String targetRef) async => 'accepted';
  @override
  Future<void> close() async => changes.close();
}

void main() {
  setUpAll(loadFonts);
  test('All three locales cover the same community vocabulary', () {
    expect(communitiesZhTw.keys.toSet(), communitiesZhCn.keys.toSet());
    expect(communitiesEn.keys.toSet(), communitiesZhCn.keys.toSet());
  });
  test(
    'An account change clears cards and rejects late directory responses',
    () async {
      final port = PendingCommunityPort();
      final active = CommunitiesModule(port);
      final reading = active.refresh();
      port.changes.add(null);
      port.pending.complete(
        const CommunityDirectory('mine', '', [
          CommunityCard(targetRef: 'old', name: 'old account'),
        ]),
      );
      await reading;
      expect(active.directory, isNull);
      expect(active.selected, isNull);
      expect(active.accountRevision, 1);
      active.dispose();
    },
  );
  test(
    'Example application and withdrawal change only that organization',
    () async {
      final model = CommunitiesModule(ExampleCommunities());
      await model.refresh(newView: 'discover');
      final before = model.directory!.items;
      await model.execute(before.last, 'apply');
      expect(model.directory!.items.last.relationship, 'pending');
      expect(model.directory!.items.first.relationship, 'member');
      await model.execute(model.directory!.items.last, 'withdraw');
      expect(model.directory!.items.last.relationship, 'none');
      model.dispose();
    },
  );
  test(
    'Unknown versions, oversized lists and untrusted actions are rejected',
    () {
      final value = <String, Object?>{
        'schemaVersion': 1,
        'view': 'mine',
        'query': '',
        'next': null,
        'items': [],
      };
      expect(parseCommunityDirectory(value).items, isEmpty);
      expect(
        () => parseCommunityDirectory({...value, 'schemaVersion': 2}),
        throwsFormatException,
      );
      expect(
        () => parseCommunityDirectory({...value, 'items': List.filled(21, {})}),
        throwsFormatException,
      );
      expect(
        () => parseCommunityDirectory({...value, 'view': 'admin'}),
        throwsFormatException,
      );
    },
  );
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [800.0, 1280.0]) {
      testWidgets(
        'Community navigation and cards ${locale.toLanguageTag()} $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
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
                body: RepaintBoundary(
                  key: const ValueKey('community-capture'),
                  child: CommunitiesPage(createPort: ExampleCommunities.new),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('示例 · 休闲协作'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('示例 · 探索交流'),
            250,
            scrollable: find.descendant(
              of: find.byWidgetPredicate(
                (widget) =>
                    widget is ListView &&
                    widget.key.toString().contains('community-directory-'),
              ),
              matching: find.byType(Scrollable),
            ),
          );
          expect(find.text('示例 · 探索交流'), findsOneWidget);
          expect(tester.takeException(), isNull);
          final strings = AppStrings.resolve(locale);
          await tester.tap(
            find.text(strings.text('communities.discover')).first,
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('示例 · 新手互助'),
            250,
            scrollable: find.descendant(
              of: find.byWidgetPredicate(
                (widget) =>
                    widget is ListView &&
                    widget.key.toString().contains('community-directory-'),
              ),
              matching: find.byType(Scrollable),
            ),
          );
          expect(find.text('示例 · 新手互助'), findsOneWidget);
          await tester.ensureVisible(
            find
                .widgetWithText(
                  FilledButton,
                  strings.text('communities.action.apply'),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find
                .widgetWithText(
                  FilledButton,
                  strings.text('communities.action.apply'),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(FilledButton),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(strings.text('communities.done.apply')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('COMMUNITY_CAPTURE') &&
              locale == const Locale('zh', 'CN') &&
              width == 1280) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('community-capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '${Directory.systemTemp.path}/starbridge-community-${DateTime.now().microsecondsSinceEpoch}.png',
              );
              await file.writeAsBytes(data!.buffer.asUint8List());
              // ignore: avoid_print
              print('COMMUNITY_CAPTURE=${file.path}');
              image.dispose();
            });
          }
        },
      );
    }
  }
}
