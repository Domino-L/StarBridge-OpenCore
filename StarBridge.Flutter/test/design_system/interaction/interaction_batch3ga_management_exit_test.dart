import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_admissions_port.dart';
import 'package:starbridge_flutter/features/communities/community_management_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_exit_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_exit_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/communities/community_management_dialog_test.dart'
    show ManagementTestPort;
import '../../features/communities/community_ownership_exit_test.dart'
    show ExitFake, exitPayload;
import '../../features/communities/community_workspace_test.dart'
    show WorkspaceTestPort, workspacePayload;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3fw_workspace_test.dart' show activate;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;
import 'interaction_batch3am_test.dart' as governance show action;

final _review = visualOutputDir(
  'interaction_motion_batch3ga_20261017',
  legacySubdirectory: 'review',
);
const _target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _member = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class _Management extends ManagementTestPort {
  final reads = <(String, String, int)>[];
  Completer<CommunityAdmissionsPage>? reading;
  bool fail = false;
  @override
  Future<CommunityAdmissionsPage> readAdmissions(
    String target,
    String section,
    int offset,
  ) {
    reads.add((target, section, offset));
    if (reading != null) return reading!.future;
    if (fail) return Future.error(const CommunityFailure('unavailable'));
    return super.readAdmissions(target, section, offset);
  }

  Future<void> readDone({bool error = false}) async {
    if (error) {
      reading!.completeError(const CommunityFailure('unavailable'));
      return;
    }
    final last = reads.last;
    reading!.complete(await super.readAdmissions(last.$1, last.$2, last.$3));
  }
}

CommunityWorkspace workspace(String query) {
  final data = workspacePayload(query: query);
  (data['access'] as Map)['isOwner'] = true;
  ((data['members'] as List).single as Map)['isSelf'] = false;
  return CommunityWorkspace.parse(data);
}

class _Probe {
  _Probe(
    this.kind,
    this.suite, {
    this.light = false,
    this.large = false,
    this.embedded = false,
  }) {
    directory.reader = (target, query, offset) {
      directoryReads.add((target, query, offset));
      return directoryReply?.future ?? Future.value(workspace(query));
    };
  }
  final String kind;
  final InteractionSuite suite;
  bool light, large, embedded, reduce = false;
  String section = 'applications';
  final manage = _Management();
  final exit = ExitFake();
  final directory = WorkspaceTestPort();
  final directoryReads = <(String, String, int)>[];
  Completer<CommunityWorkspace>? directoryReply;
  final capture = GlobalKey();
  late StateSetter update;
  int approvedCallbacks = 0;
  Type get dialogType => kind == 'management'
      ? CommunityManagementDialog
      : CommunityOwnershipExitDialog;
  dynamic state(WidgetTester t) => t.state(find.byType(dialogType)) as dynamic;
  dynamic model(WidgetTester t) =>
      kind == 'management' ? state(t).model : state(t).confirmation;
  Widget dialog() => kind == 'management'
      ? CommunityManagementDialog(
          port: manage,
          targetRef: _target,
          name: '探索组织',
          initialSection: section,
          embedded: embedded,
          onMembersChanged: () => approvedCallbacks++,
        )
      : CommunityOwnershipExitDialog(
          port: exit,
          workspacePort: directory,
          targetRef: _target,
        );
  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, set) {
        update = set;
        final base = scopedApp(
          Builder(
            builder: (context) => StarBridgeActionButton(
              controlKey: const Key('open-governance-stage'),
              onActivate: (_) => showStarBridgeDialog<void>(
                context,
                barrierDismissible: false,
                builder: (_) => embedded ? Material(child: dialog()) : dialog(),
              ),
              child: const Text('Open stages'),
            ),
          ),
          suite,
          light: light,
          reduce: reduce,
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
  Future<void> clean(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await manage.changes.close();
    await exit.changes.close();
    await directory.changes.close();
  }
}

// ignore: library_private_types_in_public_api
Future<void> open(WidgetTester t, _Probe p, String source) async {
  size(t, const Size(1200, 1100));
  await t.pumpWidget(p.app());
  await frames(t);
  await activate(t, const Key('open-governance-stage'), source);
  await frames(t);
}

Finder marker(String phase) => find.byKey(ValueKey('$phase-activity'));
void waiting(WidgetTester t, String phase, {required bool animated}) {
  expect(marker(phase), findsOneWidget);
  final target = find.descendant(
    of: marker(phase),
    matching: find.byType(SuiteBusyFrame),
  );
  expect(target, findsOneWidget);
  expect(InteractionScope.of(t.element(target)).reduceMotion, !animated);
}

void main() {
  setUpAll(loadFonts);
  moreCases();
  for (final kind in ['management', 'exit']) {
    testWidgets('3ga $kind keyboard initial wait must not loop', (t) async {
      final p = _Probe(kind, InteractionSuite.standard);
      if (kind == 'management') {
        p.manage.reading = Completer();
      } else {
        p.directoryReply = Completer();
      }
      try {
        await open(t, p, 'keyboard');
        final value = kind == 'management'
            ? t
                  .widget<CircularProgressIndicator>(
                    find.byType(CircularProgressIndicator),
                  )
                  .value
            : t
                  .widget<LinearProgressIndicator>(
                    find.byType(LinearProgressIndicator),
                  )
                  .value;
        expect(value, isNotNull);
        if (kind == 'management') {
          await p.manage.readDone();
        } else {
          p.directoryReply!.complete(workspace(''));
        }
        await frames(t);
      } finally {
        await p.clean(t);
      }
    });
  }
}

Future<void> flush(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await frames(t);
}

Key actionKey(String action) => switch (action) {
  'generateInvite' => const Key('management-generate'),
  'revokeInvite' => ValueKey('management-revoke-${'d' * 32}'),
  _ => ValueKey('management-$action-$_member'),
};
Future<void> managementAction(
  WidgetTester t,
  // ignore: library_private_types_in_public_api
  _Probe p,
  String action,
  String source, {
  bool cancelFirst = false,
}) async {
  final writes = p.manage.intents.length;
  await activate(
    t,
    actionKey(action),
    source == 'pointer' ? 'keyboard' : 'pointer',
  );
  expect(p.manage.intents.length, writes);
  if (cancelFirst) {
    await activate(t, const Key('management-confirm-cancel'), source);
    expect(p.manage.intents.length, writes);
    await activate(
      t,
      actionKey(action),
      source == 'pointer' ? 'keyboard' : 'pointer',
    );
  }
  await activate(t, const Key('management-confirm-accept'), source);
}

Future<void> choose(WidgetTester t, String source) async {
  final key = const ValueKey('successor-action-$_member');
  final target = find.byKey(key);
  if (source == 'keyboard') {
    await t.ensureVisible(target);
    t
        .widget<FocusableActionDetector>(
          find
              .descendant(
                of: target,
                matching: find.byType(FocusableActionDetector),
              )
              .first,
        )
        .focusNode!
        .requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await frames(t);
  } else {
    await activate(t, key, source);
  }
}

// ignore: library_private_types_in_public_api
void previewDone(_Probe p, {bool fail = false, String name = '示例成员'}) {
  if (fail) {
    p.exit.pendingRead!.completeError(const CommunityFailure('unavailable'));
    return;
  }
  p.exit.pendingRead!.complete(
    CommunityOwnershipExit.parse(exitPayload()..['callsign'] = name),
  );
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
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_review/$png.png')
            .writeAsBytes(data!.buffer.asUint8List());
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

void moreCases() {
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3ga management $suite $source section read keeps selection and source',
        (t) async {
          final p = _Probe('management', suite);
          try {
            await open(t, p, source == 'pointer' ? 'keyboard' : 'pointer');
            p.manage.reading = Completer();
            if (source == 'reader') {
              await governance.action(
                t,
                const ValueKey('management-section-invites'),
                source,
                settle: false,
              );
              await frames(t);
            } else {
              await activate(
                t,
                const ValueKey('management-section-invites'),
                source,
              );
            }
            waiting(t, 'management-read', animated: source == 'pointer');
            expect(p.manage.reads.last, (_target, 'invites', 0));
            expect(p.manage.reads.length, 2);
            expect(p.model(t).section, 'invites');
            expect(p.manage.intents, isEmpty);
            await p.manage.readDone();
            await flush(t);
            expect(p.model(t).page.section, 'invites');
            expect(marker('management-read'), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );
      testWidgets(
        '3ga exit $suite $source actual search is its own directory phase',
        (t) async {
          final p = _Probe('exit', suite);
          try {
            await open(t, p, source == 'pointer' ? 'keyboard' : 'pointer');
            await t.enterText(
              find.byKey(const Key('ownership-exit-search')),
              'pilot',
            );
            p.directoryReply = Completer();
            if (source == 'keyboard') {
              await t.testTextInput.receiveAction(TextInputAction.done);
              await frames(t);
            } else {
              await activate(
                t,
                const Key('ownership-exit-search-submit'),
                source,
              );
            }
            waiting(t, 'exit-directory', animated: source == 'pointer');
            expect(p.directoryReads.last, (_target, 'pilot', 0));
            expect(p.directoryReads.length, 2);
            expect(p.exit.reads, 0);
            expect(p.exit.writes, 0);
            p.directoryReply!.complete(workspace('pilot'));
            await frames(t);
            expect(marker('exit-directory'), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );
    }

    for (final kind in ['management', 'exit']) {
      testWidgets(
        '3ga $kind $suite initial read failure keyboard retry then cancel',
        (t) async {
          final p = _Probe(kind, suite);
          try {
            if (kind == 'management') {
              p.manage.reading = Completer();
            } else {
              p.directoryReply = Completer();
            }
            await open(t, p, 'pointer');
            if (kind == 'management') {
              await p.manage.readDone(error: true);
            } else {
              p.directoryReply!.completeError(
                const CommunityFailure('unavailable'),
              );
            }
            await frames(t);
            expect(
              marker(
                kind == 'management' ? 'management-read' : 'exit-directory',
              ),
              findsNothing,
            );
            if (kind == 'management') {
              p.manage.reading = Completer();
            } else {
              p.directoryReply = Completer();
            }
            await activate(
              t,
              Key(
                kind == 'management'
                    ? 'management-refresh'
                    : 'ownership-exit-reload',
              ),
              'keyboard',
            );
            waiting(
              t,
              kind == 'management' ? 'management-read' : 'exit-directory',
              animated: false,
            );
            await activate(
              t,
              Key(
                kind == 'management'
                    ? 'management-close'
                    : 'ownership-exit-cancel',
              ),
              'keyboard',
            );
            expect(find.byType(p.dialogType), findsNothing);
            if (kind == 'management') {
              await p.manage.readDone();
            } else {
              p.directoryReply!.complete(workspace(''));
            }
            await flush(t);
            expect(find.byType(p.dialogType), findsNothing);
            expect(p.manage.intents, isEmpty);
            expect(p.exit.writes, 0);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );
    }

    testWidgets(
      '3ga exit $suite preview failure is retried without replacing controller',
      (t) async {
        final p = _Probe('exit', suite);
        try {
          await open(t, p, 'pointer');
          p.exit.pendingRead = Completer();
          await choose(t, 'pointer');
          final model = p.model(t);
          previewDone(p, fail: true);
          await flush(t);
          expect(marker('exit-preview'), findsNothing);
          expect(p.exit.writes, 0);
          p.exit.pendingRead = Completer();
          await activate(t, const Key('ownership-exit-reload'), 'keyboard');
          waiting(t, 'exit-preview', animated: false);
          expect(identical(model, p.model(t)), isTrue);
          previewDone(p);
          await flush(t);
          expect(p.exit.reads, 2);
          expect(p.exit.writes, 0);
          expect(marker('exit-preview'), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      },
    );

    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final kind in ['management', 'exit']) {
        testWidgets('3ga $kind $suite $source initial phase and live reduce', (
          t,
        ) async {
          final p = _Probe(kind, suite);
          if (kind == 'management') {
            p.manage.reading = Completer();
          } else {
            p.directoryReply = Completer();
          }
          final phase = kind == 'management'
              ? 'management-read'
              : 'exit-directory';
          try {
            await open(t, p, source);
            waiting(t, phase, animated: source == 'pointer');
            p.update(() => p.reduce = true);
            await t.pump();
            await t.pump();
            waiting(t, phase, animated: false);
            p.update(() => p.reduce = false);
            await t.pump();
            await t.pump();
            waiting(t, phase, animated: source == 'pointer');
            if (kind == 'management') {
              await p.manage.readDone();
            } else {
              p.directoryReply!.complete(workspace(''));
            }
            await frames(t);
            expect(marker(phase), findsNothing);
            expect(p.manage.intents, isEmpty);
            expect(p.exit.writes, 0);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        });
      }
      for (final action in [
        'approve',
        'decline',
        'generateInvite',
        'revokeInvite',
      ]) {
        testWidgets(
          '3ga management $suite $source $action confirmation write then reread',
          (t) async {
            final p = _Probe('management', suite)
              ..section = (action == 'approve' || action == 'decline'
                  ? 'applications'
                  : 'invites');
            try {
              await open(t, p, source == 'pointer' ? 'keyboard' : 'pointer');
              p.manage.hold = Completer();
              await managementAction(t, p, action, source, cancelFirst: true);
              waiting(t, 'management-write', animated: source == 'pointer');
              expect(marker('management-read'), findsNothing);
              expect(p.manage.reads.length, 1);
              expect(p.manage.intents.length, 1);
              final intent = p.manage.intents.single;
              expect(intent.action.name, action);
              expect(intent.targetRef, _target);
              expect(intent.confirmUncertainRetry, isFalse);
              expect(
                intent.entryRef,
                action == 'generateInvite'
                    ? isNull
                    : action == 'revokeInvite'
                    ? 'd' * 32
                    : _member,
              );
              expect(
                intent.expiresInDays,
                action == 'generateInvite' ? 7 : isNull,
              );
              expect(intent.maxUses, action == 'generateInvite' ? 1 : isNull);
              final rect = t.getRect(marker('management-write'));
              expect(
                rect.size,
                suite == InteractionSuite.standard
                    ? const Size(20, 20)
                    : const Size(20, 4),
              );
              p.update(() => p.reduce = true);
              await t.pump();
              await t.pump();
              waiting(t, 'management-write', animated: false);
              p.update(() => p.reduce = false);
              await t.pump();
              await t.pump();
              waiting(t, 'management-write', animated: source == 'pointer');
              p.manage.reading = Completer();
              p.manage.hold!.complete(
                const CommunityAdmissionOutcome('accepted'),
              );
              await flush(t);
              expect(marker('management-write'), findsNothing);
              waiting(t, 'management-read', animated: source == 'pointer');
              expect(p.manage.reads.length, 2);
              expect(p.approvedCallbacks, 0);
              expect(p.model(t).outcome.status, 'accepted');
              await p.manage.readDone();
              await flush(t);
              expect(marker('management-read'), findsNothing);
              expect(p.manage.intents.length, 1);
              expect(p.approvedCallbacks, action == 'approve' ? 1 : 0);
              expect(t.takeException(), isNull);
            } finally {
              await p.clean(t);
            }
          },
        );
      }
      testWidgets('3ga exit $suite $source dynamic preview and actual leave', (
        t,
      ) async {
        final p = _Probe('exit', suite);
        try {
          await open(t, p, source);
          p.exit.pendingRead = Completer();
          final choosing = source == 'pointer' ? 'keyboard' : 'pointer';
          await choose(t, choosing);
          waiting(t, 'exit-preview', animated: choosing == 'pointer');
          expect(marker('exit-directory'), findsNothing);
          expect(p.exit.writes, 0);
          previewDone(p);
          await flush(t);
          expect(marker('exit-preview'), findsNothing);
          p.exit.pendingWrite = Completer();
          await activate(t, const Key('ownership-exit-confirm'), source);
          waiting(t, 'exit-write', animated: source == 'pointer');
          expect(p.exit.writes, 1);
          expect(p.exit.reads, 1);
          expect(p.exit.confirmations, [false]);
          p.update(() => p.reduce = true);
          await t.pump();
          await t.pump();
          waiting(t, 'exit-write', animated: false);
          p.update(() => p.reduce = false);
          await t.pump();
          await t.pump();
          waiting(t, 'exit-write', animated: source == 'pointer');
          p.exit.pendingWrite!.complete(
            const CommunityOwnershipTransferOutcome('accepted'),
          );
          await flush(t);
          expect(find.byType(CommunityOwnershipExitDialog), findsNothing);
          expect(p.directoryReads.length, 1);
          expect(p.exit.writes, 1);
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      });
    }

    testWidgets(
      '3ga management $suite quiet retained read is unknown static and preserves original failure outcome',
      (t) async {
        final p = _Probe('management', suite, embedded: true);
        try {
          await open(t, p, 'pointer');
          final page = p.model(t).page;
          p.manage.reading = Completer();
          final read = p.state(t).refreshVisibleCommunity() as Future<void>;
          await frames(t);
          waiting(t, 'management-read', animated: false);
          expect(identical(page, p.model(t).page), isTrue);
          await p.manage.readDone(error: true);
          await read;
          await frames(t);
          expect(identical(page, p.model(t).page), isTrue);
          expect(p.model(t).error, 'unavailable');
          expect(p.manage.reads.length, 2);
          expect(p.manage.intents, isEmpty);
          expect(marker('management-read'), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      },
    );

    for (final outcome in ['unknown', 'rejected']) {
      testWidgets(
        '3ga management $suite $outcome explicit retry and final confirmation source',
        (t) async {
          final p = _Probe('management', suite);
          try {
            await open(t, p, 'keyboard');
            p.manage.hold = Completer();
            await managementAction(t, p, 'approve', 'pointer');
            p.manage.hold!.complete(
              CommunityAdmissionOutcome(
                outcome,
                error: outcome == 'unknown' ? 'outcomeUnknown' : 'conflict',
              ),
            );
            await flush(t);
            expect(p.manage.intents.length, 1);
            expect(p.manage.reads.length, 2);
            expect(p.model(t).outcome.status, outcome);
            expect(marker('management-write'), findsNothing);
            p.manage.hold = Completer();
            await managementAction(
              t,
              p,
              'approve',
              'keyboard',
              cancelFirst: true,
            );
            waiting(t, 'management-write', animated: false);
            expect(p.manage.intents.length, 2);
            expect(
              p.manage.intents.last.confirmUncertainRetry,
              outcome == 'unknown',
            );
            p.manage.reading = Completer();
            p.manage.hold!.complete(
              const CommunityAdmissionOutcome('accepted'),
            );
            await flush(t);
            waiting(t, 'management-read', animated: false);
            await p.manage.readDone(error: true);
            await flush(t);
            expect(p.model(t).outcome.status, 'accepted');
            expect(p.model(t).error, 'unavailable');
            expect(p.manage.intents.length, 2);
            expect(p.manage.reads.length, 3);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );

      testWidgets(
        '3ga exit $suite $outcome explicit reload and retry contract',
        (t) async {
          final p = _Probe('exit', suite);
          try {
            await open(t, p, 'pointer');
            await choose(t, 'pointer');
            p.exit.pendingWrite = Completer();
            await activate(t, const Key('ownership-exit-confirm'), 'pointer');
            p.exit.pendingWrite!.complete(
              CommunityOwnershipTransferOutcome(
                outcome,
                error: outcome == 'unknown' ? 'outcomeUnknown' : 'conflict',
              ),
            );
            await flush(t);
            expect(marker('exit-write'), findsNothing);
            expect(p.exit.writes, 1);
            if (outcome == 'unknown') {
              expect(
                find.byKey(const Key('ownership-exit-back')),
                findsNothing,
              );
            }
            p.exit.pendingRead = Completer();
            await activate(t, const Key('ownership-exit-reload'), 'keyboard');
            waiting(t, 'exit-preview', animated: false);
            previewDone(p);
            await flush(t);
            p.exit.pendingWrite = Completer();
            await activate(t, const Key('ownership-exit-confirm'), 'keyboard');
            waiting(t, 'exit-write', animated: false);
            expect(p.exit.confirmations, [false, outcome == 'unknown']);
            p.exit.pendingWrite!.complete(
              const CommunityOwnershipTransferOutcome('accepted'),
            );
            await flush(t);
            expect(find.byType(CommunityOwnershipExitDialog), findsNothing);
            expect(p.exit.writes, 2);
            expect(p.exit.reads, 2);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );
    }

    testWidgets(
      '3ga exit $suite back disposes old preview binding and late reply cannot revive it',
      (t) async {
        final p = _Probe('exit', suite);
        try {
          await open(t, p, 'pointer');
          p.exit.pendingRead = Completer();
          final old = p.exit.pendingRead!;
          await choose(t, 'pointer');
          waiting(t, 'exit-preview', animated: true);
          final oldModel = p.model(t);
          p.directoryReply = Completer();
          await activate(t, const Key('ownership-exit-back'), 'keyboard');
          waiting(t, 'exit-directory', animated: false);
          expect(marker('exit-preview'), findsNothing);
          old.complete(
            CommunityOwnershipExit.parse(exitPayload()..['callsign'] = '迟到旧预览'),
          );
          await flush(t);
          expect(p.model(t), isNull);
          expect(find.text('迟到旧预览'), findsNothing);
          p.directoryReply!.complete(workspace(''));
          await frames(t);
          p.exit.pendingRead = Completer();
          await choose(t, 'keyboard');
          waiting(t, 'exit-preview', animated: false);
          expect(identical(oldModel, p.model(t)), isFalse);
          previewDone(p, name: '最新确认');
          await flush(t);
          expect(find.text('最新确认'), findsOneWidget);
          expect(p.exit.writes, 0);
          expect(p.exit.reads, 2);
          expect(p.directoryReads.length, 2);
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      },
    );

    for (final phase in ['preview', 'write']) {
      testWidgets(
        '3ga exit $suite invalidate $phase retires wait and ignores late reply',
        (t) async {
          final p = _Probe('exit', suite);
          try {
            await open(t, p, 'pointer');
            if (phase == 'preview') p.exit.pendingRead = Completer();
            await choose(t, 'pointer');
            if (phase == 'write') {
              p.exit.pendingWrite = Completer();
              await activate(t, const Key('ownership-exit-confirm'), 'pointer');
            }
            waiting(t, 'exit-$phase', animated: true);
            p.exit.changes.add(null);
            await frames(t);
            expect(marker('exit-$phase'), findsNothing);
            if (phase == 'preview') {
              previewDone(p, name: '迟到确认');
            } else {
              p.exit.pendingWrite!.complete(
                const CommunityOwnershipTransferOutcome('accepted'),
              );
            }
            await flush(t);
            expect(find.byType(CommunityOwnershipExitDialog), findsOneWidget);
            expect(find.text('迟到确认'), findsNothing);
            expect(p.exit.writes, phase == 'write' ? 1 : 0);
            expect(p.directoryReads.length, 1);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );
    }

    testWidgets(
      '3ga management $suite invalidation closes original route and late receipt cannot reread',
      (t) async {
        final p = _Probe('management', suite);
        try {
          await open(t, p, 'pointer');
          p.manage.hold = Completer();
          await managementAction(t, p, 'approve', 'pointer');
          p.manage.changes.add(null);
          await frames(t);
          expect(find.byType(CommunityManagementDialog), findsNothing);
          p.manage.hold!.complete(const CommunityAdmissionOutcome('accepted'));
          await flush(t);
          expect(p.manage.reads.length, 1);
          expect(p.approvedCallbacks, 0);
          expect(p.manage.intents.length, 1);
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      },
    );

    for (final phase in [
      'management-read',
      'management-write',
      'exit-directory',
      'exit-preview',
      'exit-write',
    ]) {
      testWidgets('3ga $suite $phase actual large Chinese wait visual', (
        t,
      ) async {
        final p = _Probe(
          phase.startsWith('management') ? 'management' : 'exit',
          suite,
          large: true,
          light:
              suite == InteractionSuite.rail || suite == InteractionSuite.glow,
        );
        try {
          if (phase == 'management-read') p.manage.reading = Completer();
          if (phase == 'exit-directory') p.directoryReply = Completer();
          await open(t, p, 'pointer');
          if (phase == 'management-write') {
            p.manage.hold = Completer();
            await managementAction(t, p, 'approve', 'pointer');
          }
          if (phase == 'exit-preview') {
            p.exit.pendingRead = Completer();
            await choose(t, 'pointer');
          }
          if (phase == 'exit-write') {
            await choose(t, 'pointer');
            p.exit.pendingWrite = Completer();
            await activate(t, const Key('ownership-exit-confirm'), 'pointer');
          }
          waiting(t, phase, animated: true);
          await frames(t);
          final rect = t.getRect(marker(phase));
          final first = await pixels(t, p, rect, png: '$phase-${suite.name}');
          final movingSamples = <int>[];
          if (suite == InteractionSuite.rail && phase == 'management-write') {
            // A 20px rail shuttle can be outside the track or on its same-color
            // static half at two isolated timestamps. Observe a full 1s loop,
            // requiring multiple visible changes rather than weakening >0.
            var previous = first;
            for (var i = 0; i < 8; i++) {
              await frames(t, 8);
              final next = await pixels(t, p, rect);
              movingSamples.add(changed(previous, next));
              previous = next;
            }
            expect(movingSamples.where((v) => v > 0).length, greaterThan(1));
          } else {
            await frames(t, 17);
            movingSamples.add(changed(first, await pixels(t, p, rect)));
          }
          final moving = movingSamples.reduce((a, b) => a > b ? a : b);
          expect(moving, greaterThan(0));
          p.update(() => p.reduce = true);
          await t.pump();
          await t.pump();
          final stillA = await pixels(t, p, rect);
          await frames(t, 38);
          final stillB = await pixels(t, p, rect);
          final still = changed(stillA, stillB);
          expect(still, 0);
          expect(t.getRect(marker(phase)), rect);
          File('$_review/$phase-${suite.name}.json').writeAsStringSync(
            jsonEncode({
              'movingPixels': moving,
              'movingSamples': movingSamples,
              'staticPixels': still,
              'rect': [rect.left, rect.top, rect.width, rect.height],
            }),
          );
          await t.pumpWidget(const SizedBox());
          if (phase == 'management-read') await p.manage.readDone();
          if (phase == 'management-write') {
            p.manage.hold!.complete(
              const CommunityAdmissionOutcome('accepted'),
            );
          }
          if (phase == 'exit-directory') {
            p.directoryReply!.complete(workspace(''));
          }
          if (phase == 'exit-preview') previewDone(p);
          if (phase == 'exit-write') {
            p.exit.pendingWrite!.complete(
              const CommunityOwnershipTransferOutcome('accepted'),
            );
          }
          await flush(t);
          expect(p.manage.reads.length, phase.startsWith('management') ? 1 : 0);
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      });
    }
  }
}
