import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_directory_card.dart';
import 'package:starbridge_flutter/features/communities/community_directory_details.dart';

import '../personal_profile/profile_polish_regression_test.dart' show app;
import '../friends/social_layout_test.dart' show loadFonts;

final longDescription = List.filled(
  8,
  '我们是一群喜欢探索、协作与舰队行动的玩家。欢迎想要学习多人舰船岗位的新伙伴，也欢迎只在周末上线的朋友。\n\n'
  '活动前会说明集合时间、预计时长与任务目标。你可以选择感兴趣的岗位，不需要固定出勤。我们尊重每个人的时间，期待在星海中共同完成更多旅程。',
).join('\n\n');
final longNote = List.filled(
  4,
  '欢迎探索与运输玩家，新人可以从基础岗位开始。请在申请中说明通常在线的时间，以及希望尝试的玩法。',
).join('\n\n');
final row = CommunityCard(
  targetRef: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  organizationRef: 'org-a',
  name: '北辰探索协作组织 · Northstar Exploration Community',
  description: longDescription,
  tags: '探索 · 战斗 · 社交 · 休闲 · 新手友好 · 运输',
  memberScale: 'medium',
  language: 'zh-CN',
  activeTime: '工作日 19:00–22:30\n周末 08:00–22:00 · 跨日活动会提前公告',
  systems: const ['Stanton', 'Pyro', 'Nyx'],
  recruiting: true,
  recruitingTarget: '新手友好',
  recruitingNote: longNote,
  joinMode: 'application',
  actions: const ['apply'],
);

void main() {
  setUpAll(loadFonts);
  for (final locale in AppStrings.supportedLocales) {
    for (final size in [const Size(400, 640), const Size(1280, 720)]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          'full public details ${locale.toLanguageTag()} $size $scale',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final strings = AppStrings.resolve(locale);
            var actions = 0;
            final capture = GlobalKey();
            await tester.pumpWidget(
              app(
                Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: RepaintBoundary(
                      key: capture,
                      child: CommunityDirectoryDetails(
                        row: row,
                        text: (key) => strings.text('communities.$key'),
                        onClose: () {},
                        onAction: (_) => actions++,
                      ),
                    ),
                  ),
                ),
                locale: locale,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final description = tester.widget<SelectableText>(
              find.byKey(const ValueKey('community-details-description')),
            );
            expect(description.data, longDescription);
            expect(description.maxLines, isNull);
            expect(
              find.byWidgetPredicate(
                (widget) =>
                    widget is SelectableText &&
                    widget.data == longNote &&
                    widget.maxLines == null,
              ),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('community-gameplay-tag-运输')),
              findsOneWidget,
            );
            final action = find.byKey(
              const ValueKey('community-details-action-apply'),
            );
            final footer = find.byKey(
              const ValueKey('community-details-footer'),
            );
            final originalFooter = tester.getRect(footer);
            expect(action.hitTestable(), findsOneWidget);
            expect(originalFooter.bottom, lessThanOrEqualTo(size.height));
            if (Platform.environment['STARBRIDGE_CAPTURE_POLISH'] == '1' &&
                locale == const Locale('zh', 'CN') &&
                scale == 1) {
              final boundary =
                  capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                final data = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '../.artifacts/community-directory-details-${size.width.toInt()}.png',
                ).writeAsBytes(data!.buffer.asUint8List());
                image.dispose();
              });
            }
            final scroll = tester.widget<SingleChildScrollView>(
              find.byKey(const ValueKey('community-details-scroll')),
            );
            expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
            scroll.controller!.jumpTo(
              scroll.controller!.position.maxScrollExtent,
            );
            await tester.pumpAndSettle();
            expect(tester.getRect(footer), originalFooter);
            if (Platform.environment['STARBRIDGE_CAPTURE_POLISH'] == '1' &&
                locale == const Locale('zh', 'CN') &&
                size.width == 1280 &&
                scale == 1) {
              final boundary =
                  capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                final data = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '../.artifacts/community-directory-details-bottom.png',
                ).writeAsBytes(data!.buffer.asUint8List());
                image.dispose();
              });
            }
            expect(action.hitTestable(), findsOneWidget);
            expect(
              find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is SelectableText && widget.data == longNote,
                  )
                  .hitTestable(),
              findsOneWidget,
            );
            await tester.tap(action);
            expect(actions, 1);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets(
    'card excerpts collapse blank lines and visibly ellipsize long text',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final strings = AppStrings.resolve(const Locale('zh', 'CN'));
      await tester.pumpWidget(
        app(
          SizedBox(
            width: 975,
            child: CommunityDirectoryCard(
              row: row,
              text: (key) => strings.text('communities.$key'),
              horizontal: true,
              onDetails: () {},
              onAction: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in [
        'community-card-description-org-a',
        'community-card-recruitment-org-a',
      ]) {
        final text = find.byKey(ValueKey(key));
        final widget = tester.widget<Text>(text);
        expect(widget.overflow, TextOverflow.ellipsis);
        expect(widget.data, isNot(contains('\n')));
        expect(
          tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
          isTrue,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
