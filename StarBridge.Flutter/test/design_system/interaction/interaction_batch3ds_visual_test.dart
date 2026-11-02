import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_models.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_page_components.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import 'interaction_batch3do_test.dart' as fixture;
import 'interaction_batch3dp_visual_test.dart' show loadVisualFonts;

const _timeout = Timeout(Duration(seconds: 45));
const _frameKey = Key('3ds-visual-frame');
const _lowerChoice = Key('privacy-low-confidence-location');
const _width = 430.0;
const _height = 850.0;
final _output = visualOutputDir('interaction_motion_batch3ds_20261016');

class _Port implements SyncPrivacyPort {
  final original = InMemorySyncPrivacyAdapter.forReview();
  final pending = Completer<SyncPrivacyWriteResult>();
  int reads = 0;
  final updates = <(SyncPrivacySettingsValue, int)>[];

  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<SyncPrivacySnapshot> read() {
    reads++;
    return original.read();
  }

  @override
  Future<SyncPrivacyWriteResult> update(
    SyncPrivacySettingsValue settings, {
    required int expectedRevision,
  }) {
    updates.add((settings, expectedRevision));
    return pending.future;
  }

  @override
  Future<void> close() => original.close();
}

Future<void> _frames(WidgetTester t, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(
  Widget page,
  InteractionSuite suite, {
  required bool light,
  required double scale,
  bool reduce = false,
}) {
  final original = fixture.scopedApp(
    page,
    suite,
    light: light,
    reduce: reduce,
  ) as MaterialApp;
  return RepaintBoundary(
    key: _frameKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: original.locale,
      supportedLocales: original.supportedLocales,
      localizationsDelegates: original.localizationsDelegates,
      theme: original.theme,
      themeAnimationDuration: Duration.zero,
      home: original.home,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: original.builder!(context, child),
      ),
    ),
  );
}

Future<List<int>> _pixels(WidgetTester t) => t
    .runAsync(() async {
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(_frameKey),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List().toList();
      } finally {
        image.dispose();
      }
    })
    .then((value) => value!);

Future<void> _saveFrame(WidgetTester t, String name) async {
  final bytes = await _pixels(t);
  await t.runAsync(() async {
    final directory = Directory(_output);
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
  });
}

void _visible(WidgetTester t, Finder target) {
  expect(target, findsOneWidget);
  final rect = t.getRect(target);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(_width));
  expect(rect.bottom, lessThanOrEqualTo(_height));
  expect(rect.width, greaterThan(0));
  expect(rect.height, greaterThan(0));
}

ScrollPosition _position(WidgetTester t) => t
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('sync-privacy-content')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

StarBridgeSwitch _switch(WidgetTester t, Finder target) =>
    t.widget<StarBridgeSwitch>(
      find.ancestor(of: target, matching: find.byType(StarBridgeSwitch)).first,
    );

void main() {
  setUpAll(loadVisualFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final name = '${suite.name}-${light ? 'light' : 'dark'}-$scale';
        testWidgets(
          '$name lower settings scroll keeps pending and failure visible at logical 430x850',
          (t) async {
            // These are logical viewport/text-scale fixtures, not Windows DPI
            // or real-device accessibility acceptance.
            fixture.size(t, const Size(_width, _height));
            final port = _Port();
            final module = createSyncPrivacyModule(port);
            await module.initialize();
            final page = SyncPrivacyPage(module: module);
            Widget app({bool reduce = false}) =>
                _app(page, suite, light: light, scale: scale, reduce: reduce);
            try {
              await t.pumpWidget(app());
              await _frames(t);
              final lower = find.byKey(_lowerChoice);
              await t.ensureVisible(lower);
              await _frames(t);
              _visible(t, lower);
              expect(_switch(t, lower).value, isTrue);
              final saved = module.projection.value.settings;
              final beforeScroll = _position(t).pixels;
              expect(beforeScroll, greaterThan(0));
              expect(port.reads, 1);
              expect(port.updates, isEmpty);
              await _saveFrame(t, '$name-idle');

              // Do not re-align the scroll after the action. The user is editing
              // a lower setting, so pending and failure must be visible there.
              await t.tap(lower);
              await t.pump();
              await t.pump(const Duration(milliseconds: 100));
              expect(port.updates, hasLength(1));
              expect(port.updates.single.$2, 7);
              expect(
                port.updates.single.$1.social.hideLowConfidenceLocation,
                isFalse,
              );
              expect(module.projection.value.settings, same(saved));
              expect(
                module.projection.value.operation,
                SyncPrivacyOperation.saving,
              );
              expect(_switch(t, lower).value, isTrue);
              expect(_switch(t, lower).onChanged, isNull);
              expect(_position(t).pixels, closeTo(beforeScroll, 0.01));
              await _saveFrame(t, '$name-pending');
              _visible(t, find.byType(HelpSupportWaiting));
              expect(find.byType(SuiteProgressBar), findsOneWidget);

              await t.pumpWidget(app(reduce: true));
              await t.pump();
              await t.pump();
              expect(port.updates, hasLength(1));
              expect(
                module.projection.value.operation,
                SyncPrivacyOperation.saving,
              );
              expect(find.byType(SuiteProgressBar), findsNothing);
              _visible(t, find.byType(HelpSupportWaiting));
              final reducedPixels = await _pixels(t);
              await t.pump(const Duration(milliseconds: 300));
              expect(
                await _pixels(t),
                reducedPixels,
                reason: 'Live reduce stops the full pending frame, not just a progress label.',
              );

              port.pending.complete(
                const SyncPrivacyWriteResult.failed(
                  SyncPrivacyFailure.writeFailed,
                ),
              );
              await _frames(t);
              expect(module.projection.value.settings, same(saved));
              expect(
                module.projection.value.failure,
                SyncPrivacyFailure.writeFailed,
              );
              expect(_switch(t, lower).value, isTrue);
              expect(port.reads, 1);
              expect(port.updates, hasLength(1));
              expect(_position(t).pixels, closeTo(beforeScroll, 0.01));
              await _saveFrame(t, '$name-failed');
              _visible(t, find.byType(SyncPrivacyFailureBanner));
              expect(find.byType(HelpSupportWaiting), findsNothing);
              expect(t.takeException(), isNull);
            } finally {
              if (!port.pending.isCompleted) {
                port.pending.complete(
                  const SyncPrivacyWriteResult.failed(
                    SyncPrivacyFailure.writeFailed,
                  ),
                );
              }
              await t.pumpWidget(const SizedBox.shrink());
              await _frames(t, count: 2);
              module.dispose();
            }
          },
          timeout: _timeout,
          skip: !Platform.isWindows,
        );
      }
    }
  }
}
