import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/communities/bridge_communities.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/communities_page.dart';
import 'package:starbridge_flutter/features/communities/community_directory_card.dart';

import '../personal_profile/profile_polish_regression_test.dart' show app;
import '../friends/social_layout_test.dart' show loadFonts;

const recruiting = CommunityCard(
  targetRef: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  organizationRef: 'org-a',
  name: '北辰探索协作组织 · Northstar',
  memberScale: 'medium',
  language: 'zh-CN',
  activeTime: '工作日 19:00–22:30 · 周末 08:00–22:00',
  tags: '探索 · 战斗 · 社交 · 休闲 · 新手友好 · 运输',
  description: '一起探索星系，也欢迎下班后轻松飞一趟的伙伴。\n定期组织舰队活动，重视协作，不要求每天上线。',
  recruiting: true,
  recruitingTarget: '新手友好',
  recruitingNote: '提供入门指导，欢迎参与周末多人舰船活动。无需固定出勤，报名时请说明希望尝试的岗位。',
  joinMode: 'application',
  actions: ['apply'],
);
const ordinary = CommunityCard(
  targetRef: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  organizationRef: 'org-b',
  name: '远航物流',
  memberCount: 32,
  language: 'en',
  tags: '运输 · 工业',
  description: '专注运输与工业协作。',
  joinMode: 'direct',
  actions: ['join'],
);

class DirectoryPort implements CommunitiesPort {
  final changes = StreamController<void>.broadcast(sync: true);
  int reads = 0, writes = 0;
  List<CommunityCard> rows = [recruiting, ordinary];
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async {
    reads++;
    return CommunityDirectory(view, query, rows);
  }

  @override
  Future<String> execute(String action, String targetRef) async {
    writes++;
    return 'rejected';
  }

  @override
  Future<void> close() async => changes.close();
}

void main() {
  setUpAll(loadFonts);
  testWidgets('small desktop window shows the whole first card and action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = DirectoryPort();
    final model = CommunitiesModule(port);
    await model.refresh(newView: 'discover');
    final capture = GlobalKey();
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width - 224,
              height: MediaQuery.sizeOf(context).height - 64,
              child: RepaintBoundary(
                key: capture,
                child: CommunitiesPage(createPort: () => port, module: model),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final card = find.byKey(const ValueKey('community-card-org-a'));
    final list = find.ancestor(of: card, matching: find.byType(ListView));
    final action = find.byKey(const ValueKey('community-card-primary-org-a'));
    expect(
      tester.getRect(card).bottom,
      lessThanOrEqualTo(tester.getRect(list).bottom),
    );
    expect(action.hitTestable(), findsOneWidget);
    for (final tag in ['探索', '战斗', '社交', '休闲', '新手友好', '运输']) {
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(ValueKey('community-gameplay-tag-$tag')),
        ),
        findsOneWidget,
      );
    }
    expect(find.descendant(of: card, matching: find.text('+3')), findsNothing);
    expect(tester.getSize(card).height, lessThanOrEqualTo(320));
    expect(
      tester.getSize(card),
      tester.getSize(find.byKey(const ValueKey('community-card-org-b'))),
    );
    if (Platform.environment['STARBRIDGE_CAPTURE_POLISH'] == '1') {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('../.artifacts/community-card-small-window.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(port.writes, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final reads = port.reads;
    for (final size in [const Size(1920, 1080), const Size(1280, 720)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(card).height, size.height == 720 ? 304 : 464);
      expect(action.hitTestable(), findsOneWidget);
      expect(port.reads, reads);
      expect(model.selected, isNull);
    }
    await tester.pumpWidget(const SizedBox());
    model.dispose();
    await tester.pumpAndSettle();
  });
  for (final locale in AppStrings.supportedLocales) {
    for (final textScale in [1.0, 1.5]) {
      testWidgets('flat card ${locale.toLanguageTag()} $textScale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1300, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final strings = AppStrings.resolve(locale);
        var details = 0, actions = 0;
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: SizedBox(
                  width: 720 * textScale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final row in [recruiting, ordinary])
                        CommunityDirectoryCard(
                          row: row,
                          horizontal: true,
                          text: (k) => strings.text('communities.$k'),
                          onDetails: () => details++,
                          onAction: (_) => actions++,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(const ValueKey('community-card-org-a'))),
          Size(720 * textScale, 304 * textScale),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('community-card-org-b'))),
          Size(720 * textScale, 304 * textScale),
        );
        expect(
          find.text(
            recruiting.description.replaceAll(RegExp(r'\s+'), ' ').trim(),
          ),
          findsOneWidget,
        );
        expect(find.text(recruiting.recruitingNote), findsOneWidget);
        expect(
          find.byKey(const ValueKey('community-gameplay-tag-探索')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('community-card-primary-org-a')),
        );
        expect(actions, 1);
        expect(details, 0);
        await tester.tap(
          find.byKey(const ValueKey('community-card-open-org-a')),
        );
        expect(details, 1);
        expect(actions, 1);
      });
    }
    for (final width in [320.0, 520.0]) {
      for (final textScale in [1.0, 1.5]) {
        testWidgets('fixed cards ${locale.toLanguageTag()} $width $textScale', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1200, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final strings = AppStrings.resolve(locale);
          final capture = GlobalKey();
          await tester.pumpWidget(
            app(
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: RepaintBoundary(
                    key: capture,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final row in [recruiting, ordinary])
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: width,
                              child: CommunityDirectoryCard(
                                row: row,
                                text: (k) => strings.text('communities.$k'),
                                onDetails: () {},
                                onAction: (_) {},
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byKey(const ValueKey('community-card-org-a'))),
            tester.getSize(find.byKey(const ValueKey('community-card-org-b'))),
          );
          expect(find.text('32'), findsOneWidget);
          expect(
            find.text(
              strings
                  .text('communities.option.scale.medium')
                  .split(' · ')
                  .first,
            ),
            findsOneWidget,
          );
          if (width == 520 && textScale == 1) {
            expect(find.text('+3'), findsNothing);
            expect(
              find.byKey(const ValueKey('community-gameplay-tag-运输')),
              findsNWidgets(2),
            );
          }
          if (Platform.environment['STARBRIDGE_CAPTURE_POLISH'] == '1' &&
              locale == const Locale('zh', 'CN') &&
              width == 520 &&
              textScale == 1) {
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: Offset.zero);
            await mouse.moveTo(
              tester.getCenter(
                find.byKey(const ValueKey('community-card-open-org-a')),
              ),
            );
            await tester.pumpAndSettle();
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('../.artifacts/community-card-preview-v1.png')
                  .writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
            await mouse.removePointer();
          }
        });
      }
    }
  }

  testWidgets(
    'details retain directory, scroll and account isolation; action does not open details',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = DirectoryPort();
      final model = CommunitiesModule(port);
      await model.refresh(newView: 'discover');
      await tester.pumpWidget(
        app(CommunitiesPage(createPort: () => port, module: model)),
      );
      await tester.pumpAndSettle();
      final beforeReads = port.reads;
      await tester.tap(find.byKey(const ValueKey('community-card-open-org-a')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('community-directory-details')),
        findsOneWidget,
      );
      expect(model.selected, isNull);
      expect(port.reads, beforeReads);
      expect(
        find
            .byType(SelectableText)
            .evaluate()
            .map((e) => (e.widget as SelectableText).data),
        contains(recruiting.recruitingNote),
      );
      await tester.tap(
        find.byKey(const ValueKey('community-details-action-apply')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(port.writes, 0);
      expect(model.selected, isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(model.selected, isNull);
      final primary = find.byKey(
        const ValueKey('community-card-primary-org-a'),
      );
      await tester.ensureVisible(primary);
      await tester.tap(primary);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('community-directory-details')),
        findsNothing,
      );
      expect(port.writes, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('community-card-open-org-a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('community-card-open-org-a')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('community-directory-details')),
        findsOneWidget,
      );
      port.rows = [];
      port.changes.add(null);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('community-directory-details')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      model.dispose();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'optional recruitment note parses and survives confirmed name updates',
    () async {
      final port = DirectoryPort();
      final model = CommunitiesModule(port);
      await model.refresh(newView: 'discover');
      model.applyOrganizationName('org-a', 'TEST', 'New name');
      expect(
        model.directory!.items.first.recruitingNote,
        recruiting.recruitingNote,
      );
      final payload = <String, Object?>{
        'schemaVersion': 1,
        'view': 'discover',
        'query': '',
        'items': [
          {
            'targetRef': recruiting.targetRef,
            'name': 'Fixture',
            'description': '',
            'relationship': 'none',
            'joinMode': 'application',
            'actions': ['apply'],
            'language': '',
            'activeTime': '',
            'memberCount': null,
            'recruiting': true,
            'recruitingNote': 'Weekend crews welcome',
          },
        ],
      };
      expect(
        parseCommunityDirectory(payload).items.single.recruitingNote,
        'Weekend crews welcome',
      );
      model.dispose();
    },
  );
}
