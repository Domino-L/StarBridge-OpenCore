import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_profile_rules.dart';
import 'package:starbridge_flutter/features/communities/community_profile_controller.dart';
import 'package:starbridge_flutter/features/communities/community_profile_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_system_choices.dart';
import 'package:starbridge_flutter/features/communities/legacy_community_tag_catalog.dart';

import 'community_profile_dialog_test.dart' show EditorPort;
import 'community_settings_workspace_test.dart' show openSettings, select;
import 'community_workspace_view_test.dart' show host;
import 'community_workspace_test.dart' show WorkspaceTestPort;
import '../friends/social_layout_test.dart' show loadFonts;
import 'community_image_test_support.dart';

import 'package:starbridge_flutter/features/communities/community_activity_time.dart';

void main() {
  setUpAll(loadFonts);
  test(
    'operation scale shares the reserved style pool, not a separate pool',
    () {
      final tags = LegacyCommunityTagCatalog.tags;
      final shared = tags
          .where((t) => t.categoryId == 'combat')
          .take(5)
          .map((t) => t.id);
      final core = tags.firstWhere((t) => t.categoryId == 'core').id;
      final scale = tags
          .where((t) => t.categoryId == 'scale')
          .take(2)
          .map((t) => t.id);
      final style = tags.firstWhere((t) => t.categoryId == 'style').id;
      expect(
        CommunityTagQuota([core, ...shared, ...scale], tags).valid,
        isTrue,
      );
      expect(
        CommunityTagQuota([core, ...shared, ...scale, style], tags).valid,
        isFalse,
      );
    },
  );
  test(
    'WPF overnight coupling covers equal clocks, 24h, midnight and unchecking',
    () {
      final row = <String, Object?>{
        'days': ['fri'],
        'startTime': '19:00',
        'endTime': '22:00',
        'endsNextDay': false,
      };
      final overnight = changeCommunityWindow(row, 'endTime', '02:00');
      expect(overnight['endsNextDay'], true);
      expect(communityWindowDuration(overnight), 420);
      final fullDay = changeCommunityWindow(row, 'endsNextDay', true);
      expect(fullDay['endTime'], '19:00');
      expect(communityWindowDuration(fullDay), 1440);
      final sameDay = changeCommunityWindow(fullDay, 'endsNextDay', false);
      expect(sameDay['endTime'], '19:01');
      expect(sameDay['endsNextDay'], false);
      final lastMinute = changeCommunityWindow(
        {...row, 'startTime': '23:59', 'endTime': '00:00', 'endsNextDay': true},
        'endsNextDay',
        false,
      );
      expect(lastMinute['endsNextDay'], true);
      expect(communityWindowDuration(lastMinute), 1);
      expect(communityWindowFits({...row, 'endsNextDay': true}), false);
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets(
      'activity picker uses localized clock format $locale without changing storage',
      (tester) async {
        await openSettings(tester, size: const Size(420, 720), locale: locale);
        await select(tester, 'schedule', compact: true);
        final state = tester.state<CommunityProfileDialogState>(
          find.byType(CommunityProfileDialog),
        );
        state.update('activityWindows', [
          {
            'days': ['fri'],
            'startTime': '00:00',
            'endTime': '12:00',
            'endsNextDay': false,
          },
        ]);
        await settleCommunityImages(tester);
        final periods = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.key.toString().contains('-period'),
        );
        expect(
          periods,
          locale.languageCode == 'en' ? findsNWidgets(2) : findsNothing,
        );
        if (locale.languageCode == 'en') {
          await tester.ensureVisible(periods.first);
          await tester.tap(periods.first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('PM').last);
          await settleCommunityImages(tester);
          final picker = find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                w.key.toString().contains('-startTime-0'),
          );
          expect(
            tester.widget<DropdownButtonFormField<String>>(picker).initialValue,
            '12',
          );
          expect(state.rows('activityWindows').single['startTime'], '12:00');
          expect(state.rows('activityWindows').single['endsNextDay'], true);
        }
        await tester.ensureVisible(find.byType(CheckboxListTile).first);
        await settleCommunityImages(tester);
        final capture = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('settings-capture')),
        );
        await tester.runAsync(() async {
          final image = await capture.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/community-time-${locale.toString()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final width in [420.0, 1280.0]) {
    testWidgets('schedule controls and system images fit $width', (
      tester,
    ) async {
      await openSettings(tester, size: Size(width, 720));
      await select(tester, 'schedule', compact: width < 600);
      final cards = [
        for (final id in ['stanton', 'pyro', 'nyx'])
          find.byKey(ValueKey('community-system-$id')),
      ];
      await tester.ensureVisible(cards.first);
      await settleCommunityImages(tester);
      final rects = cards.map(tester.getRect).toList();
      expect(rects.first.width, greaterThanOrEqualTo(150));
      expect(rects.first.height, greaterThanOrEqualTo(115));
      expect(rects[0].top, rects[1].top);
      if (width > 600) {
        expect(rects[2].top, rects[0].top);
      } else {
        expect(rects[2].top, greaterThan(rects[0].bottom));
      }
      final selectedBefore = List<String>.from(
        tester
            .widget<CommunitySystemChoices>(find.byType(CommunitySystemChoices))
            .selected,
      );
      await tester.tap(cards.first);
      await settleCommunityImages(tester);
      expect(
        tester
            .widget<CommunitySystemChoices>(find.byType(CommunitySystemChoices))
            .selected
            .contains('stanton'),
        !selectedBefore.contains('stanton'),
      );
      final systemBoundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('settings-capture')),
      );
      await tester.runAsync(() async {
        final image = await systemBoundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/community-system-cards-${width.toInt()}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      final formState = tester.state<CommunityProfileDialogState>(
        find.byType(CommunityProfileDialog),
      );
      formState.update('activityWindows', [
        {
          'days': ['fri'],
          'startTime': '19:00',
          'endTime': '22:00',
          'endsNextDay': false,
        },
      ]);
      await settleCommunityImages(tester);
      final startHour = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.key.toString().contains('-startTime-0'),
      );
      await tester.ensureVisible(startHour);
      await settleCommunityImages(tester);
      expect(tester.getSize(startHour).width, greaterThanOrEqualTo(110));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('settings-capture')),
      );
      await tester.runAsync(() async {
        final rendered = await boundary.toImage();
        final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
        await File('build/community-schedule-${width.toInt()}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        rendered.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant({TargetPlatform.windows}));
  }
  test(
    'mixed language edit limits use the same budget regardless of locale',
    () {
      expect(communityProfileTextFits('logoText', '中' * 8), isTrue);
      expect(communityProfileTextFits('logoText', '${'中' * 8}a'), isFalse);
      expect(communityProfileTextFits('logoText', 'x' * 16), isTrue);
      expect(communityProfileTextFits('description', 'x' * 400), isTrue);
      expect(communityProfileTextFits('description', '中' * 201), isFalse);
      expect(communityProfileTextFits('recruitingNote', '中' * 200), isTrue);
      expect(communityProfileTextFits('websiteUrl', 'x' * 257), isFalse);
      expect(communityTextUnits('中a🙂'), 5);
    },
  );
  test('core, reserved style and shared slots do not borrow in reverse', () {
    final tags = LegacyCommunityTagCatalog.tags;
    List<String> group(String id, int n) =>
        tags.where((t) => t.categoryId == id).take(n).map((t) => t.id).toList();
    CommunityTagQuota quota(int core, int style, int other) =>
        CommunityTagQuota([
          ...group('core', core),
          ...group('style', style),
          ...group('combat', other),
        ], tags);
    expect(quota(3, 2, 5).valid, isTrue);
    expect(quota(1, 3, 4).valid, isTrue);
    expect(quota(1, 7, 0).valid, isTrue);
    expect(quota(1, 8, 0).valid, isFalse);
    expect(quota(1, 0, 6).valid, isFalse);
    expect(quota(4, 0, 0).valid, isFalse);
    expect(quota(0, 2, 3).valid, isFalse);
  });
  test(
    'recruiting changes are atomic and lock discovery and invite only',
    () async {
      final port = EditorPort();
      (port.profile['profile'] as Map)['joinPolicy'] = 'Invite';
      final model = CommunityProfileController(port, 'a' * 32);
      await model.load();
      model.update('recruitingEnabled', true);
      expect(model.fields['publicListingEnabled'], true);
      expect(model.fields['joinPolicy'], 'Approval');
      expect(model.update('publicListingEnabled', false), false);
      expect(model.update('joinPolicy', 'Invite'), false);
      await model.save();
      expect(port.saves.single['publicListingEnabled'], true);
      expect(port.saves.single['joinPolicy'], 'Approval');
      model.dispose();
    },
  );
  test('old long text reads and survives unrelated edits, new overflow cannot save', () async {
    final port = EditorPort();
    (port.profile['profile'] as Map)['description'] = '旧' * 300;
    final model = CommunityProfileController(port, 'a' * 32);
    await model.load();
    model.update('logoText', 'TEST');
    await model.save();
    expect(port.saves.single.containsKey('description'), false);
    model.update('description', '新' * 201);
    await model.save();
    expect(port.saves.length, 1);
    expect(model.error, 'textTooLong');
    model.dispose();
  });
  testWidgets('profile replaces language and time free text with choices', (
    tester,
  ) async {
    await openSettings(tester);
    await select(tester, 'schedule');
    expect(
      find.byKey(const ValueKey('profile-language-English')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is TextFormField &&
            (w.key.toString().contains('-language') ||
                w.key.toString().contains('-activeTime') ||
                w.key.toString().contains('-activeDaysDescription')),
      ),
      findsNothing,
    );
    final state = tester.state<CommunityProfileDialogState>(
      find.byType(CommunityProfileDialog),
    );
    state.update('activityWindows', [
      {
        'days': ['fri'],
        'startTime': '19:00',
        'endTime': '22:00',
        'endsNextDay': false,
      },
    ]);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.key.toString().contains('-startTime-'),
      ),
      findsNWidgets(2),
    );
    expect(find.text('斯坦顿'), findsOneWidget);
    expect(find.text('派罗'), findsOneWidget);
    expect(find.text('尼克斯'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('small information header expands in place and collapses again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final port = WorkspaceTestPort();
    addTearDown(port.changes.close);
    await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    final header = find.byKey(const Key('community-header-information'));
    final compact = tester.getSize(header).height;
    await tester.tap(find.byKey(const Key('community-header-expand')));
    await tester.pumpAndSettle();
    expect(tester.getSize(header).height, greaterThan(compact));
    expect(find.text('活跃时间'), findsOneWidget);
    await tester.tap(find.byKey(const Key('community-header-collapse')));
    await tester.pumpAndSettle();
    expect(tester.getSize(header).height, compact);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
