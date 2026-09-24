import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'community_announcements_dialog_test.dart'
    show AnnouncementsWorkspaceFake;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final width in [420.0, 1200.0]) {
      testWidgets(
        'organization details show complete announcement $locale $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final port = AnnouncementsWorkspaceFake()..allowed = false;
          addTearDown(port.changes.close);
          port.current!['content'] =
              '集合前请检查补给。\n\n舰船与人员分工将在组织聊天中确认。\n请在出发前完成准备。';
          port.addHistory(1);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('details-capture'),
              child: host(port, locale),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(port.current!['content'] as String), findsNothing);
          await tester.tap(find.byKey(const Key('community-open-details')));
          await tester.pumpAndSettle();
          final inline = find.byKey(
            const Key('community-announcement-expanded'),
          );
          expect(inline, findsOneWidget);
          expect(
            find.descendant(of: inline, matching: find.text('远航准备通知')),
            findsOneWidget,
          );
          final body = find.descendant(
            of: inline,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SelectableText &&
                  widget.data == port.current!['content'],
            ),
          );
          expect(tester.widget<SelectableText>(body).maxLines, isNull);
          expect(
            find.descendant(of: inline, matching: find.text('Author (Pilot)')),
            findsNWidgets(2),
          );
          expect(port.detailReads, greaterThan(0));
          expect(port.writes, isEmpty);
          expect(tester.takeException(), isNull);
          if (width == 1200 && locale.countryCode == 'CN') {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('details-capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              await File('build/community-inline-announcement.png')
                  .writeAsBytes(bytes.buffer.asUint8List());
              image.dispose();
            });
          }
          final history = find.byKey(
            const Key('community-announcement-history-entry'),
          );
          await tester.ensureVisible(history);
          await tester.tap(history);
          await tester.pumpAndSettle();
          expect(find.text('历史公告 1'), findsOneWidget);
          port.changes.add(null);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('community-details-dialog')),
            findsNothing,
          );
          expect(find.text('Author (Pilot)'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final state in ['empty', 'error', 'long']) {
    testWidgets('inline announcement handles $state', (tester) async {
      tester.view.physicalSize = const Size(420, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = AnnouncementsWorkspaceFake();
      addTearDown(port.changes.close);
      if (state == 'empty') port.current = null;
      if (state == 'error') port.failure = 'unavailable';
      if (state == 'long') {
        port.current!['content'] = '完整公告正文需要保留并允许滚动阅读。\n' * 50;
      }
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('community-open-details')));
      await tester.pumpAndSettle();
      final inline = find.byKey(const Key('community-announcement-expanded'));
      expect(inline, findsOneWidget);
      if (state == 'empty') {
        expect(
          find.descendant(of: inline, matching: find.text('暂无当前公告')),
          findsOneWidget,
        );
      }
      if (state == 'error') {
        expect(
          find.descendant(of: inline, matching: find.text('公告暂时无法读取，请刷新重试。')),
          findsOneWidget,
        );
      }
      if (state == 'long') {
        expect(
          find.descendant(
            of: inline,
            matching: find.text(port.current!['content'] as String),
          ),
          findsOneWidget,
        );
      }
      expect(port.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
