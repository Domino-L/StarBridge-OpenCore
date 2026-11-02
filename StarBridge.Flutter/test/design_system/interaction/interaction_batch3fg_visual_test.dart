import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/hangar_browser_viewport.dart';
import 'package:starbridge_flutter/features/hangar/hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_save_panel.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_removal_dialog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/hangar/hangar_reader_test.dart'
    show BrowserFake, PreviewFake;
import '../../features/hangar/local_hangar_save_test.dart' show SaveFake;
import '../../features/hangar/local_hangar_reconciliation_test.dart'
    show ReviewPort;
import 'interaction_batch3i_test.dart' show scopedApp;

final _captureDir = const bool.hasEnvironment('INTERACTION_CAPTURE_DIR')
    ? const String.fromEnvironment('INTERACTION_CAPTURE_DIR')
    : visualOutputDir(
        'interaction_motion_batch3fg_20261017',
        legacySubdirectory: 'review',
      );
const _suites = [
  InteractionSuite.rail,
  InteractionSuite.scan,
  InteractionSuite.glow,
];
const _locales = [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en', 'US')];

Finder _key(String key) => find.byKey(Key(key));

Widget _app(
  Widget child,
  InteractionSuite suite,
  bool light,
  Locale locale,
  GlobalKey frame,
) {
  final base = scopedApp(child, suite, light: light) as MaterialApp;
  return RepaintBoundary(
    key: frame,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: base.theme,
      themeAnimationDuration: base.themeAnimationDuration,
      locale: locale,
      supportedLocales: base.supportedLocales,
      localizationsDelegates: base.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.5)),
        child: base.builder!(context, child),
      ),
      home: base.home,
    ),
  );
}

Future<void> _frames(WidgetTester t, [int count = 8]) async {
  await t.pump();
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _activate(
  WidgetTester t,
  Finder target, {
  bool keyboard = false,
}) async {
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  await _frames(t);
  if (keyboard) {
    final widget = t.widget(target);
    final node = switch (widget) {
      SuitePressable button => button.focusNode!,
      ButtonStyleButton button => button.focusNode!,
      _ => throw StateError('Unsupported production button $widget'),
    };
    for (var i = 0; !node.hasPrimaryFocus && i < 64; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(node.hasPrimaryFocus, isTrue, reason: 'Real Tab must reach $target');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await t.tap(target);
  }
  await _frames(t);
}

Future<void> _check(WidgetTester t, String key) async {
  final target = _key(key);
  expect(target, findsOneWidget);
  // The key remains on the actual checkbox, whose tile control is decorative.
  // Hit the existing row owner; do not call a callback or tap IgnorePointer.
  final row = find
      .ancestor(of: target, matching: find.byType(GestureDetector))
      .first;
  await _activate(t, row);
}

List<double> _rect(Rect rect) => [rect.left, rect.top, rect.width, rect.height];

Map<String, Object?> _bounds(
  WidgetTester t,
  List<String> keys,
  Size viewport,
  String phase,
) {
  expect(t.takeException(), isNull, reason: '$phase overflow');
  final result = <String, Object?>{};
  for (final key in keys) {
    final target = _key(key);
    expect(target, findsOneWidget, reason: phase);
    expect(MediaQuery.textScalerOf(t.element(target)).scale(16), 24);
    final rect = t.getRect(target);
    expect(rect.width, greaterThan(0), reason: '$phase $key');
    expect(rect.height, greaterThan(0), reason: '$phase $key');
    expect(rect.left, greaterThanOrEqualTo(-0.01), reason: '$phase $key');
    expect(
      rect.right,
      lessThanOrEqualTo(viewport.width + 0.01),
      reason: '$phase $key',
    );
    expect(rect.top, greaterThanOrEqualTo(-0.01), reason: '$phase $key');
    expect(
      rect.bottom,
      lessThanOrEqualTo(viewport.height + 0.01),
      reason: '$phase $key',
    );
    result[key] = _rect(rect);
  }
  return {'phase': phase, 'rects': result, 'overflow': false};
}

class _Reader {
  _Reader(this.account);
  final AccountModule account;
  final browser = BrowserFake();
  final preview = PreviewFake();
  final frame = GlobalKey();
  final capture = Completer<Map<String, Object?>>();
}

Future<_Reader> _reader(
  WidgetTester t,
  InteractionSuite suite,
  bool light,
  Locale locale,
) async {
  final account = createAccountModule(
    InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
  );
  await account.initialize();
  final probe = _Reader(account);
  await t.pumpWidget(
    _app(
      HangarPage(
        account: account,
        previewFactory: () => probe.preview,
        browserFactory: () => probe.browser,
      ),
      suite,
      light,
      locale,
      probe.frame,
    ),
  );
  await _frames(t);
  await _activate(t, _key('hangar-open-reader'));
  expect(probe.browser.opens, 1);
  expect(probe.preview.begins, 0);
  probe.browser.pendingCapture = probe.capture;
  return probe;
}

Future<void> _releaseReader(WidgetTester t, _Reader probe) async {
  if (!probe.capture.isCompleted) probe.capture.complete({});
  await _frames(t);
  await t.pumpWidget(const SizedBox());
  await _frames(t);
  probe.account.dispose();
}

Widget _savePanel(
  LocalHangarPort port,
  VoidCallback saved, {
  int shipCount = 1,
}) => SingleChildScrollView(
  child: Padding(
    padding: const EdgeInsets.all(12),
    child: LocalHangarSavePanel(
      port: port,
      view: {
        'operationId': 'scan',
        'shipCount': shipCount,
        'phase': 'complete',
      },
      onSaved: saved,
    ),
  ),
);

Future<List<int>> _pixels(
  WidgetTester t,
  GlobalKey frame,
  Rect globalRect,
) async {
  final boundary =
      frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final rect = globalRect.shift(-boundary.localToGlobal(Offset.zero));
  return (await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      final left = rect.left.floor().clamp(0, image.width).toInt();
      final top = rect.top.floor().clamp(0, image.height).toInt();
      final right = rect.right.ceil().clamp(0, image.width).toInt();
      final bottom = rect.bottom.ceil().clamp(0, image.height).toInt();
      return <int>[
        for (var y = top; y < bottom; y++)
          ...bytes.sublist(
            (y * image.width + left) * 4,
            (y * image.width + right) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

int _changes(List<int> before, List<int> after) {
  expect(after.length, before.length);
  var changed = 0;
  for (var i = 0; i < before.length; i += 4) {
    if (before[i] != after[i] ||
        before[i + 1] != after[i + 1] ||
        before[i + 2] != after[i + 2] ||
        before[i + 3] != after[i + 3]) {
      changed++;
    }
  }
  return changed;
}

Future<Map<String, Object?>> _touch(
  WidgetTester t,
  GlobalKey frame,
  String key,
  VoidCallback unchanged,
) async {
  final target = _key(key);
  await t.ensureVisible(target);
  await _frames(t);
  final rect = t.getRect(target);
  final baseline = await _pixels(t, frame, rect);
  await t.pump(const Duration(milliseconds: 182));
  expect(
    _changes(baseline, await _pixels(t, frame, rect)),
    0,
    reason: '$key idle',
  );
  final pointer = await t.startGesture(
    rect.center,
    kind: ui.PointerDeviceKind.touch,
  );
  var changed = 0;
  try {
    await t.pump(const Duration(milliseconds: 150));
    await t.pump(const Duration(milliseconds: 32));
    expect(t.getRect(target), rect, reason: '$key must not relayout');
    changed = _changes(baseline, await _pixels(t, frame, rect));
    expect(changed, greaterThan(0), reason: '$key visible touch feedback');
    unchanged();
  } finally {
    await pointer.cancel();
    await _frames(t);
  }
  unchanged();
  expect(t.takeException(), isNull);
  return {
    'key': key,
    'rect': _rect(rect),
    'idleChanges': 0,
    'touchChanges': changed,
  };
}

Future<Map<String, Object?>> _waitPixels(
  WidgetTester t,
  GlobalKey frame,
  String key,
  bool keyboard,
) async {
  final target = _key(key);
  expect(target, findsOneWidget);
  final rect = t.getRect(target);
  expect(rect.width, greaterThan(0));
  expect(rect.height, greaterThan(0));
  final before = await _pixels(t, frame, rect);
  await t.pump(const Duration(milliseconds: 600));
  expect(t.getRect(target), rect, reason: '$key wait geometry');
  final changed = _changes(before, await _pixels(t, frame, rect));
  expect(
    changed,
    keyboard ? 0 : greaterThan(0),
    reason: '$key source-specific pixels',
  );
  return {
    'key': key,
    'rect': _rect(rect),
    'elapsedMs': 600,
    'changedPixels': changed,
  };
}

Future<void> _capture(WidgetTester t, GlobalKey frame, String name) async {
  final boundary =
      frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(_captureDir);
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final layouts = <Map<String, Object?>>[];
  final feedback = <Map<String, Object?>>[];
  setUpAll(() async {
    await loadFonts();
    await (FontLoader('Source Code Pro')
          ..addFont(rootBundle.load('assets/fonts/SourceCodeVF-Upright.ttf')))
        .load();
  });
  tearDownAll(() async {
    final dir = Directory(_captureDir);
    await dir.create(recursive: true);
    await File('${dir.path}/visual-summary.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'Actual HangarPage fake-browser entry; actual save/removal components with existing ports',
        'excluded':
            'Native browser pixels/real RSI/Host persistence/device acceptance',
        'textScale': 1.5,
        'height': 1100,
        'layouts': layouts,
        'feedback': feedback,
      }),
    );
  });
  for (final suite in _suites) {
    for (final light in [false, true]) {
      final palette = light ? 'light' : 'dark';
      for (final locale in _locales) {
        for (final width in [540.0, 1100.0]) {
          testWidgets(
            '3fg reader/save/removal $suite $palette ${locale.toLanguageTag()} $width',
            (t) async {
              final viewport = Size(width, 1100);
              size(t, viewport);
              final phases = <Map<String, Object?>>[];
              final reader = await _reader(t, suite, light, locale);
              try {
                phases.add(
                  _bounds(
                    t,
                    [
                      'hangar-reader-status',
                      'hangar-reader-action',
                      'hangar-reader-reopen',
                      'hangar-browser-viewport',
                      'hangar-reader-live-results',
                    ],
                    viewport,
                    'reader-ready',
                  ),
                );
                final browser = t.getRect(_key('hangar-browser-viewport'));
                final results = t.getRect(_key('hangar-reader-live-results'));
                expect(browser.overlaps(results), isFalse);
                // The native child occupies the content, not the existing
                // one-pixel border on each edge of its parent Container.
                final browserContent = t.getRect(
                  find.byType(HangarBrowserViewport),
                );
                expect(browserContent, browser.deflate(1));
                phases.last['browserContentRect'] = _rect(browserContent);
                expect(
                  reader.browser.rect.width,
                  closeTo(browserContent.width, 0.01),
                );
                expect(
                  reader.browser.rect.height,
                  closeTo(browserContent.height, 0.01),
                );
                await _activate(t, _key('hangar-reader-action'));
                phases.add(
                  _bounds(
                    t,
                    [
                      'hangar-reader-status',
                      'hangar-reader-cancel',
                      'hangar-reader-progress',
                      'hangar-browser-viewport',
                      'hangar-reader-live-results',
                    ],
                    viewport,
                    'reader-reading',
                  ),
                );
                expect(
                  t
                      .widget<HangarBrowserViewport>(
                        find.byType(HangarBrowserViewport),
                      )
                      .interactive,
                  isFalse,
                );
                expect(reader.preview.begins, 1);
                expect(reader.preview.observations, 0);
                if (locale == const Locale('zh', 'CN') && width == 540) {
                  await _capture(
                    t,
                    reader.frame,
                    '${suite.name}-$palette-reader-reading-cn',
                  );
                }
              } finally {
                await _releaseReader(t, reader);
              }

              final save = SaveFake()
                ..pending = Completer<LocalHangarSnapshot>();
              var saved = 0;
              final saveFrame = GlobalKey();
              await t.pumpWidget(
                _app(
                  _savePanel(save, () => saved++),
                  suite,
                  light,
                  locale,
                  saveFrame,
                ),
              );
              await _frames(t);
              phases.add(
                _bounds(
                  t,
                  [
                    'local-hangar-save-panel',
                    'local-hangar-confirm',
                    'local-hangar-save',
                  ],
                  viewport,
                  'save-ready',
                ),
              );
              await _check(t, 'local-hangar-confirm');
              await _activate(t, _key('local-hangar-save'));
              expect(save.writes, 1);
              expect(saved, 0);
              phases.add(
                _bounds(
                  t,
                  ['local-hangar-save-panel', 'local-hangar-save-progress'],
                  viewport,
                  'save-busy',
                ),
              );
              save.pending!.complete(
                const LocalHangarSnapshot(
                  revision: 5,
                  operationId: 'scan',
                  ships: [],
                ),
              );
              await _frames(t);
              expect(saved, 1);
              await t.pumpWidget(const SizedBox());
              await _frames(t);

              final review = ReviewPort();
              final removalFrame = GlobalKey();
              await t.pumpWidget(
                _app(
                  _savePanel(review, () => saved++, shipCount: 2),
                  suite,
                  light,
                  locale,
                  removalFrame,
                ),
              );
              await _frames(t);
              await _activate(t, _key('local-hangar-review-removals'));
              expect(find.byType(LocalHangarRemovalDialog), findsOneWidget);
              phases.add(
                _bounds(
                  t,
                  [
                    'hangar-removal-list',
                    'hangar-removal-cancel',
                    'hangar-removal-confirm',
                  ],
                  viewport,
                  'removal-ready',
                ),
              );
              await _check(t, 'hangar-remove-a');
              await _check(t, 'hangar-remove-c');
              phases.add(
                _bounds(
                  t,
                  ['hangar-removal-list', 'hangar-removal-confirm'],
                  viewport,
                  'removal-selected',
                ),
              );
              expect(review.writes, 0);
              if (locale == const Locale('zh', 'CN') && width == 540) {
                await _capture(
                  t,
                  removalFrame,
                  '${suite.name}-$palette-removal-cn',
                );
              }
              await _activate(t, _key('hangar-removal-cancel'));
              expect(find.byType(LocalHangarRemovalDialog), findsNothing);
              expect(review.writes, 0);
              expect(saved, 1);
              layouts.add({
                'suite': suite.name,
                'palette': palette,
                'locale': locale.toLanguageTag(),
                'width': width,
                'phases': phases,
              });
              await t.pumpWidget(const SizedBox());
              await _frames(t);
            },
          );
        }
      }

      testWidgets('3fg local touch/wait pixels $suite $palette', (t) async {
        size(t, const Size(540, 1100));
        final checks = <Map<String, Object?>>[];
        for (final keyboard in [false, true]) {
          final reader = await _reader(
            t,
            suite,
            light,
            const Locale('zh', 'CN'),
          );
          try {
            if (!keyboard) {
              checks.add(
                await _touch(t, reader.frame, 'hangar-reader-action', () {
                  expect(reader.preview.begins, 0);
                  expect(reader.browser.opens, 1);
                }),
              );
            }
            await _activate(
              t,
              _key('hangar-reader-action'),
              keyboard: keyboard,
            );
            expect(reader.preview.begins, 1);
            expect(reader.preview.observations, 0);
            checks.add({
              'source': keyboard ? 'keyboard' : 'pointer',
              ...await _waitPixels(
                t,
                reader.frame,
                'hangar-reader-progress',
                keyboard,
              ),
            });
            if (!keyboard) {
              final cancels = reader.preview.cancels;
              checks.add(
                await _touch(t, reader.frame, 'hangar-reader-cancel', () {
                  expect(reader.preview.cancels, cancels);
                  expect(reader.preview.observations, 0);
                  expect(reader.browser.locked, isTrue);
                }),
              );
            }
          } finally {
            await _releaseReader(t, reader);
          }

          final save = SaveFake()..pending = Completer<LocalHangarSnapshot>();
          final frame = GlobalKey();
          var saved = 0;
          await t.pumpWidget(
            _app(
              _savePanel(save, () => saved++),
              suite,
              light,
              const Locale('zh', 'CN'),
              frame,
            ),
          );
          await _frames(t);
          await _check(t, 'local-hangar-confirm');
          if (!keyboard) {
            checks.add(
              await _touch(t, frame, 'local-hangar-save', () {
                expect(save.writes, 0);
                expect(saved, 0);
              }),
            );
          }
          await _activate(t, _key('local-hangar-save'), keyboard: keyboard);
          expect(save.writes, 1);
          expect(saved, 0);
          checks.add({
            'source': keyboard ? 'keyboard' : 'pointer',
            ...await _waitPixels(
              t,
              frame,
              'local-hangar-save-progress',
              keyboard,
            ),
          });
          save.pending!.complete(
            const LocalHangarSnapshot(
              revision: 5,
              operationId: 'scan',
              ships: [],
            ),
          );
          await _frames(t);
          expect(saved, 1);
          await t.pumpWidget(const SizedBox());
          await _frames(t);
        }
        final review = ReviewPort();
        final frame = GlobalKey();
        await t.pumpWidget(
          _app(
            _savePanel(review, () {}, shipCount: 2),
            suite,
            light,
            const Locale('zh', 'CN'),
            frame,
          ),
        );
        await _frames(t);
        await _activate(t, _key('local-hangar-review-removals'));
        checks.add(
          await _touch(t, frame, 'hangar-removal-cancel', () {
            expect(find.byType(LocalHangarRemovalDialog), findsOneWidget);
            expect(review.writes, 0);
          }),
        );
        await _activate(t, _key('hangar-removal-cancel'));
        expect(review.writes, 0);
        feedback.add({
          'suite': suite.name,
          'palette': palette,
          'checks': checks,
        });
        await t.pumpWidget(const SizedBox());
        await _frames(t);
      });
    }
  }
}
