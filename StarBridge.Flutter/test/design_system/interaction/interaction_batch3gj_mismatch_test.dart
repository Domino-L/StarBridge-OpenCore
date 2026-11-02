import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/handle_mismatch_module.dart';
import 'package:starbridge_flutter/app/runtime/handle_mismatch_flow.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/handle_mismatch_port.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/account/handle_mismatch_module_test.dart'
    show projection;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3gb_logs_presets_test.dart' show actTarget;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;

final class _Port implements HandleMismatchPort, LegacyHandleChangePort {
  final reads = <(int, Completer<HandleCheckResult>)>[];
  final writes = <(int, String, Completer<void>)>[];
  final cancels = <(int, String)>[];
  @override
  Future<HandleCheckResult> check(int generation) {
    final gate = Completer<HandleCheckResult>();
    reads.add((generation, gate));
    return gate.future;
  }

  @override
  Future<void> confirm(int generation, String confirmationId) {
    final gate = Completer<void>();
    writes.add((generation, confirmationId, gate));
    return gate.future;
  }

  @override
  Future<void> cancel(int generation, String confirmationId) async {
    cancels.add((generation, confirmationId));
  }

  @override
  Future<HandleNotificationReceipt?> notifyBackground(int generation) async =>
      null;
}

Finder target(String key) => find
    .ancestor(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(StarBridgeActionButton),
    )
    .first;
final _activity = find.byType(SocialReadActivity);

class _Probe {
  _Probe(this.suite, {this.automatic = false}) {
    module = HandleMismatchModule(
      account: account,
      gameLog: null,
      port: port,
      refresh: () async {
        refreshes++;
      },
    );
  }
  final InteractionSuite suite;
  final bool automatic;
  final account = ValueNotifier(projection());
  final port = _Port();
  final queue = StartupPromptQueue(
    quietPeriod: const Duration(milliseconds: 1),
  );
  final capture = GlobalKey();
  final nav = GlobalKey<NavigatorState>();
  late final HandleMismatchModule module;
  late final HandleMismatchFlow flow;
  late StateSetter update;
  SemanticsHandle? semantics;
  bool reduce = false, light = false;
  double scale = 1;
  int refreshes = 0, accountOpens = 0;

  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, set) {
        update = set;
        final base = scopedApp(
          Center(
            child: StarBridgeActionButton(
              controlKey: const Key('open-mismatch'),
              onActivate: (_) => unawaited(flow.open()),
              child: const Text('Open identity notice'),
            ),
          ),
          suite,
          reduce: reduce,
          light: light,
        ) as MaterialApp;
        return MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [queue],
          debugShowCheckedModeBanner: false,
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: base.builder!(context, child),
          ),
          home: base.home,
        );
      },
    ),
  );

  Future<void> mount(WidgetTester t, {String? source = 'pointer'}) async {
    semantics = t.ensureSemantics();
    size(t, const Size(1200, 1000));
    await t.pumpWidget(app());
    flow = HandleMismatchFlow(
      module: module,
      queue: queue,
      ready: () => automatic,
      onOpenAccount: () => accountOpens++,
    );
    await frames(t);
    if (source != null && !automatic) {
      await actTarget(t, target('open-mismatch'), source);
    }
    await frames(t);
  }

  StarBridgeDialogRoute<bool> route(WidgetTester t) =>
      ModalRoute.of(t.element(find.byKey(const Key('handle-mismatch-dialog'))))!
          as StarBridgeDialogRoute<bool>;

  void ready() => port.reads.last.$2.complete(
    HandleCheckResult(
      HandleCheckState.ready,
      'Pilot_Alpha',
      'Pilot-Alpha',
      confirmationId: 'a' * 32,
    ),
  );

  Future<void> clean(WidgetTester t) async {
    semantics?.dispose();
    flow.dispose();
    module.dispose();
    await t.pumpWidget(const SizedBox());
    for (final read in port.reads) {
      if (!read.$2.isCompleted) {
        read.$2.complete(
          const HandleCheckResult(
            HandleCheckState.unknown,
            'Pilot_Alpha',
            'Pilot-Alpha',
          ),
        );
      }
    }
    for (final write in port.writes) {
      if (!write.$3.isCompleted) write.$3.complete();
    }
    queue.dispose();
    account.dispose();
    await frames(t);
    expect(t.takeException(), isNull);
  }
}

void waiting(WidgetTester t, {required bool animate}) {
  expect(_activity, findsOneWidget);
  final frame = find.descendant(
    of: _activity,
    matching: find.byType(SuiteBusyFrame),
  );
  expect(InteractionScope.of(t.element(frame)).reduceMotion, !animate);
  expect(t.getSize(_activity).height, 2);
}

Future<List<int>> pixels(
  WidgetTester t,
  // ignore: library_private_types_in_public_api
  _Probe p, {
  bool save = false,
}) async => (await t.runAsync(() async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(p.capture));
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    if (save) {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await (await File(
        '${visualOutputDir('interaction_motion_batch3gj_20261017', legacySubdirectory: 'review')}/${p.suite.name}.png',
      ).create(recursive: true)).writeAsBytes(png.buffer.asUint8List());
    }
    final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    final rect = t.getRect(_activity);
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
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('3gj $suite $source check / confirm / failure / retry', (
        t,
      ) async {
        final p = _Probe(suite);
        try {
          await p.mount(t, source: source);
          expect(p.route(t).instant, source != 'pointer');
          await actTarget(t, target('handle-mismatch-recheck'), source);
          expect(p.port.reads.single.$1, 7);
          waiting(t, animate: source == 'pointer');
          for (final key in [
            'handle-mismatch-recheck',
            'handle-mismatch-later',
            'handle-mismatch-account',
          ]) {
            expect(
              t.widget<StarBridgeActionButton>(target(key)).onActivate,
              isNull,
            );
          }
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          expect(
            find.byKey(const Key('handle-mismatch-dialog')),
            findsOneWidget,
          );
          expect(p.port.writes, isEmpty);
          p.ready();
          await frames(t);
          expect(_activity, findsNothing);
          expect(p.module.canConfirm, isTrue);
          await actTarget(t, target('handle-mismatch-confirm'), source);
          expect(p.port.writes.single.$1, 7);
          expect(p.port.writes.single.$2, 'a' * 32);
          expect(p.module.checkState, HandleCheckState.outcomeUnknown);
          waiting(t, animate: source == 'pointer');
          p.port.writes.single.$3.completeError(
            const FormatException('synthetic uncertain outcome'),
          );
          await frames(t);
          expect(_activity, findsNothing);
          expect(p.module.failed, isTrue);
          expect(p.module.notice, isNotNull);
          expect(p.module.canConfirm, isFalse);
          expect(
            t
                .widget<StarBridgeActionButton>(
                  target('handle-mismatch-confirm'),
                )
                .onActivate,
            isNull,
          );
          await actTarget(t, target('handle-mismatch-recheck'), source);
          expect(p.port.reads, hasLength(2));
          expect(p.port.writes, hasLength(1));
          p.ready();
          await frames(t);
          await actTarget(t, target('handle-mismatch-later'), source);
          expect(p.port.cancels, [(7, 'a' * 32)]);
          expect(p.module.notice, isNotNull);
          expect(p.module.canConfirm, isFalse);
          expect(p.accountOpens, 0);
        } finally {
          await p.clean(t);
        }
      });

      for (final close in ['later', 'account']) {
        testWidgets('3gj $suite $source $close cancels prepared ticket only', (
          t,
        ) async {
          final p = _Probe(suite);
          try {
            await p.mount(t);
            await actTarget(t, target('handle-mismatch-recheck'), 'pointer');
            p.ready();
            await frames(t);
            final route = p.route(t);
            await actTarget(t, target('handle-mismatch-$close'), source);
            expect(
              find.byKey(const Key('handle-mismatch-dialog')),
              findsNothing,
            );
            expect(p.port.writes, isEmpty);
            expect(p.port.cancels, [(7, 'a' * 32)]);
            expect(p.accountOpens, close == 'account' ? 1 : 0);
            expect(p.module.notice, isNotNull);
            if (source != 'pointer') {
              expect(route.animation!.isDismissed, isTrue);
            }
          } finally {
            await p.clean(t);
          }
        });
      }
    }

    testWidgets('3gj $suite late check cannot affect a replacement identity', (
      t,
    ) async {
      final p = _Probe(suite);
      try {
        await p.mount(t);
        await actTarget(t, target('handle-mismatch-recheck'), 'pointer');
        p.account.value = projection(generation: 8, detected: 'Other-Pilot');
        await frames(t);
        expect(find.byKey(const Key('handle-mismatch-dialog')), findsNothing);
        p.ready();
        await frames(t);
        expect(p.refreshes, 0);
        expect(p.module.notice!.generation, 8);
        expect(p.module.failed, isFalse);
        expect(p.port.writes, isEmpty);
        expect(p.accountOpens, 0);
      } finally {
        await p.clean(t);
      }
    });

    testWidgets(
      '3gj $suite write acknowledgment does not clear authority evidence',
      (t) async {
        final p = _Probe(suite);
        try {
          await p.mount(t);
          await actTarget(t, target('handle-mismatch-recheck'), 'pointer');
          p.ready();
          await frames(t);
          await actTarget(t, target('handle-mismatch-confirm'), 'pointer');
          p.port.writes.single.$3.complete();
          await frames(t);
          expect(p.refreshes, 2);
          expect(p.module.notice, isNotNull);
          expect(
            find.byKey(const Key('handle-mismatch-dialog')),
            findsOneWidget,
          );
          expect(_activity, findsNothing);
          p.account.value = projection(state: AccountIdentityState.match);
          await frames(t);
          expect(find.byKey(const Key('handle-mismatch-dialog')), findsNothing);
          expect(p.module.notice, isNull);
          expect(p.port.writes, hasLength(1));
        } finally {
          await p.clean(t);
        }
      },
    );

    testWidgets(
      '3gj $suite externally started check is static and unknown open is instant',
      (t) async {
        final p = _Probe(suite);
        try {
          await p.mount(t, source: null);
          final check = p.module.recheck();
          unawaited(p.flow.open());
          await frames(t);
          expect(p.route(t).instant, isTrue);
          waiting(t, animate: false);
          p.ready();
          await check;
          await frames(t);
          expect(_activity, findsNothing);
        } finally {
          await p.clean(t);
        }
      },
    );

    testWidgets('3gj $suite queue automatic opening keeps its own lifecycle', (
      t,
    ) async {
      final p = _Probe(suite, automatic: true);
      try {
        await p.mount(t);
        expect(p.route(t).instant, isFalse);
        expect(p.port.reads, isEmpty);
        await actTarget(t, target('handle-mismatch-later'), 'pointer');
        await frames(t);
        expect(find.byKey(const Key('handle-mismatch-dialog')), findsNothing);
        expect(p.module.notice, isNotNull);
        expect(p.port.writes, isEmpty);
      } finally {
        await p.clean(t);
      }
    });

    testWidgets('3gj $suite live reduce and theme / scaled review', (t) async {
      final p = _Probe(suite)
        ..scale = 1.5
        ..light =
            suite == InteractionSuite.rail || suite == InteractionSuite.glow;
      try {
        await p.mount(t);
        await actTarget(t, target('handle-mismatch-recheck'), 'pointer');
        waiting(t, animate: true);
        final rect = t.getRect(_activity);
        final moving = await pixels(t, p, save: true);
        await frames(t, 13);
        expect(changed(moving, await pixels(t, p)), greaterThan(0));
        p.update(() {
          p.reduce = true;
          p.light = !p.light;
        });
        await t.pump();
        await t.pump();
        waiting(t, animate: false);
        expect(t.getRect(_activity), rect);
        final stopped = await pixels(t, p);
        await frames(t, 38);
        expect(changed(stopped, await pixels(t, p)), 0);
        p.ready();
        await frames(t);
        expect(_activity, findsNothing);
      } finally {
        await p.clean(t);
      }
    });
  }
}
