import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/communities_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3m_test.dart' show keyPress;

final _review = visualOutputDir(
  'interaction_motion_batch3fv_20261017',
  legacySubdirectory: 'review',
);
const _refresh = Key('community-directory-refresh');
const _retry = Key('community-directory-retained-retry');
const _search = Key('community-directory-search');

class _Read {
  _Read(this.view, this.query, this.after, this.filters);
  final String view, query;
  final String? after, filters;
  final result = Completer<CommunityDirectory>();
}

class _Port implements CommunitiesPort {
  final events = StreamController<void>.broadcast(sync: true);
  final reads = <_Read>[];
  int writes = 0, closes = 0;
  bool _closed = false;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) {
    final request = _Read(view, query, after, filters);
    reads.add(request);
    return request.result.future;
  }

  @override
  Future<String> execute(String action, String targetRef) async {
    writes++;
    return 'accepted';
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    closes++;
    await events.close();
  }

  void complete(int index, {String name = 'Directory organization'}) {
    final request = reads[index];
    request.result.complete(
      CommunityDirectory(request.view, request.query, [
        CommunityCard(
          targetRef: 'org-target',
          organizationRef: 'org-one',
          name: name,
          memberCount: 12,
          description: 'Synthetic directory row',
          joinMode: 'direct',
          actions: const ['join'],
        ),
      ], totalCount: 1),
    );
  }
}

class _Probe {
  _Probe(
    this.suite, {
    this.light = false,
    this.large = false,
    this.openingSource = InteractionSource.pointer,
  }) {
    model = CommunitiesModule(port, now: () => DateTime.utc(2026, 10, 17));
  }
  final port = _Port();
  late final CommunitiesModule model;
  final capture = GlobalKey();
  final InteractionSource openingSource;
  InteractionSuite suite;
  bool light, large, reduce = false, visible = true;
  late StateSetter update;
  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, state) {
        update = state;
        final base = scopedApp(
          Builder(
            builder: (context) => starBridgeInitialReadViewport(
              context,
              source: openingSource,
              child: visible
                  ? CommunitiesPage(createPort: () => port, module: model)
                  : const Text('Closed'),
            ),
          ),
          suite,
          reduce: reduce,
          light: light,
        ) as MaterialApp;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
            child: base.builder!(context, child),
          ),
          home: base.home,
        );
      },
    ),
  );
}

Future<void> frames(WidgetTester t, [int count = 24]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

// ignore: library_private_types_in_public_api
Future<void> mount(WidgetTester t, _Probe p, {bool preload = true}) async {
  size(t, const Size(1000, 1100));
  if (preload) {
    final reading = p.model.refresh(newView: 'discover');
    p.port.complete(0);
    await reading;
  }
  await t.pumpWidget(p.app());
  await frames(t);
  expect(p.port.reads, hasLength(1));
}

Future<void> activate(WidgetTester t, Key key, String source) async {
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
  await frames(t);
}

Finder get waiting => find.byType(SocialReadActivity);
void waitState(
  WidgetTester t,
  // ignore: library_private_types_in_public_api
  _Probe p, {
  required bool animated,
  bool initial = false,
}) {
  if (initial && p.suite == InteractionSuite.standard) {
    final circle = t.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(circle.value, animated ? isNull : .5);
    return;
  }
  expect(waiting, findsOneWidget);
  final busy = find.descendant(
    of: waiting,
    matching: find.byType(SuiteBusyFrame),
  );
  expect(InteractionScope.of(t.element(busy)).reduceMotion, !animated);
}

// ignore: library_private_types_in_public_api
Future<void> clean(WidgetTester t, _Probe p) async {
  await t.pumpWidget(const SizedBox());
  p.model.dispose();
  await p.port.events.close();
  expect(t.takeException(), isNull);
}

Future<List<int>> pixels(
  WidgetTester t,
  // ignore: library_private_types_in_public_api
  _Probe p,
  Rect rect, {
  String? png,
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
      return [
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
}

int changed(List<int> a, List<int> b) {
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

void main() {
  setUpAll(loadFonts);
  testWidgets('3fv keyboard initial directory must not loop', (t) async {
    final p = _Probe(
      InteractionSuite.standard,
      openingSource: InteractionSource.keyboard,
    );
    try {
      await mount(t, p, preload: false);
      expect(
        t
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .value,
        isNotNull,
      );
      p.port.complete(0);
      await frames(t);
    } finally {
      await clean(t, p);
    }
  });

  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3fv $suite $source retained refresh failure and retry preserve rows and authority',
        (t) async {
          final semantics = t.ensureSemantics();
          final p = _Probe(suite);
          try {
            await mount(t, p);
            await activate(t, _refresh, source);
            waitState(t, p, animated: source == 'pointer');
            expect(find.text('Directory organization'), findsOneWidget);
            expect(p.port.reads, hasLength(2));
            expect(p.model.showDirectoryProgress, isTrue);
            expect(
              t
                  .getSemantics(find.byKey(_refresh))
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            p.port.reads[1].result.completeError(
              const CommunityFailure('readTransient'),
            );
            await frames(t);
            expect(waiting, findsNothing);
            expect(p.model.directory!.items.single.displayOnly, isTrue);
            expect(find.text('Directory organization'), findsOneWidget);
            expect(p.port.writes, 0);
            final retrySource = source == 'pointer' ? 'keyboard' : 'pointer';
            await activate(t, _retry, retrySource);
            waitState(t, p, animated: retrySource == 'pointer');
            p.port.complete(2);
            await frames(t);
            expect(p.model.directory!.items.single.displayOnly, isFalse);
            expect(p.port.reads, hasLength(3));
          } finally {
            await clean(t, p);
            semantics.dispose();
          }
        },
      );
    }

    for (final first in ['pointer', 'keyboard']) {
      testWidgets(
        '3fv $suite $first superseded search owns its new input and rejects old response',
        (t) async {
          final p = _Probe(suite);
          try {
            await mount(t, p);
            await activate(t, _refresh, first);
            final next = first == 'pointer' ? 'keyboard' : 'pointer';
            await t.enterText(find.byType(TextField).first, 'new query');
            await t.pump();
            await activate(t, _search, next);
            waitState(t, p, animated: next == 'pointer', initial: true);
            expect(p.port.reads, hasLength(3));
            expect(p.port.reads[2].query, 'new query');
            p.port.complete(1, name: 'Stale row');
            await frames(t);
            expect(find.text('Stale row'), findsNothing);
            expect(p.model.busy, isTrue);
            p.port.complete(2, name: 'Current row');
            await frames(t);
            expect(find.text('Current row'), findsOneWidget);
          } finally {
            await clean(t, p);
          }
        },
      );
    }

    testWidgets(
      '3fv $suite same-query force read receives a new wait identity',
      (t) async {
        final p = _Probe(suite);
        try {
          await mount(t, p);
          await activate(t, _refresh, 'pointer');
          waitState(t, p, animated: true);
          runStarBridgeSynchronousActivation(
            InteractionSource.keyboard,
            () => unawaited(p.model.refresh(force: true)),
          );
          await frames(t);
          waitState(t, p, animated: false);
          expect(p.port.reads, hasLength(3));
          p.port.complete(1, name: 'Old row');
          p.port.complete(2);
          await frames(t);
          expect(find.text('Old row'), findsNothing);
        } finally {
          await clean(t, p);
        }
      },
    );

    testWidgets(
      '3fv $suite unrelated joined read cannot relabel foreground directory phase',
      (t) async {
        final p = _Probe(suite);
        try {
          await mount(t, p);
          await activate(t, _refresh, 'pointer');
          final identity = t.widget(waiting).key;
          final joined = p.model.refreshJoined();
          expect(p.port.reads[2].view, 'mine');
          p.port.complete(2);
          await joined;
          await frames(t);
          expect(t.widget(waiting).key, identity);
          waitState(t, p, animated: true);
          p.port.complete(1);
          await frames(t);
        } finally {
          await clean(t, p);
        }
      },
    );

    testWidgets(
      '3fv $suite silent read has no foreground marker and page disposal does not own borrowed module',
      (t) async {
        final p = _Probe(suite);
        try {
          await mount(t, p);
          final task = p.model.refresh(silent: true);
          await frames(t);
          expect(waiting, findsNothing);
          expect(p.model.showDirectoryProgress, isFalse);
          expect(find.text('Directory organization'), findsOneWidget);
          p.update(() {
            p.visible = false;
          });
          await frames(t);
          expect(p.port.closes, 0);
          p.port.complete(1);
          await task;
          p.update(() {
            p.visible = true;
          });
          await frames(t);
          expect(p.port.reads, hasLength(2));
          expect(find.text('Directory organization'), findsOneWidget);
        } finally {
          await clean(t, p);
        }
      },
    );

    for (final light in [false, true]) {
      testWidgets(
        '3fv $suite light=$light initial and retained waits settle live reduce',
        (t) async {
          final p = _Probe(suite, light: light, large: true);
          try {
            await mount(t, p, preload: false);
            waitState(t, p, animated: true, initial: true);
            if (!light) {
              await pixels(
                t,
                p,
                const Rect.fromLTWH(0, 0, 1000, 1100),
                png: '${suite.name}-initial',
              );
            }
            p.update(() {
              p.reduce = true;
            });
            await t.pump();
            await t.pump();
            waitState(t, p, animated: false, initial: true);
            final initialMarker = suite == InteractionSuite.standard
                ? find.byType(CircularProgressIndicator)
                : waiting;
            final initialRect = t.getRect(initialMarker);
            final initialStopped = await pixels(t, p, initialRect);
            await frames(t, 38);
            final initialStaticPixels = changed(
              initialStopped,
              await pixels(t, p, initialRect),
            );
            expect(initialStaticPixels, 0);
            expect(p.port.reads, hasLength(1));
            p.update(() {
              p.reduce = false;
            });
            await t.pump();
            await t.pump();
            p.port.complete(0);
            await frames(t);
            await activate(t, _refresh, 'pointer');
            waitState(t, p, animated: true);
            final rect = t.getRect(waiting);
            final before = await pixels(
              t,
              p,
              rect,
              png: '${suite.name}-${light ? 'light' : 'dark'}',
            );
            await frames(t, 17);
            final moving = changed(before, await pixels(t, p, rect));
            expect(moving, greaterThan(0));
            p.update(() {
              p.reduce = true;
            });
            await t.pump();
            await t.pump();
            waitState(t, p, animated: false);
            final stopped = await pixels(t, p, rect);
            await frames(t, 38);
            final staticPixels = changed(stopped, await pixels(t, p, rect));
            expect(staticPixels, 0);
            expect(t.getRect(waiting), rect);
            await t.runAsync(
              () =>
                  File(
                    '$_review/${suite.name}-${light ? 'light' : 'dark'}.json',
                  ).writeAsString(
                    jsonEncode({
                      'movingPixels': moving,
                      'staticPixels': staticPixels,
                      'initialReducedPixels': initialStaticPixels,
                      'rect': [rect.left, rect.top, rect.width, rect.height],
                    }),
                  ),
            );
            p.port.complete(1);
            await frames(t);
          } finally {
            await clean(t, p);
          }
        },
      );
    }
  }
}
