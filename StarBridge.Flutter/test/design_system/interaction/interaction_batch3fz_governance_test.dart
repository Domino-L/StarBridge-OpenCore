import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_member_removal_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_member_removal_port.dart';
import 'package:starbridge_flutter/features/communities/community_member_role_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_member_role_port.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_transfer_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ownership_transfer_port.dart';
import 'package:starbridge_flutter/features/communities/community_disband_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_disband_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/communities/community_member_removal_test.dart'
    show RemovalFake, removalPayload;
import '../../features/communities/community_member_role_test.dart'
    show MemberRoleFake, memberRolePayload;
import '../../features/communities/community_ownership_transfer_test.dart'
    show TransferFake, transferPayload;
import '../../features/communities/community_disband_test.dart'
    show DisbandFake, disbandPayload;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3fw_workspace_test.dart' show activate;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;
import 'interaction_batch3af_test.dart' as draft show activate;

final _review = visualOutputDir(
  'interaction_motion_batch3fz_20261017',
  legacySubdirectory: 'review',
);
const _kinds = ['removal', 'role', 'transfer', 'disband'];

class _Probe {
  _Probe(this.kind, this.suite, {this.large = false, this.light = false});
  final String kind;
  final InteractionSuite suite;
  final removal = RemovalFake();
  final role = MemberRoleFake();
  final transfer = TransferFake();
  final disband = DisbandFake();
  final capture = GlobalKey();
  bool reduce = false, large, light;
  late StateSetter update;
  dynamic get port => switch (kind) {
    'removal' => removal,
    'role' => role,
    'transfer' => transfer,
    _ => disband,
  };
  Type get dialogType => switch (kind) {
    'removal' => CommunityMemberRemovalDialog,
    'role' => CommunityMemberRoleDialog,
    'transfer' => CommunityOwnershipTransferDialog,
    _ => CommunityDisbandDialog,
  };
  dynamic model(WidgetTester t) =>
      (t.state(find.byType(dialogType)) as dynamic).model;
  void holdRead() {
    switch (kind) {
      case 'removal':
        removal.pendingRead = Completer<CommunityMemberRemoval>();
      case 'role':
        role.pendingRead = Completer<CommunityMemberRole>();
      case 'transfer':
        transfer.pendingRead = Completer<CommunityOwnershipTransfer>();
      default:
        disband.reading = Completer<CommunityDisbandPreview>();
    }
  }

  void readDone({bool fail = false, bool assigned = false}) {
    if (fail) {
      switch (kind) {
        case 'removal':
          removal.pendingRead!.completeError(
            const CommunityFailure('unavailable'),
          );
        case 'role':
          role.pendingRead!.completeError(
            const CommunityFailure('unavailable'),
          );
        case 'transfer':
          transfer.pendingRead!.completeError(
            const CommunityFailure('unavailable'),
          );
        default:
          disband.reading!.completeError(const CommunityFailure('unavailable'));
      }
      return;
    }
    switch (kind) {
      case 'removal':
        removal.pendingRead!.complete(
          CommunityMemberRemoval.parse(removalPayload()),
        );
      case 'role':
        role.pendingRead!.complete(
          CommunityMemberRole.parse(
            memberRolePayload(role: assigned ? 'custom_navigation' : ''),
          ),
        );
      case 'transfer':
        transfer.pendingRead!.complete(
          CommunityOwnershipTransfer.parse(transferPayload()),
        );
      default:
        disband.reading!.complete(
          CommunityDisbandPreview.parse(disbandPayload()),
        );
    }
  }

  void holdWrite() {
    switch (kind) {
      case 'removal':
        removal.pendingWrite = Completer<CommunityMemberRemovalOutcome>();
      case 'role':
        role.pendingWrite = Completer<CommunityMemberRoleOutcome>();
      case 'transfer':
        transfer.pendingWrite = Completer<CommunityOwnershipTransferOutcome>();
      default:
        disband.writing = Completer<CommunityDisbandOutcome>();
    }
  }

  void writeDone(String status) {
    final error = status == 'rejected'
        ? (kind == 'disband' ? 'passwordInvalid' : 'conflict')
        : status == 'unknown'
        ? 'outcomeUnknown'
        : null;
    switch (kind) {
      case 'removal':
        removal.pendingWrite!.complete(
          CommunityMemberRemovalOutcome(status, error: error),
        );
      case 'role':
        role.pendingWrite!.complete(
          CommunityMemberRoleOutcome(status, error: error),
        );
      case 'transfer':
        transfer.pendingWrite!.complete(
          CommunityOwnershipTransferOutcome(status, error: error),
        );
      default:
        disband.writing!.complete(
          CommunityDisbandOutcome(status, error: error),
        );
    }
  }

  Key get confirm => Key(switch (kind) {
    'removal' => 'member-remove-confirm',
    'role' => 'member-role-save',
    'transfer' => 'member-transfer-confirm',
    _ => 'community-disband-confirm',
  });
  Key get reload => Key(switch (kind) {
    'removal' => 'member-remove-reload',
    'role' => 'member-role-reload',
    'transfer' => 'member-transfer-reload',
    _ => 'community-disband-reload',
  });
  Key get cancel => Key(switch (kind) {
    'removal' => 'member-remove-cancel',
    'role' => 'member-role-close',
    'transfer' => 'member-transfer-cancel',
    _ => 'community-disband-cancel',
  });
  Widget dialog() => switch (kind) {
    'removal' => CommunityMemberRemovalDialog(
      port: removal,
      targetRef: 'a' * 32,
      memberRef: 'b' * 32,
      organizationName: '探索组织',
    ),
    'role' => CommunityMemberRoleDialog(
      port: role,
      targetRef: 'a' * 32,
      memberRef: 'b' * 32,
    ),
    'transfer' => CommunityOwnershipTransferDialog(
      port: transfer,
      targetRef: 'a' * 32,
      memberRef: 'b' * 32,
      organizationName: '探索组织',
    ),
    _ => CommunityDisbandDialog(port: disband, targetRef: 'a' * 32),
  };
  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, set) {
        update = set;
        final base = scopedApp(
          Builder(
            builder: (context) => StarBridgeActionButton(
              controlKey: const Key('governance-open'),
              onActivate: (_) => showStarBridgeDialog<void>(
                context,
                barrierDismissible: false,
                builder: (_) => dialog(),
              ),
              child: const Text('Open governance'),
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
    await removal.changes.close();
    await role.changes.close();
    await transfer.changes.close();
    await disband.changes.close();
  }
}

// ignore: library_private_types_in_public_api
Future<void> open(WidgetTester t, _Probe p, String source) async {
  size(t, const Size(1200, 1100));
  await t.pumpWidget(p.app());
  await frames(t);
  await activate(t, const Key('governance-open'), source);
  await frames(t);
}

Finder marker(String kind) => find.byKey(ValueKey('$kind-activity'));
void waiting(WidgetTester t, String kind, {required bool animated}) {
  expect(marker(kind), findsOneWidget);
  final busy = find.descendant(
    of: marker(kind),
    matching: find.byType(SuiteBusyFrame),
  );
  expect(busy, findsOneWidget);
  expect(InteractionScope.of(t.element(busy)).reduceMotion, !animated);
}

void main() {
  setUpAll(loadFonts);
  moreCases();
  testWidgets('3fz keyboard removal initial wait must not loop', (t) async {
    final p = _Probe('removal', InteractionSuite.standard)..holdRead();
    try {
      await open(t, p, 'keyboard');
      expect(
        t
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNotNull,
      );
      p.readDone();
      await frames(t);
    } finally {
      await p.clean(t);
    }
  });
  for (final kind in _kinds) {
    for (final suite in InteractionSuite.values) {
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets('3fz $kind $suite $source initial wait and live reduce', (
          t,
        ) async {
          final p = _Probe(kind, suite)..holdRead();
          try {
            await open(t, p, source);
            waiting(t, kind, animated: source == 'pointer');
            expect(p.port.reads, 1);
            expect(p.port.writes, 0);
            p.update(() => p.reduce = true);
            await t.pump();
            await t.pump();
            waiting(t, kind, animated: false);
            p.update(() => p.reduce = false);
            await t.pump();
            await t.pump();
            waiting(t, kind, animated: source == 'pointer');
            p.readDone();
            await frames(t);
            expect(marker(kind), findsNothing);
            expect(p.port.writes, 0);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        });
      }
    }
  }
}

// ignore: library_private_types_in_public_api
Future<void> prepare(WidgetTester t, _Probe p, String source) async {
  if (p.kind == 'role') {
    final target = find.byWidgetPredicate(
      (w) =>
          w is StarBridgeActionRow &&
          w.controlKey == const ValueKey('assign-option-custom_navigation'),
    );
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
      await draft.activate(t, target, source);
    }
    expect(p.model(t).selectedKey, 'custom_navigation');
  } else if (p.kind == 'disband') {
    await t.enterText(
      find.byKey(const Key('community-disband-password')),
      ' fixture-password ',
    );
    await frames(t);
  }
}

Future<void> submit(
  WidgetTester t,
  // ignore: library_private_types_in_public_api
  _Probe p,
  String source, {
  bool testCancel = false,
}) async {
  if (p.kind == 'role') {
    final writesBefore = p.port.writes;
    await activate(t, p.confirm, source == 'pointer' ? 'keyboard' : 'pointer');
    expect(p.port.writes, writesBefore);
    if (testCancel) {
      await activate(t, const Key('member-role-confirm-cancel'), source);
      expect(p.port.writes, writesBefore);
      expect(p.model(t).dirty, isTrue);
      await activate(
        t,
        p.confirm,
        source == 'pointer' ? 'keyboard' : 'pointer',
      );
    }
    await activate(t, const Key('member-role-confirm-accept'), source);
  } else {
    await activate(t, p.confirm, source);
  }
  await frames(t);
}

Future<void> flushReply(WidgetTester t) async {
  // Semantics dispatch can cross the test zone. Deliver the fake Port reply's
  // real event turn; this is not a product delay or a relaxed state assertion.
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await frames(t);
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
  for (final kind in _kinds) {
    for (final suite in InteractionSuite.values) {
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '3fz $kind $suite $source actual submission and accepted reread',
          (t) async {
            final p = _Probe(kind, suite);
            try {
              await open(t, p, source == 'pointer' ? 'keyboard' : 'pointer');
              await prepare(t, p, source);
              p.holdWrite();
              await submit(t, p, source, testCancel: true);
              expect(p.port.writes, 1);
              expect(p.port.reads, 1);
              waiting(t, kind, animated: source == 'pointer');
              expect(
                p.kind == 'disband'
                    ? p.model(t).sending
                    : p.model(t).submitting,
                isTrue,
              );
              expect(
                t
                    .widget<StarBridgeActionButton>(
                      find
                          .ancestor(
                            of: find.byKey(p.confirm),
                            matching: find.byType(StarBridgeActionButton),
                          )
                          .first,
                    )
                    .onActivate,
                isNull,
              );
              if (kind == 'disband') {
                expect(p.disband.sentPassword, ' fixture-password ');
                expect(
                  t.widget<TextField>(find.byType(TextField)).controller!.text,
                  isEmpty,
                );
              } else if (kind != 'role') {
                expect(p.port.confirmations, [false]);
              }
              p.update(() => p.reduce = true);
              await t.pump();
              await t.pump();
              waiting(t, kind, animated: false);
              p.update(() => p.reduce = false);
              await t.pump();
              await t.pump();
              waiting(t, kind, animated: source == 'pointer');
              if (kind == 'role') p.holdRead();
              p.writeDone('accepted');
              await flushReply(t);
              if (kind == 'role') {
                expect(p.role.reads, 2);
                expect(p.role.writes, 1);
                expect(p.model(t).saved, isFalse);
                waiting(t, kind, animated: source == 'pointer');
                p.readDone(assigned: true);
                await flushReply(t);
              }
              expect(find.byType(p.dialogType), findsNothing);
              expect(p.port.writes, 1);
              expect(t.takeException(), isNull);
            } finally {
              await p.clean(t);
            }
          },
        );
      }

      testWidgets('3fz $kind $suite read failure and opposite-source retry', (
        t,
      ) async {
        final p = _Probe(kind, suite)..holdRead();
        try {
          await open(t, p, 'pointer');
          p.readDone(fail: true);
          await frames(t);
          expect(marker(kind), findsNothing);
          expect(p.port.writes, 0);
          p.holdRead();
          await activate(t, p.reload, 'keyboard');
          waiting(t, kind, animated: false);
          expect(p.port.reads, 2);
          expect(p.port.writes, 0);
          p.readDone();
          await frames(t);
          expect(marker(kind), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      });

      testWidgets(
        '3fz $kind $suite rejected write preserves original reload contract',
        (t) async {
          final p = _Probe(kind, suite);
          try {
            await open(t, p, 'keyboard');
            await prepare(t, p, 'pointer');
            p.holdWrite();
            await submit(t, p, 'pointer');
            p.writeDone('rejected');
            await flushReply(t);
            expect(marker(kind), findsNothing);
            expect(find.byType(p.dialogType), findsOneWidget);
            expect(p.port.writes, 1);
            if (kind == 'role') {
              expect(p.model(t).dirty, isTrue);
              expect(p.model(t).selectedKey, 'custom_navigation');
            }
            p.holdRead();
            await activate(t, p.reload, 'pointer');
            if (kind == 'role') {
              expect(marker(kind), findsNothing);
              expect(p.port.reads, 1);
              await activate(
                t,
                const Key('member-role-confirm-cancel'),
                'keyboard',
              );
              expect(p.model(t).dirty, isTrue);
              expect(p.port.reads, 1);
              await activate(t, p.reload, 'pointer');
              await activate(
                t,
                const Key('member-role-confirm-accept'),
                'keyboard',
              );
            }
            waiting(t, kind, animated: kind != 'role');
            expect(p.port.reads, 2);
            expect(p.port.writes, 1);
            p.readDone();
            await frames(t);
            expect(marker(kind), findsNothing);
            if (kind == 'role') expect(p.model(t).dirty, isFalse);
            if (kind == 'disband') {
              expect(
                t.widget<TextField>(find.byType(TextField)).controller!.text,
                isEmpty,
              );
            }
            expect(p.port.writes, 1);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );

      testWidgets(
        '3fz $kind $suite invalidation retires busy and ignores late accepted write',
        (t) async {
          final p = _Probe(kind, suite);
          try {
            await open(t, p, 'pointer');
            await prepare(t, p, 'pointer');
            p.holdWrite();
            await submit(t, p, 'pointer');
            p.port.changes.add(null);
            await frames(t);
            expect(marker(kind), findsNothing);
            expect(p.model(t).invalidated, isTrue);
            p.writeDone('accepted');
            await flushReply(t);
            expect(find.byType(p.dialogType), findsOneWidget);
            expect(p.port.writes, 1);
            expect(p.port.reads, 1);
            expect(find.text('示例成员'), findsNothing);
            expect(find.text('示例组织'), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );

      testWidgets(
        '3fz $kind $suite unknown never auto retries and explicit recovery keeps contract',
        (t) async {
          final p = _Probe(kind, suite);
          try {
            await open(t, p, 'keyboard');
            await prepare(t, p, 'pointer');
            p.holdWrite();
            await submit(t, p, 'pointer');
            p.writeDone('unknown');
            await flushReply(t);
            expect(marker(kind), findsNothing);
            expect(p.port.writes, 1);
            await frames(t, 60);
            expect(p.port.writes, 1);
            expect(p.port.reads, 1);
            if (kind == 'disband') {
              expect(find.byKey(p.reload), findsNothing);
              expect(find.byKey(p.confirm), findsNothing);
              expect(find.byType(TextField), findsNothing);
            } else {
              expect(p.model(t).requiresRetryConfirmation, isTrue);
              p.holdRead();
              await activate(t, p.reload, 'keyboard');
              if (kind == 'role') {
                expect(p.port.reads, 1);
                await activate(
                  t,
                  const Key('member-role-confirm-cancel'),
                  'pointer',
                );
                expect(p.port.writes, 1);
                expect(p.port.reads, 1);
                await activate(t, p.reload, 'pointer');
                await activate(
                  t,
                  const Key('member-role-confirm-accept'),
                  'keyboard',
                );
              }
              waiting(t, kind, animated: false);
              p.readDone();
              await flushReply(t);
              await prepare(t, p, 'keyboard');
              p.holdWrite();
              if (kind == 'role') {
                await submit(t, p, 'keyboard', testCancel: true);
              } else {
                await activate(t, p.confirm, 'pointer');
              }
              expect(p.port.writes, 2);
              expect(p.port.confirmations, [false, true]);
              waiting(t, kind, animated: kind != 'role');
              if (kind == 'role') p.holdRead();
              p.writeDone('accepted');
              await flushReply(t);
              if (kind == 'role') {
                expect(p.port.reads, 3);
                waiting(t, kind, animated: false);
                p.readDone(assigned: true);
                await flushReply(t);
              }
              expect(find.byType(p.dialogType), findsNothing);
            }
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );

      testWidgets(
        '3fz $kind $suite close initial wait and late read do not write',
        (t) async {
          final p = _Probe(kind, suite)..holdRead();
          try {
            await open(t, p, 'pointer');
            await activate(t, p.cancel, 'keyboard');
            expect(find.byType(p.dialogType), findsNothing);
            p.readDone();
            await frames(t);
            expect(find.byType(p.dialogType), findsNothing);
            expect(p.port.writes, 0);
            expect(p.port.reads, 1);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );

      testWidgets(
        '3fz $kind $suite actual dialog Chinese large submission visual',
        (t) async {
          final p = _Probe(
            kind,
            suite,
            large: true,
            light:
                suite == InteractionSuite.rail ||
                suite == InteractionSuite.glow,
          );
          try {
            await open(t, p, 'pointer');
            await prepare(t, p, 'pointer');
            p.holdWrite();
            await submit(t, p, 'pointer');
            await frames(t);
            final rect = t.getRect(marker(kind));
            final before = await pixels(t, p, rect, png: '$kind-${suite.name}');
            await frames(t, 17);
            final after = await pixels(t, p, rect);
            final moving = changed(before, after);
            expect(moving, greaterThan(0));
            p.update(() => p.reduce = true);
            await t.pump();
            await t.pump();
            final staticA = await pixels(t, p, rect);
            await frames(t, 38);
            final staticB = await pixels(t, p, rect);
            final still = changed(staticA, staticB);
            expect(still, 0);
            expect(t.getRect(marker(kind)), rect);
            File('$_review/$kind-${suite.name}.json').writeAsStringSync(
              jsonEncode({
                'movingPixels': moving,
                'staticPixels': still,
                'rect': [rect.left, rect.top, rect.width, rect.height],
              }),
            );
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            p.writeDone('accepted');
            await flushReply(t);
            expect(p.port.writes, 1);
            expect(p.port.reads, 1);
          } finally {
            await p.clean(t);
          }
        },
      );
    }
  }
}
