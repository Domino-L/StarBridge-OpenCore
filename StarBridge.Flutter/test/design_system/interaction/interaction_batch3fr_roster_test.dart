import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_compact_select.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_roster_editor.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3m_test.dart' show keyPress;
import 'interaction_batch3aa_test.dart' show open, select;

const _open = Key('overlay-roster-open');
const _refresh = Key('overlay-roster-refresh');
const _close = Key('overlay-roster-close');
const _waiting = Key('overlay-roster-waiting');
final _review = visualOutputDir(
  'interaction_motion_batch3fr_20261017',
  legacySubdirectory: 'review',
);

class _Request {
  _Request(this.revision, this.key, this.mode);
  final int? revision;
  final String? key, mode;
  final result = Completer<Map<String, Object?>>();
}

class _Port implements OverlayRosterPort {
  final events = StreamController<void>.broadcast(sync: true);
  final requests = <_Request>[];
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<Map<String, Object?>> request([
    int? revision,
    String? key,
    String? mode,
  ]) {
    final request = _Request(revision, key, mode);
    requests.add(request);
    return request.result.future;
  }

  void complete(
    int index, {
    int revision = 7,
    String mode = 'auto',
    String name = 'Member A',
    bool empty = false,
  }) {
    requests[index].result.complete({
      'schemaVersion': 1,
      'revision': revision,
      'rows': empty
          ? []
          : [
              {'key': 'a', 'name': name, 'mode': mode},
            ],
    });
  }
}

class _Probe {
  _Probe(this.suite, {this.light = false, this.scale = 1, this.narrow = false});
  InteractionSuite suite;
  bool light, reduce = false, systemReduce = false;
  final double scale;
  final bool narrow;
  final port = _Port();
  final capture = GlobalKey();
  late StateSetter update;
  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, state) {
        update = state;
        final base = scopedApp(
          Center(child: OverlayRosterButton(port: port)),
          suite,
          reduce: reduce,
          light: light,
        ) as MaterialApp;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: const Locale('en'),
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: systemReduce,
            ),
            child: base.builder!(context, child),
          ),
          home: base.home,
        );
      },
    ),
  );
}

Future<void> _frames(WidgetTester t, [int count = 30]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _activate(WidgetTester t, Key key, String source) async {
  final target = find.byKey(key);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    await keyPress(t, target);
  } else {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  }
  await t.pump();
  await _frames(t);
}

Future<void> _mount(WidgetTester t, _Probe p, String source) async {
  size(t, Size(p.narrow ? 540 : 1000, 1000));
  await t.pumpWidget(p.app());
  await _frames(t);
  await _activate(t, _open, source);
  expect(p.port.requests, hasLength(1));
}

Future<void> _pick(WidgetTester t, String source) async {
  final config = t.widget<StarBridgeCompactSelect<String>>(
    find.byType(StarBridgeCompactSelect<String>),
  );
  final target = find.byKey(config.controlKey!);
  if (source == 'reader') {
    final node = t.getSemantics(target);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  } else {
    await open(t, config.controlKey!, source);
  }
  await _frames(t);
  final option = find.byKey(ValueKey<Object>((config.identity, 'pin')));
  if (source == 'reader') {
    final node = t.getSemantics(option);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  } else {
    await select(t, config.identity, 'pin', source);
  }
  await t.pump();
  await _frames(t);
}

Future<List<int>> _pixels(
  WidgetTester t,
  _Probe p, {
  String? png,
  Rect? region,
}) async {
  final boundary =
      p.capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await t.runAsync(() async {
    final image = await boundary.toImage();
    try {
      if (png != null) {
        await Directory(_review).create(recursive: true);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_review/$png.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      }
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      if (region == null) return raw.toList();
      return [
        for (var y = region.top.ceil(); y < region.bottom.floor(); y++)
          ...raw.sublist(
            (y * image.width + region.left.ceil()) * 4,
            (y * image.width + region.right.floor()) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

int _changed(List<int> a, List<int> b) {
  expect(a.length, b.length);
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      count++;
    }
  }
  return count;
}

Future<void> _waitState(
  WidgetTester t,
  _Probe p, {
  required bool animates,
}) async {
  expect(find.byKey(_waiting), findsOneWidget);
  final busy = find.descendant(
    of: find.byKey(_waiting),
    matching: find.byType(SuiteBusyFrame),
  );
  if (p.suite == InteractionSuite.standard) {
    final progress = t.widget<CircularProgressIndicator>(
      find.descendant(
        of: find.byKey(_waiting),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    expect(progress.value, animates ? isNull : .5);
  } else {
    expect(busy, findsOneWidget);
    expect(InteractionScope.of(t.element(busy)).reduceMotion, !animates);
  }
}

void main() {
  setUpAll(loadFonts);

  testWidgets('3fr admitted roster wait uses shared recipe', (t) async {
    final p = _Probe(InteractionSuite.rail);
    await _mount(t, p, 'keyboard');
    expect(find.byType(SocialReadActivity), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    p.port.complete(0);
    await t.pump();
    await p.port.events.close();
  });

  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3fr $suite $source initial refresh and mode wait preserve request phases',
        (t) async {
          final semantics = t.ensureSemantics();
          final p = _Probe(suite);
          try {
            await _mount(t, p, source);
            await _waitState(t, p, animates: source == 'pointer');
            expect(p.port.requests.single.revision, isNull);
            // Busy refresh stays disabled; a second activation must not add a read.
            final refreshNode = t.getSemantics(find.byKey(_refresh));
            expect(
              refreshNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            await t.tap(find.byKey(_refresh), warnIfMissed: false);
            await t.pump();
            expect(p.port.requests, hasLength(1));
            p.port.complete(0);
            await _frames(t);
            expect(find.text('Member A'), findsOneWidget);
            await _activate(t, _refresh, source);
            await _waitState(t, p, animates: source == 'pointer');
            expect(p.port.requests, hasLength(2));
            expect(p.port.requests[1].revision, isNull);
            p.port.complete(1);
            await _frames(t);
            await _pick(t, source);
            await _waitState(t, p, animates: source == 'pointer');
            expect(p.port.requests, hasLength(3));
            final write = p.port.requests[2];
            expect((write.revision, write.key, write.mode), (7, 'a', 'pin'));
            expect(find.text('Member A'), findsNothing);
            write.result.completeError(StateError('refused'));
            await _frames(t);
            expect(
              find.text('Could not read or save. Refresh to retry.'),
              findsOneWidget,
            );
            expect(find.byKey(_waiting), findsNothing);
            await _activate(t, _refresh, source);
            p.port.complete(3, revision: 8);
            await _frames(t);
            expect(
              t
                  .widget<StarBridgeCompactSelect<String>>(
                    find.byType(StarBridgeCompactSelect<String>),
                  )
                  .value,
              'auto',
            );
            await _activate(t, _close, source);
            expect(find.text('Member A'), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await p.port.events.close();
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '3fr $suite background invalidation supersedes held write and stream close ignores late read',
      (t) async {
        final p = _Probe(suite);
        await _mount(t, p, 'pointer');
        p.port.complete(0);
        await _frames(t);
        await _pick(t, 'pointer');
        expect(p.port.requests, hasLength(2));
        p.port.events.add(null);
        await _frames(t);
        expect(p.port.requests, hasLength(3));
        await _waitState(t, p, animates: false);
        p.port.complete(1, name: 'Stale member', mode: 'pin');
        await _frames(t);
        expect(find.text('Stale member'), findsNothing);
        expect(find.byKey(_waiting), findsOneWidget);
        await p.port.events.close();
        await _frames(t);
        expect(
          find.text('Could not read or save. Refresh to retry.'),
          findsOneWidget,
        );
        p.port.complete(2, name: 'Late member');
        await _frames(t);
        expect(find.text('Late member'), findsNothing);
        expect(p.port.requests, hasLength(3));
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '3fr $suite close during held read detaches events and ignores late failure',
      (t) async {
        final p = _Probe(suite);
        await _mount(t, p, 'keyboard');
        await _activate(t, _close, 'keyboard');
        expect(p.port.events.hasListener, isFalse);
        p.port.requests.single.result.completeError(StateError('late'));
        p.port.events.add(null);
        await _frames(t);
        expect(p.port.requests, hasLength(1));
        expect(find.byType(AlertDialog), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await p.port.events.close();
      },
    );

    testWidgets(
      '3fr $suite initial read failure retries to empty without update',
      (t) async {
        final p = _Probe(suite);
        await _mount(t, p, 'pointer');
        p.port.requests.single.result.completeError(
          StateError('read unavailable'),
        );
        await _frames(t);
        expect(
          find.text('Could not read or save. Refresh to retry.'),
          findsOneWidget,
        );
        await _activate(t, _refresh, 'keyboard');
        await _waitState(t, p, animates: false);
        p.port.complete(1, empty: true);
        await _frames(t);
        expect(
          find.text('No members are available in this scene.'),
          findsOneWidget,
        );
        expect(p.port.requests.every((r) => r.revision == null), isTrue);
        expect(p.port.requests, hasLength(2));
        await t.pumpWidget(const SizedBox());
        await p.port.events.close();
      },
    );

    testWidgets(
      '3fr $suite keyboard phase stays static across live styles and system reduce',
      (t) async {
        final p = _Probe(suite);
        await _mount(t, p, 'pointer');
        p.port.complete(0);
        await _frames(t);
        await _activate(t, _refresh, 'keyboard');
        for (final next in InteractionSuite.values) {
          p.update(() {
            p.suite = next;
            p.systemReduce = true;
          });
          await t.pump();
          await t.pump();
          await _waitState(t, p, animates: false);
          p.update(() {
            p.systemReduce = false;
          });
          await t.pump();
          await t.pump();
          await _waitState(t, p, animates: false);
          final rect = t.getRect(find.byKey(_waiting));
          final before = await _pixels(t, p, region: rect);
          await _frames(t, 38);
          expect(_changed(before, await _pixels(t, p, region: rect)), 0);
        }
        expect(p.port.requests, hasLength(2));
        p.port.complete(1);
        await _frames(t);
        await t.pumpWidget(const SizedBox());
        await p.port.events.close();
        expect(t.takeException(), isNull);
      },
    );

    for (final light in [false, true]) {
      testWidgets(
        '3fr $suite light=$light wait pixels and live reduce with stable slot',
        (t) async {
          final p = _Probe(suite, light: light, scale: 1.5, narrow: light);
          final semantics = t.ensureSemantics();
          try {
            await _mount(t, p, 'pointer');
            final rect = t.getRect(find.byKey(_waiting));
            final before = await _pixels(
              t,
              p,
              region: rect,
              png: '${suite.name}-${light ? 'light' : 'dark'}-waiting',
            );
            await _frames(t, 17);
            final moving = await _pixels(t, p, region: rect);
            final changed = _changed(before, moving);
            expect(changed, greaterThan(0));
            p.update(() {
              p.reduce = true;
            });
            await t.pump();
            await t.pump();
            await _waitState(t, p, animates: false);
            final frozen = await _pixels(t, p, region: rect);
            await _frames(t, 38);
            final staticChange = _changed(
              frozen,
              await _pixels(t, p, region: rect),
            );
            expect(staticChange, 0);
            expect(t.getRect(find.byKey(_waiting)), rect);
            expect(p.port.requests, hasLength(1));
            p.update(() {
              p.reduce = false;
            });
            await t.pump();
            await t.pump();
            await _waitState(t, p, animates: true);
            final label = t.getSemantics(find.bySemanticsLabel('Please wait…'));
            expect(label.getSemanticsData().value, isEmpty);
            await t.runAsync(() async {
              await File(
                '$_review/${suite.name}-${light ? 'light' : 'dark'}-pixels.json',
              ).writeAsString(
                jsonEncode({
                  'movingPixels': changed,
                  'reducedPixelsAfterTwoFramesOver608ms': staticChange,
                  'rect': [rect.left, rect.top, rect.width, rect.height],
                }),
              );
            });
            p.port.complete(0);
            await _frames(t);
            expect(find.text('Member A'), findsOneWidget);
            expect(find.byKey(_waiting), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await p.port.events.close();
            semantics.dispose();
          }
        },
      );
    }
  }
}
