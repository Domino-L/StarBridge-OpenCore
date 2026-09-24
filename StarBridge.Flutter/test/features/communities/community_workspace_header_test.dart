import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_copy.dart';

import 'community_workspace_test.dart';
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets('header groups structured days in $locale', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      port.reader = (target, query, offset) async => CommunityWorkspace.parse({
        ...workspacePayload(target: target),
        'activeTime': 'outdated verbose day summary',
        'timeZoneId': 'Central America Standard Time',
        'timeZoneStandardOffsetMinutes': -360,
        'timeZoneUsesDaylightSaving': false,
        'activityWindows': [
          for (final days in [
            ['mon', 'tue', 'wed'],
            ['thu', 'fri'],
          ])
            {
              'days': days,
              'startTime': '19:00',
              'endTime': '22:30',
              'endsNextDay': false,
            },
          {
            'days': ['sun', 'sat'],
            'startTime': '08:00',
            'endTime': '22:00',
            'endsNextDay': false,
          },
        ],
      });
      await tester.pumpWidget(host(port, locale));
      await tester.pumpAndSettle();
      final english = locale.languageCode == 'en';
      expect(find.textContaining(english ? 'Weekdays' : '工作日'), findsWidgets);
      expect(
        find.textContaining(
          english
              ? 'Weekends'
              : locale.countryCode == 'TW'
              ? '週末'
              : '周末',
        ),
        findsWidgets,
      );
      expect(find.textContaining('outdated verbose'), findsNothing);
      expect(find.textContaining('Central America Standard Time'), findsNothing);
      expect(find.textContaining('UTC−06:00'), findsWidgets);
      final context = tester.element(
        find.byKey(const Key('community-header-information')),
      );
      expect(
        workspaceDays(context, [
          'sun',
          'fri',
          'mon',
          'sat',
          'tue',
          'thu',
          'wed',
          'mon',
        ]),
        english ? 'Every day' : '每日',
      );
      expect(
        workspaceDays(context, ['wed', 'mon']),
        english
            ? 'Mon, Wed'
            : locale.countryCode == 'TW'
            ? '週一、週三'
            : '周一、周三',
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final size in [const Size(1280, 720), const Size(420, 720)]) {
    testWidgets('small header puts all three metrics beside the name $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      var reads = 0;
      port.reader = (target, query, offset) async {
        reads++;
        return CommunityWorkspace.parse(workspacePayload(target: target));
      };
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
      final header = find.byKey(const Key('community-header-information'));
      expect(tester.getSize(header).height, lessThanOrEqualTo(64));
      final name = tester.getRect(
        find.byKey(const Key('community-compact-name')),
      );
      for (final metric in ['online', 'gaming', 'member']) {
        final value = find.byKey(ValueKey('community-presence-value-$metric'));
        expect(value, findsOneWidget);
        final rect = tester.getRect(value);
        expect(rect.left, greaterThan(name.right));
        expect(rect.center.dy, closeTo(name.center.dy, 1));
      }
      for (final label in ['在线信息', '活跃时间', '公告', '组织联系方式']) {
        expect(
          find.descendant(of: header, matching: find.text(label)),
          findsNothing,
        );
      }
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('workspace-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/community-compact-header-${size.width.toInt()}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.byKey(const Key('community-open-details')));
      await tester.pumpAndSettle();
      expect(find.textContaining('organization-contact'), findsOneWidget);
      await tester.tap(find.byKey(const Key('community-details-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('community-details-dialog')), findsNothing);
      expect(reads, 2);
      tester.view.physicalSize = const Size(1600, 1000);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('community-header-compact')), findsNothing);
      expect(tester.getSize(header).height, greaterThan(64));
      expect(reads, 2, reason: 'Resizing does not reload organization data.');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final width in [420.0, 1200.0]) {
    testWidgets('compact overview retains full details at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
      final header = find.byKey(const Key('community-header-information'));
      for (final metric in ['online', 'gaming', 'member']) {
        final value = tester.widget<Text>(
          find.byKey(ValueKey('community-presence-value-$metric')),
        );
        expect(value.data, '1');
        expect(value.style!.fontSize, width < 1000 ? 18 : 28);
        expect(value.style!.fontWeight, FontWeight.w700);
        if (width >= 1000) {
          final label = tester.widget<Text>(
            find.byKey(ValueKey('community-presence-label-$metric')),
          );
          expect(
            value.style!.fontSize!,
            greaterThan(label.style!.fontSize! * 2),
          );
        }
      }
      expect(
        find.descendant(of: header, matching: find.byType(ExpansionTile)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
      if (width == 1200) {
        expect(tester.getSize(header).height, lessThanOrEqualTo(190));
      }
      expect(find.text('Members only details'), findsNothing);
      final tab = find.byKey(const Key('community-section-members'));
      final position = tester.getRect(tab);
      await tester.tap(find.byKey(const Key('community-open-details')));
      await tester.pumpAndSettle();
      final dialog = find.byKey(const Key('community-details-dialog'));
      for (final text in [
        'Members only details',
        '探索',
        '调查',
        '中文 / English',
        'Stanton',
      ]) {
        expect(
          find.descendant(of: dialog, matching: find.text(text)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: dialog, matching: find.textContaining('次日 01:00')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('https://example.org'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: dialog, matching: find.byType(TextButton)).last,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(tab), position);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('account invalidation removes open organization details', (
    tester,
  ) async {
    final port = WorkspaceTestPort();
    addTearDown(port.changes.close);
    await tester.pumpWidget(host(port, const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('community-open-details')));
    await tester.pumpAndSettle();
    expect(find.text('Members only details'), findsOneWidget);
    port.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('community-details-dialog')), findsNothing);
    expect(find.textContaining('organization-contact'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving workspace dismisses its details route', (tester) async {
    final port = WorkspaceTestPort();
    addTearDown(port.changes.close);
    await tester.pumpWidget(host(port, const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('community-open-details')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final width in [420.0, 1200.0]) {
    testWidgets('long and page-scoped data stays bounded at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      port.reader = (target, query, offset) async => CommunityWorkspace.parse({
        ...workspacePayload(target: target),
        'name': 'Long organization name ' * 8,
        'activeTime': 'Weekday evening and weekend sessions ' * 8,
        'externalContacts': [
          for (var i = 0; i < 20; i++)
            {
              'platform': 'Discord',
              'value': 'organization-contact-$i-${'long ' * 20}',
            },
        ],
        'totalCount': 50,
      });
      await tester.pumpWidget(host(port, const Locale('en')));
      await tester.pumpAndSettle();
      if (width >= 1000) {
        expect(find.text('This page'), findsOneWidget);
      } else {
        final context = tester.element(
          find.byKey(const Key('community-header-information')),
        );
        expect(
          find.byTooltip(
            '${workspaceText(context, 'online')} 1\n${workspaceText(context, 'presencePageScope')}',
          ),
          findsOneWidget,
        );
      }
      final header = find.byKey(const Key('community-header-information'));
      expect(
        tester.getSize(header).height,
        lessThanOrEqualTo(width == 1200 ? 190 : 380),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
