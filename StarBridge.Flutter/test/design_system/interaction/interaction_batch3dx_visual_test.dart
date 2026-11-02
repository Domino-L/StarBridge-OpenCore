import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_controller.dart';
import 'package:starbridge_flutter/features/settings/notification_audio_panel.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import 'interaction_batch3do_test.dart' show scopedApp, size;
import 'interaction_batch3dp_visual_test.dart' show loadVisualFonts;
import 'interaction_batch3dw_test.dart'
    show NotificationMotionPort, notificationMotionFrames;
import 'interaction_batch3dx_test.dart' show AudioMotionPort;

const _frame = Key('3dx-visual-frame');
final _output = visualOutputDir('interaction_motion_batch3dx_20261016');
const _timeout = Timeout(Duration(seconds: 60));
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en')];

Widget _app(
  NotificationSettingsModule module,
  NotificationAudioController audio,
  InteractionSuite suite, {
  required Locale locale,
  double scale = 1,
  bool light = false,
  bool reduce = false,
  bool themeOnly = false,
}) {
  final base = scopedApp(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: SizedBox.expand(
          child: NotificationSettingsPage(module: module, audio: audio),
        ),
      ),
    ),
    suite,
    locale: locale,
    light: light,
    reduce: reduce,
  ) as MaterialApp;
  final app = themeOnly
      ? MaterialApp(
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          home: base.home,
        )
      : base;
  return RepaintBoundary(key: _frame, child: app);
}

void _visible(WidgetTester t, Finder finder) {
  final rect = t.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(-.01));
  expect(rect.top, greaterThanOrEqualTo(-.01));
  expect(rect.right, lessThanOrEqualTo(430.01));
  expect(rect.bottom, lessThanOrEqualTo(850.01));
}

/// Explicit pointer scrolling, not jumpTo/ensureVisible or feedback autoscroll.
/// The local audio panel remains in its original page scroll, unlike the
/// page's fixed transaction footer. This proves reachability, not a new layout.
Future<void> _userReach(
  WidgetTester t,
  Finder content,
  List<Finder> targets,
) async {
  Rect bounds() =>
      targets.map(t.getRect).reduce((a, b) => a.expandToInclude(b));
  for (var i = 0; i < 30; i++) {
    final viewport = t.getRect(content);
    final rect = bounds();
    if (rect.top >= viewport.top + 4 && rect.bottom <= viewport.bottom - 4) {
      return;
    }
    final delta = rect.top < viewport.top + 4
        ? (viewport.top - rect.top + 12).clamp(50.0, 430.0).toDouble()
        : -(rect.bottom - viewport.bottom + 12).clamp(50.0, 430.0).toDouble();
    await t.timedDragFrom(
      Offset(viewport.right - 8, viewport.center.dy),
      Offset(0, delta),
      const Duration(milliseconds: 400),
    );
    await notificationMotionFrames(t, count: 4);
  }
  final viewport = t.getRect(content);
  final rect = bounds();
  expect(rect.top, greaterThanOrEqualTo(viewport.top - .01));
  expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + .01));
}

Future<List<int>> _pixels(WidgetTester t) async => (await t.runAsync(() async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(_frame));
  final image = await boundary.toImage();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List().toList();
  } finally {
    image.dispose();
  }
}))!;

Future<void> _save(WidgetTester t, String name) async {
  final pixels = await _pixels(t);
  await t.runAsync(() async {
    final directory = Directory(_output);
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(pixels);
  });
}

Future<void> _close(
  WidgetTester t,
  NotificationSettingsModule module,
  NotificationAudioController audio,
) async {
  await t.pumpWidget(const SizedBox.shrink());
  audio.dispose();
  module.dispose();
  await t.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
}

String _failedFooter(Locale locale) => locale.languageCode == 'en'
    ? 'Some changes could not be confirmed. Unsaved edits are retained.'
    : locale.countryCode == 'TW'
    ? '部分變更未能確認，未儲存項目已保留。'
    : '部分更改未能确认，未保存项已保留。';

void main() {
  setUpAll(loadVisualFonts);
  for (final suite in InteractionSuite.values) {
    for (final locale in _locales) {
      for (final light in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          final name =
              '${suite.name}-$locale-${light ? 'light' : 'dark'}-${scale.toInt()}';
          testWidgets(
            '$name real scrolled audio save wait and typed failure remain user reachable with original footer',
            (t) async {
              size(t, const Size(430, 850));
              final notifications = NotificationMotionPort();
              final module = createNotificationSettingsModule(notifications);
              final port = AudioMotionPort();
              final audio = NotificationAudioController(port);
              final answer = Completer<AudioPreferences>();
              Widget app({bool reduce = false}) => _app(
                module,
                audio,
                suite,
                locale: locale,
                scale: scale,
                light: light,
                reduce: reduce,
              );
              try {
                await module.initialize();
                await audio.refresh();
                final confirmed = audio.value!;
                await t.pumpWidget(app());
                await notificationMotionFrames(t);
                final panel = find.byType(NotificationAudioPanel);
                final strings = AppStrings.of(t.element(panel));
                expect(find.text(strings.text('audio.title')), findsOneWidget);
                expect(
                  find.text(strings.text('settings.notification.title')),
                  findsOneWidget,
                );
                final content = find.byKey(
                  const Key('notification-settings-content'),
                );
                final scrollFinder = find.descendant(
                  of: content,
                  matching: find.byType(Scrollable),
                );
                expect(scrollFinder, findsOneWidget);
                final scroll = t.state<ScrollableState>(scrollFinder);
                final outer = find
                    .ancestor(
                      of: find.byKey(const Key('audio-enabled')),
                      matching: find.byType(StarBridgeSwitch),
                    )
                    .first;
                await _userReach(t, content, [outer]);
                _visible(t, outer);
                await t.tap(outer);
                await notificationMotionFrames(t, count: 2);
                final drafts = NotificationDraftScope.of(t.element(panel))!;
                expect(drafts.dirty, isTrue);
                expect(port.saves, isEmpty);
                expect(audio.value, same(confirmed));
                final save = find.byKey(const Key('notification-save'));
                _visible(t, save);
                final offset = scroll.position.pixels;
                port.pendingSave = answer;
                await t.tap(save);
                await notificationMotionFrames(t, count: 2);
                // No forced scrolling between feedback insertion and this
                // check. The local wait is not asserted to be a fixed footer.
                expect(scroll.position.pixels, closeTo(offset, .01));
                expect(port.saves, hasLength(1));
                expect(port.saves.single.$1, same(confirmed));
                expect(port.saves.single.$5, InteractionSource.pointer);
                expect(audio.value, same(confirmed));
                expect(audio.busy, isTrue);
                expect(drafts.saving, isTrue);
                final wait = find.descendant(
                  of: panel,
                  matching: find.byType(SuiteBusyLabel),
                );
                expect(wait, findsOneWidget);
                await _userReach(t, content, [wait]);
                _visible(t, wait);
                _visible(t, find.byType(SuiteBusyLabel).last);
                _visible(t, save);
                expect(find.byType(LinearProgressIndicator), findsNothing);
                expect(t.takeException(), isNull);
                await _save(t, '$name-audio-pending');

                await t.pumpWidget(app(reduce: true));
                await notificationMotionFrames(t);
                for (final element in [
                  ...find
                      .descendant(
                        of: panel,
                        matching: find.byType(SuiteBusyLabel),
                      )
                      .evaluate(),
                  ...find
                      .descendant(
                        of: panel,
                        matching: find.byType(SuiteBusyFrame),
                      )
                      .evaluate(),
                ]) {
                  expect(InteractionScope.of(element).reduceMotion, isTrue);
                }
                final staticPixels = await _pixels(t);
                await t.pump(const Duration(milliseconds: 300));
                expect(await _pixels(t), staticPixels);
                expect(port.saves, hasLength(1));
                expect(port.previews, 0);
                answer.completeError(const AudioFailure('output'));
                await notificationMotionFrames(t);
                expect(audio.value, same(confirmed));
                expect(audio.error, 'output');
                expect(drafts.failed, isTrue);
                expect(drafts.dirty, isTrue);
                expect(t.widget<StarBridgeSwitch>(outer).value, isTrue);
                expect(
                  find.descendant(
                    of: panel,
                    matching: find.byType(SuiteBusyLabel),
                  ),
                  findsNothing,
                );
                final error = find.descendant(
                  of: panel,
                  matching: find.text(strings.text('audio.output')),
                );
                final retry = find.byKey(const Key('audio-retry'));
                expect(error, findsOneWidget);
                await _userReach(t, content, [error, retry]);
                _visible(t, error);
                _visible(t, retry);
                _visible(t, find.text(_failedFooter(locale)));
                _visible(t, save);
                expect(port.saves, hasLength(1));
                expect(notifications.writes, isEmpty);
                expect(port.previews, 0);
                await _save(t, '$name-audio-failure');
                expect(t.takeException(), isNull);
              } finally {
                if (!answer.isCompleted) {
                  answer.completeError(const AudioFailure('output'));
                }
                await notificationMotionFrames(t, count: 2);
                await _close(t, module, audio);
              }
            },
            timeout: _timeout,
            skip: !Platform.isWindows,
          );
        }
      }
    }

    testWidgets(
      '$suite theme-only actual audio panel retains titles and resolves local pending presentation',
      (t) async {
        size(t, const Size(430, 850));
        final notifications = NotificationMotionPort();
        final module = createNotificationSettingsModule(notifications);
        final port = AudioMotionPort();
        final audio = NotificationAudioController(port);
        final answer = Completer<AudioPreferences>();
        try {
          await module.initialize();
          await audio.refresh();
          await t.pumpWidget(
            _app(
              module,
              audio,
              suite,
              locale: const Locale('en'),
              scale: 2,
              themeOnly: true,
            ),
          );
          await notificationMotionFrames(t);
          final panel = find.byType(NotificationAudioPanel);
          final strings = AppStrings.of(t.element(panel));
          expect(find.text(strings.text('audio.title')), findsOneWidget);
          expect(find.text(strings.text('audio.enabled')), findsOneWidget);
          expect(find.text(strings.text('audio.automatic')), findsOneWidget);
          final content = find.byKey(
            const Key('notification-settings-content'),
          );
          final outer = find
              .ancestor(
                of: find.byKey(const Key('audio-enabled')),
                matching: find.byType(StarBridgeSwitch),
              )
              .first;
          await _userReach(t, content, [outer]);
          await t.tap(outer);
          await notificationMotionFrames(t, count: 2);
          port.pendingSave = answer;
          await t.tap(find.byKey(const Key('notification-save')));
          await notificationMotionFrames(t, count: 2);
          final wait = find.descendant(
            of: panel,
            matching: find.byType(SuiteBusyLabel),
          );
          await _userReach(t, content, [wait]);
          _visible(t, wait);
          final frame = find.descendant(
            of: panel,
            matching: find.byType(SuiteBusyFrame),
          );
          expect(InteractionScope.of(t.element(frame)).suite, suite);
          expect(InteractionScope.of(t.element(frame)).reduceMotion, isFalse);
          expect(port.saves, hasLength(1));
          expect(port.previews, 0);
          expect(t.takeException(), isNull);
        } finally {
          if (!answer.isCompleted) {
            answer.completeError(const AudioFailure('output'));
          }
          await notificationMotionFrames(t, count: 2);
          await _close(t, module, audio);
        }
      },
      timeout: _timeout,
    );
  }
}
