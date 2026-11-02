import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_common.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import 'interaction_batch3do_test.dart' show scopedApp, size;
import 'interaction_batch3dp_visual_test.dart' show loadVisualFonts;
import 'interaction_batch3dw_test.dart'
    show NotificationMotionPort, notificationMotionFrames;

const _frame = Key('3dw-visual-frame');
final _output = visualOutputDir('interaction_motion_batch3dw_20261016');
const _timeout = Timeout(Duration(seconds: 60));
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en')];

NotificationMotionPort _localPort() {
  final port = NotificationMotionPort();
  final review = port.stored.settings!;
  port.stored = NotificationSettingsSnapshot.available(
    revision: 11,
    settings: NotificationSettingsValue(
      localInAppOnly: true,
      desktopDeliveryAvailable: true,
      directMessageDeliveryAvailable: true,
      overlayDeliveryAvailable: true,
      channels: review.channels,
      sourceRules: const [],
      previewMode: review.previewMode,
      playerActivity: review.playerActivity,
      continuousPlay: review.continuousPlay.copyWith(enabled: false),
    ),
  );
  return port;
}

Widget _app(
  NotificationSettingsModule module,
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
        child: SizedBox.expand(child: NotificationSettingsPage(module: module)),
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

void _narrowFailureLayout(WidgetTester t, Finder failure) {
  final context = t.element(failure);
  final banner = t.widget<NotificationFailureBanner>(failure);
  final message = find.descendant(
    of: failure,
    matching: find.text(AppStrings.of(context).text(banner.messageKey)),
  );
  expect(message, findsOneWidget);
  final container = t.widget<Container>(
    find.descendant(of: failure, matching: find.byType(Container)).first,
  );
  final direction = Directionality.of(context);
  final padding = (container.padding ?? EdgeInsets.zero).resolve(direction);
  final decoration = container.decoration as BoxDecoration;
  final border = (decoration.border?.dimensions ?? EdgeInsets.zero).resolve(
    direction,
  );
  final bounds = t.getRect(failure);
  final availableWidth = bounds.width - padding.horizontal - border.horizontal;
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  if (availableWidth < 440 * scale) {
    final text = t.getRect(message);
    final retry = find.byKey(const Key('notification-failure-retry'));
    final button = t.getRect(retry);
    expect(
      text.right,
      closeTo(bounds.right - padding.right - border.right, .05),
      reason: 'Narrow long-copy messages use the whole content row, not a column squeezed by Retry.',
    );
    expect(
      button.top,
      greaterThanOrEqualTo(text.bottom - .01),
      reason: 'The unchanged retry action must be below the narrow message.',
    );
    _visible(t, message);
    _visible(t, retry);
  }
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

Future<void> _close(WidgetTester t, NotificationSettingsModule module) async {
  await t.pumpWidget(const SizedBox.shrink());
  module.dispose();
  await t.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
}

Future<void> _dragToBottom(
  WidgetTester t,
  Finder content,
  ScrollableState scroll,
) async {
  for (var i = 0; i < 18 && scroll.position.extentAfter > 1; i++) {
    await t.timedDrag(
      content,
      const Offset(0, -450),
      const Duration(milliseconds: 400),
    );
    await notificationMotionFrames(t);
  }
  expect(scroll.position.extentAfter, lessThanOrEqualTo(1));
}

Future<void> _dragToControl(
  WidgetTester t,
  Finder content,
  Finder control,
) async {
  for (var i = 0; i < 18; i++) {
    final viewport = t.getRect(content);
    final rect = t.getRect(control);
    if (rect.top >= viewport.top && rect.bottom <= viewport.bottom) return;
    final delta = rect.top < viewport.top
        ? (viewport.top - rect.top + 24).clamp(80.0, 450.0).toDouble()
        : -(rect.bottom - viewport.bottom + 24).clamp(80.0, 450.0).toDouble();
    await t.timedDrag(
      content,
      Offset(0, delta),
      const Duration(milliseconds: 400),
    );
    await notificationMotionFrames(t);
  }
  final viewport = t.getRect(content);
  final rect = t.getRect(control);
  expect(rect.top, greaterThanOrEqualTo(viewport.top));
  expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
}

void main() {
  setUpAll(loadVisualFonts);
  for (final suite in InteractionSuite.values) {
    for (final locale in _locales) {
      for (final light in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          final name =
              '${suite.name}-$locale-${light ? 'light' : 'dark'}-${scale.toInt()}';
          testWidgets(
            '$name actual local notification owner wait and failed draft stay visible at scroll bottom',
            (t) async {
              size(t, const Size(430, 850));
              final port = _localPort();
              final module = createNotificationSettingsModule(port);
              final answer = Completer<NotificationSettingsWriteResult>();
              Widget app({bool reduce = false}) => _app(
                module,
                suite,
                locale: locale,
                scale: scale,
                light: light,
                reduce: reduce,
              );
              try {
                await module.initialize();
                await t.pumpWidget(app());
                await notificationMotionFrames(t);
                final strings = AppStrings.of(
                  t.element(find.byType(NotificationSettingsPage)),
                );
                expect(
                  find.text(strings.text('settings.notification.title')),
                  findsOneWidget,
                );
                expect(
                  find.byKey(const Key('notification-channel-in-app')),
                  findsOneWidget,
                );
                expect(
                  find.byKey(const Key('notification-source-rules-panel')),
                  findsNothing,
                );
                final preview = find.byKey(
                  const Key('notification-preview-hiddenDetails'),
                );
                await t.ensureVisible(preview);
                await t.pump();
                await t.tap(preview);
                await notificationMotionFrames(t, count: 2);
                expect(port.writes, isEmpty);
                final content = find.byKey(
                  const Key('notification-settings-content'),
                );
                final scrollFinder = find.descendant(
                  of: content,
                  matching: find.byType(Scrollable),
                );
                expect(scrollFinder, findsOneWidget);
                final scroll = t.state<ScrollableState>(scrollFinder);
                await _dragToBottom(t, content, scroll);
                final offset = scroll.position.pixels;
                final save = find.byKey(const Key('notification-save'));
                _visible(t, save);
                port.pendingWrite = answer;
                await t.tap(save);
                await notificationMotionFrames(t, count: 2);
                // Never force a scroll after feedback insertion; that would
                // hide a misplaced module wait at the beginning of the body.
                expect(scroll.position.pixels, closeTo(offset, .01));
                expect(port.writes, hasLength(1));
                expect(port.writes.single.$2, 11);
                expect(port.writes.single.$3, InteractionSource.pointer);
                expect(
                  module.projection.value.settings!.previewMode,
                  NotificationPreviewMode.sourceOnly,
                );
                final wait = find.byType(HelpSupportWaiting);
                expect(wait, findsOneWidget);
                _visible(t, wait);
                _visible(t, save);
                expect(find.byType(LinearProgressIndicator), findsNothing);
                final drafts = NotificationDraftScope.of(t.element(content))!;
                expect(drafts.saving, isTrue);
                expect(drafts.dirty, isTrue);
                // Only after proving no automatic jump, explicitly drag the
                // original preview trigger back into the reduced viewport.
                // This proves access without disguising feedback insertion.
                await _dragToControl(t, content, preview);
                _visible(t, preview);
                _visible(t, wait);
                await _save(t, '$name-local-pending');
                await t.pumpWidget(app(reduce: true));
                await notificationMotionFrames(t);
                expect(find.byType(SuiteProgressBar), findsNothing);
                final staticPixels = await _pixels(t);
                await t.pump(const Duration(milliseconds: 300));
                expect(await _pixels(t), staticPixels);
                answer.complete(
                  const NotificationSettingsWriteResult.failed(
                    NotificationSettingsFailure.writeFailed,
                  ),
                );
                await notificationMotionFrames(t);
                expect(module.projection.value.revision, 11);
                expect(
                  module.projection.value.settings!.previewMode,
                  NotificationPreviewMode.sourceOnly,
                );
                expect(drafts.failed, isTrue);
                expect(drafts.dirty, isTrue);
                expect(find.byType(HelpSupportWaiting), findsNothing);
                final failure = find.byType(NotificationFailureBanner);
                expect(failure, findsOneWidget);
                _visible(t, failure);
                _narrowFailureLayout(t, failure);
                _visible(
                  t,
                  find.byKey(const Key('notification-failure-retry')),
                );
                _visible(t, save);
                expect(port.writes, hasLength(1));
                await _save(t, '$name-local-failure');
                expect(t.takeException(), isNull);
              } finally {
                if (!answer.isCompleted) {
                  answer.complete(
                    const NotificationSettingsWriteResult.failed(
                      NotificationSettingsFailure.writeFailed,
                    ),
                  );
                }
                await notificationMotionFrames(t, count: 2);
                await _close(t, module);
              }
            },
            timeout: _timeout,
            skip: !Platform.isWindows,
          );
        }
      }
    }

    testWidgets(
      '$suite theme-only full review workspace retains visible panel titles and staged content',
      (t) async {
        size(t, const Size(430, 850));
        final port = NotificationMotionPort();
        final module = createNotificationSettingsModule(port);
        try {
          await module.initialize();
          await t.pumpWidget(
            _app(
              module,
              suite,
              locale: const Locale('en'),
              scale: 2,
              themeOnly: true,
            ),
          );
          await notificationMotionFrames(t);
          final strings = AppStrings.of(
            t.element(find.byType(NotificationSettingsPage)),
          );
          for (final key in [
            'settings.notification.title',
            'settings.notification.channels.title',
            'settings.notification.preview.title',
            'settings.notification.sources.title',
            'settings.notification.activity.title',
            'settings.notification.play.title',
          ]) {
            expect(find.text(strings.text(key)), findsOneWidget);
          }
          expect(
            find.byKey(const Key('notification-source-rules-panel')),
            findsOneWidget,
          );
          expect(module.projection.value.settings!.localInAppOnly, isFalse);
          expect(port.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await _close(t, module);
        }
      },
      timeout: _timeout,
    );
  }
}
