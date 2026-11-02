import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/test_build_notice_flow.dart';
import 'package:starbridge_flutter/app/runtime/test_build_notice_copy.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/settings/client_license.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../app/test_build_notice_flow_test.dart'
    show Harness, readTermsAndCheck;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3gb_logs_presets_test.dart' show actTarget;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;

final _review =
    Platform.environment['STARBRIDGE_TERMS_REVIEW_ROOT'] ??
    visualOutputDir(
      'interaction_motion_batch3gh_20261017',
      legacySubdirectory: 'review',
    );
final _marker = find.byKey(const Key('test-build-accept-activity'));

class _Probe {
  _Probe(this.suite);
  final InteractionSuite suite;
  final capture = GlobalKey();
  late StateSetter update;
  bool reduce = false, light = false;
  int writes = 0, licenseReads = 0;
  double scale = 1;
  Completer<bool> pending = Completer<bool>();
  final results = <bool?>[];
  SemanticsHandle? semantics;
  StarBridgeDialogRoute<bool>? route;

  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, set) {
        update = set;
        return scopedApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Center(
                child: StarBridgeActionButton(
                  child: const Text('open'),
                  onActivate: (source) async {
                    results.add(
                      await showStarBridgeDialog<bool>(
                        context,
                        source: source,
                        barrierDismissible: false,
                        onRouteCreated: (r) => route = r,
                        builder: (dialogContext) => MediaQuery(
                          data: MediaQuery.of(dialogContext)
                              .copyWith(textScaler: TextScaler.linear(scale)),
                          child: TestBuildNoticeDialog(
                            acknowledge: () {
                              writes++;
                              return pending.future;
                            },
                            readLicense: () async {
                              licenseReads++;
                              return const ClientLicenseDocument(
                                ClientLicenseState.ready,
                                'Synthetic full license for interaction regression.',
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          suite,
          reduce: reduce,
          light: light,
        );
      },
    ),
  );
  Future<void> mount(WidgetTester t) async {
    semantics = t.ensureSemantics();
    size(t, const Size(1200, 1000));
    await t.pumpWidget(app());
    await frames(t);
    await t.tap(find.text('open'));
    await frames(t);
  }

  Future<void> accept(WidgetTester t, String source) async {
    await readTermsAndCheck(t);
    final button = find
        .ancestor(
          of: find.byKey(const Key('test-build-accept')),
          matching: find.byType(StarBridgeActionButton),
        )
        .first;
    await actTarget(t, button, source);
    await frames(t);
  }

  Future<void> clean(WidgetTester t) async {
    semantics?.dispose();
    await t.pumpWidget(const SizedBox());
    if (!pending.isCompleted) pending.complete(false);
    await frames(t);
    expect(t.takeException(), isNull);
  }
}

void waitMarker(WidgetTester t, {required bool animated}) {
  expect(_marker, findsOneWidget);
  expect(t.widget(_marker), isA<SocialReadActivity>());
  final busy = find.descendant(
    of: _marker,
    matching: find.byType(SuiteBusyFrame),
  );
  expect(InteractionScope.of(t.element(busy)).reduceMotion, !animated);
}

Future<List<int>> _pixels(
  WidgetTester t,
  _Probe p, {
  bool save = false,
}) async => (await t.runAsync(() async {
  final boundary =
      p.capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    if (save) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_review).create(recursive: true);
      await File('$_review/${p.suite.name}-notice.png')
          .writeAsBytes(png!.buffer.asUint8List());
    }
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rect = t.getRect(_marker);
    final raw = bytes!.buffer.asUint8List();
    return <int>[
      for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++)
        ...raw.sublist(
          (y * image.width + rect.left.ceil()) * 4,
          (y * image.width + rect.right.floor()) * 4,
        ),
    ];
  } finally {
    image.dispose();
  }
}))!;

void main() {
  setUpAll(loadFonts);
  for (final light in [false, true]) {
    testWidgets('terms precondition initial page review light=$light', (
      t,
    ) async {
      final p = _Probe(InteractionSuite.standard)..light = light;
      await p.mount(t);
      expect(p.licenseReads, 1);
      expect(p.writes, 0);
      expect(
        t
            .widget<StarBridgeCheckboxTile>(
              find.byKey(const Key('usage-terms-consent')),
            )
            .onChanged,
        isNull,
      );
      final review = Platform.environment['STARBRIDGE_TERMS_REVIEW_ROOT'];
      if (review != null) {
        await t.runAsync(() async {
          final boundary =
              p.capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(review).create(recursive: true);
            await File('$review/terms-initial-${light ? 'light' : 'dark'}.png')
                .writeAsBytes(png!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      await p.clean(t);
    });
  }
  testWidgets('3gh real startup flow owns shared route', (t) async {
    final h = Harness();
    await h.mount(t);
    expect(
      ModalRoute.of(t.element(find.byKey(const Key('test-build-notice')))),
      isA<StarBridgeDialogRoute<bool>>(),
    );
    expect(h.accepts, 0);
    await h.close(t);
  });
  for (final suite in InteractionSuite.values) {
    testWidgets('3gh $suite pending acknowledgement blocks exit and Esc', (
      t,
    ) async {
      final p = _Probe(suite);
      await p.mount(t);
      await p.accept(t, 'pointer');
      for (final key in ['test-build-exit', 'test-build-accept']) {
        final node = t.getSemantics(find.byKey(Key(key)));
        expect(
          node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isFalse,
        );
      }
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await frames(t);
      expect(p.route!.isActive, isTrue);
      expect(p.results, isEmpty);
      expect(p.writes, 1);
      await p.clean(t);
    });
    testWidgets('3gh $suite thrown acknowledgement stays gated', (t) async {
      final p = _Probe(suite)..reduce = true;
      await p.mount(t);
      await p.accept(t, 'keyboard');
      waitMarker(t, animated: false);
      p.pending.completeError(StateError('synthetic failure'));
      await frames(t);
      expect(_marker, findsNothing);
      expect(p.results, isEmpty);
      expect(find.textContaining('暂时无法继续'), findsOneWidget);
      expect(p.writes, 1);
      await p.clean(t);
    });
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('3gh $suite $source held receipt retains gated dialog', (
        t,
      ) async {
        final p = _Probe(suite);
        await p.mount(t);
        expect(p.writes, 0);
        await p.accept(t, source);
        waitMarker(t, animated: source == 'pointer');
        expect(p.writes, 1);
        expect(p.results, isEmpty);
        expect(p.licenseReads, 1);
        p.pending.complete(true);
        await t.pump();
        await t.pump();
        if (source != 'pointer') expect(p.route!.isActive, isFalse);
        await frames(t);
        expect(p.results, [true]);
        expect(_marker, findsNothing);
        await p.clean(t);
      });
    }
    testWidgets('3gh $suite rejection stays and explicit retry succeeds', (
      t,
    ) async {
      final p = _Probe(suite);
      await p.mount(t);
      await p.accept(t, 'pointer');
      p.pending.complete(false);
      await frames(t);
      expect(_marker, findsNothing);
      expect(p.results, isEmpty);
      expect(find.textContaining('暂时无法继续'), findsOneWidget);
      p.pending = Completer<bool>();
      await p.accept(t, 'keyboard');
      waitMarker(t, animated: false);
      expect(p.writes, 2);
      await p.clean(t);
    });
    testWidgets('3gh $suite exit does not acknowledge', (t) async {
      final p = _Probe(suite);
      await p.mount(t);
      await actTarget(
        t,
        find.widgetWithText(StarBridgeActionButton, '不同意并退出'),
        'keyboard',
      );
      await frames(t);
      expect(p.writes, 0);
      expect(p.results, [false]);
      await p.clean(t);
    });
    testWidgets('3gh $suite notice review and live reduce', (t) async {
      final p = _Probe(suite)
        ..scale = 1.5
        ..light =
            suite == InteractionSuite.rail || suite == InteractionSuite.glow;
      await p.mount(t);
      await p.accept(t, 'pointer');
      waitMarker(t, animated: true);
      final a = await _pixels(t, p, save: true);
      await frames(t, 13);
      expect(changed(a, await _pixels(t, p)), greaterThan(0));
      final rect = t.getRect(_marker);
      final body = find.text(testBuildNoticeBody(const Locale('zh', 'CN')));
      expect(body, findsOneWidget);
      expect(
        rect.bottom,
        lessThanOrEqualTo(
          t.getRect(find.byKey(const Key('test-build-accept'))).top,
        ),
      );
      p.update(() => p.reduce = true);
      await frames(t, 2);
      waitMarker(t, animated: false);
      final b = await _pixels(t, p);
      await frames(t, 38);
      expect(changed(b, await _pixels(t, p)), 0);
      expect(t.getRect(_marker), rect);
      await p.clean(t);
    });
  }
}
