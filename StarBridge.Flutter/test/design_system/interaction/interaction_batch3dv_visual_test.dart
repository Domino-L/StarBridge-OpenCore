import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/event_scope_editor.dart';
import 'package:starbridge_flutter/features/settings/event_sharing_page.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import 'interaction_batch3do_test.dart' show size;
import 'interaction_batch3dp_visual_test.dart' show loadVisualFonts;
import 'interaction_batch3dv_test.dart'
    show
        EventMotionBridge,
        eventMotionApp,
        eventMotionFrames,
        eventMotionReady,
        eventMotionControl,
        eventMotionClose;

const _frame = Key('3dv-visual-frame');
const _timeout = Timeout(Duration(seconds: 60));
final _output = visualOutputDir('interaction_motion_batch3dv_20261016');
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en')];

Finder _editor(String scope) => find.byWidgetPredicate(
  (w) => w is EventScopeEditor && w.scopeKey == 'event-$scope',
);

void _titles(WidgetTester t) {
  expect(find.byType(EventScopeEditor), findsNWidgets(3));
  for (final scope in ['room', 'A', 'B']) {
    final editor = _editor(scope);
    final widget = t.widget<EventScopeEditor>(editor);
    expect(
      find.descendant(of: editor, matching: find.text(widget.title)),
      findsOneWidget,
      reason: 'Each actual scope heading must be painted, not only announced.',
    );
    final strings = AppStrings.of(t.element(editor));
    for (final field in ['presence', 'server', 'ship', 'location', 'life']) {
      final target = eventMotionControl(scope, field);
      expect(
        find.descendant(
          of: target,
          matching: find.text(strings.text('settings.privacy.events.$field')),
        ),
        findsOneWidget,
      );
    }
  }
}

void _visible(WidgetTester t, Finder target) {
  final rect = t.getRect(target);
  expect(rect.left, greaterThanOrEqualTo(-.01));
  expect(rect.top, greaterThanOrEqualTo(-.01));
  expect(rect.right, lessThanOrEqualTo(430.01));
  expect(rect.bottom, lessThanOrEqualTo(850.01));
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

void main() {
  setUpAll(loadVisualFonts);
  for (final suite in InteractionSuite.values) {
    for (final locale in _locales) {
      for (final light in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          final name =
              '${suite.name}-$locale-${light ? 'light' : 'dark'}-${scale.toInt()}';
          testWidgets(
            '$name last community action preserves offset before deliberate scroll and keeps fixed feedback visible',
            (t) async {
              size(t, const Size(430, 850));
              final bridge = EventMotionBridge();
              Widget app({bool reduce = false}) => RepaintBoundary(
                key: _frame,
                child: eventMotionApp(
                  bridge,
                  suite,
                  light: light,
                  scale: scale,
                  locale: locale,
                  reduce: reduce,
                ),
              );
              try {
                await t.pumpWidget(app());
                final controller = await eventMotionReady(t, bridge);
                _titles(t);
                final scrollFinder = find.descendant(
                  of: find.byType(EventSharingPage),
                  matching: find.byType(Scrollable),
                );
                expect(scrollFinder, findsOneWidget);
                final scroll = t.state<ScrollableState>(scrollFinder);
                scroll.position.jumpTo(scroll.position.maxScrollExtent);
                await eventMotionFrames(t, count: 2);
                final trigger = eventMotionControl('B', 'life');
                _visible(t, trigger);
                final before = controller.snapshot;
                final offset = scroll.position.pixels;
                // Directly click the already-visible last community. Never
                // ensureVisible or force a scroll after pending feedback adds
                // its footer height; that would hide an anchoring regression.
                await t.tap(trigger);
                await eventMotionFrames(t, count: 2);
                expect(scroll.position.pixels, closeTo(offset, .01));
                expect(bridge.saves, hasLength(1));
                expect(controller.snapshot, same(before));
                expect(controller.choice('B').selectedTypes, 47);
                expect(t.widget<StarBridgeSwitch>(trigger).value, isTrue);
                expect(t.widget<StarBridgeSwitch>(trigger).onChanged, isNull);
                final wait = find.byType(HelpSupportWaiting);
                expect(wait, findsOneWidget);
                _visible(t, wait);
                final strings = AppStrings.of(
                  t.element(find.byType(EventSharingPage)),
                );
                final status = find.text(
                  strings.text('settings.privacy.events.savedPaused'),
                );
                expect(status, findsOneWidget);
                _visible(t, status);
                final waitWidget = t.widget<HelpSupportWaiting>(wait);
                expect(waitWidget.source, InteractionSource.pointer);
                expect(
                  waitWidget.label,
                  contains(strings.text('settings.privacy.events.pending')),
                );
                expect(
                  waitWidget.label,
                  isNot(contains(strings.text('privacy.local.saving'))),
                );
                expect(find.byType(LinearProgressIndicator), findsNothing);
                // The fixed feedback legitimately reduces the body's viewport
                // at large text sizes. Only after proving no automatic jump,
                // model an explicit user scroll and prove the triggering row
                // remains reachable above (not behind) the feedback.
                final overflow =
                    t.getRect(trigger).bottom - t.getRect(scrollFinder).bottom;
                if (overflow > 0) {
                  await t.drag(scrollFinder, Offset(0, -overflow - 24));
                  await eventMotionFrames(t, count: 2);
                }
                _visible(t, trigger);
                expect(
                  t.getRect(trigger).bottom,
                  lessThanOrEqualTo(t.getRect(scrollFinder).bottom + .01),
                );
                _visible(t, wait);
                _visible(t, status);
                _titles(t);
                await _save(t, '$name-pending');
                await t.pumpWidget(app(reduce: true));
                await eventMotionFrames(t);
                expect(find.byType(SuiteProgressBar), findsNothing);
                final staticPixels = await _pixels(t);
                await t.pump(const Duration(milliseconds: 300));
                expect(
                  await _pixels(t),
                  staticPixels,
                  reason: 'The whole real page, footer and focused control must settle.',
                );
                await bridge.reply(bridge.saves.single, const {}, failed: true);
                await eventMotionFrames(t);
                expect(controller.snapshot, same(before));
                expect(controller.error, 'events.write_unconfirmed');
                expect(find.byType(HelpSupportWaiting), findsNothing);
                final failure = find.text(
                  strings.text('settings.privacy.events.unavailable'),
                );
                expect(failure, findsOneWidget);
                _visible(t, failure);
                expect(bridge.saves, hasLength(1));
                expect(bridge.reads, hasLength(1));
                _titles(t);
                await _save(t, '$name-failure');
                expect(t.takeException(), isNull);
              } finally {
                await eventMotionClose(t, bridge);
              }
            },
            timeout: _timeout,
            skip: !Platform.isWindows,
          );
        }
      }
    }

    testWidgets(
      '$suite theme-only event page retains actual room and community field titles',
      (t) async {
        size(t, const Size(430, 850));
        final bridge = EventMotionBridge();
        try {
          await t.pumpWidget(
            eventMotionApp(
              bridge,
              suite,
              themeOnly: true,
              locale: const Locale('en'),
              scale: 2,
            ),
          );
          await eventMotionReady(t, bridge);
          _titles(t);
          expect(find.byType(StarBridgeSwitch), findsNWidgets(15));
          expect(t.takeException(), isNull);
        } finally {
          await eventMotionClose(t, bridge);
        }
      },
      timeout: _timeout,
    );
  }
}
