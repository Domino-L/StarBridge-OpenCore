import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_controller.dart';
import 'package:starbridge_flutter/features/communities/community_announcement_write_port.dart';
import 'package:starbridge_flutter/features/communities/community_logs_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_logs_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import '../../features/communities/community_announcements_controller_test.dart'
    show AnnouncementsFake;
import '../../features/communities/community_announcements_test.dart'
    show target, itemRef;
import '../../features/communities/community_logs_test.dart' show logsPayload;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3am_test.dart' show action;

class Announcements extends AnnouncementsFake {
  final origins = <InteractionSource>[];
  @override
  Future<CommunityAnnouncementOutcome> manageAnnouncement(
    CommunityAnnouncementIntent intent,
  ) {
    origins.add(currentStarBridgeActivationSource);
    return super.manageAnnouncement(intent);
  }
}

class Logs implements CommunityLogsPort {
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool logsAvailable = true;
  @override
  bool logDeletionAvailable = true;
  bool allowed = true, empty = false;
  int reads = 0;
  String firstRef = 'b' * 32;
  String? failure;
  final readCalls = <(String, String, int, InteractionSource)>[];
  final writes = <(String, String, InteractionSource)>[];
  CommunityLogOutcome outcome = const CommunityLogOutcome('accepted');
  Completer<CommunityLogOutcome>? pending;
  @override
  Future<CommunityLogPage> readLogs(
    String ref,
    String type,
    String query,
    int offset,
  ) async {
    readCalls.add((type, query, offset, currentStarBridgeActivationSource));
    reads++;
    if (failure != null) {
      throw CommunityFailure(failure!);
    }
    firstRef = reads == 1
        ? 'b' * 32
        : (1000 + reads).toRadixString(16).padLeft(32, '0');
    final p = logsPayload();
    final sample = (p['items'] as List).single as Map<String, Object?>;
    p.addAll({
      'targetRef': ref,
      'type': type,
      'query': query,
      'offset': offset,
      'canDelete': allowed,
      'totalCount': empty ? 0 : 21,
      'matchedCount': empty ? 0 : 21,
      'next': !empty && offset == 0 ? 20 : null,
      'items': [
        if (!empty)
          for (var i = offset; i < (offset + 20).clamp(0, 21); i++)
            {
              ...sample,
              'type': type == 'All' ? '成员' : type,
              'logRef': i == offset
                  ? firstRef
                  : (10000 + i).toRadixString(16).padLeft(32, '0'),
            },
      ],
    });
    return CommunityLogPage.parse(p);
  }

  @override
  Future<CommunityLogOutcome> deleteLog(String ref, String logRef) async {
    writes.add((ref, logRef, currentStarBridgeActivationSource));
    final result = pending == null ? outcome : await pending!.future;
    if (result.status == 'accepted') empty = true;
    return result;
  }
}

Future<CommunityAnnouncementsController> entry(
  WidgetTester t,
  Announcements port,
  InteractionSuite suite,
  String source,
) async {
  await mount(
    t,
    CommunityAnnouncementEntry(port: port, targetRef: target),
    suite,
    width: 900,
  );
  await action(t, const Key('community-announcement-entry'), source);
  return t
      .state<CommunityAnnouncementsDialogState>(
        find.byType(CommunityAnnouncementsDialog),
      )
      .widget
      .model;
}

Future<void> draft(
  WidgetTester t, {
  String title = 'Updated title',
  String content = 'Full announcement body',
}) async {
  await t.enterText(find.byKey(const Key('announcement-title')), title);
  await t.enterText(find.byKey(const Key('announcement-content')), content);
  await t.pump();
}

StarBridgeActionButton button(WidgetTester t, Key key) => t.widget(
  find.byWidgetPredicate(
    (w) => w is StarBridgeActionButton && w.controlKey == key,
  ),
);
void main() {
  setUpAll(loadFonts);
  test(
    'log fixture preserves strict parsed filter and paging contract',
    () async {
      final port = Logs();
      addTearDown(port.changes.close);
      for (final type in communityLogFilters) {
        final page = await port.readLogs(target, type, 'retained query', 0);
        expect(page.items.length, 20);
        expect(page.next, 20);
        expect(
          page.items.every((row) => type == 'All' || row.type == type),
          true,
        );
        final last = await port.readLogs(target, type, 'retained query', 20);
        expect(last.items.length, 1);
        expect(last.next, isNull);
      }
    },
  );
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final operation in ['publish', 'edit', 'withdraw']) {
        testWidgets(
          'actual announcement center scoped command and close $suite $source $operation',
          (t) async {
            final semantics = t.ensureSemantics(), port = Announcements();
            addTearDown(port.changes.close);
            try {
              final model = await entry(t, port, suite, source);
              final route =
                  ModalRoute.of(
                        t.element(find.byType(CommunityAnnouncementsDialog)),
                      )!
                      as StarBridgeDialogRoute;
              expect(route.instant, source != 'pointer');
              final original = model.page!.current!.announcementRef;
              if (operation == 'withdraw') {
                await action(t, const Key('announcement-withdraw'), source);
                expect(port.writes, isEmpty);
                await action(
                  t,
                  const Key('announcement-confirm-cancel'),
                  source,
                );
                expect(port.writes, isEmpty);
                await action(t, const Key('announcement-withdraw'), source);
                await action(
                  t,
                  const Key('announcement-confirm-accept'),
                  source,
                );
              } else {
                await action(
                  t,
                  Key(
                    operation == 'publish'
                        ? 'announcement-create'
                        : 'announcement-edit',
                  ),
                  source,
                );
                await draft(t);
                expect(port.writes, isEmpty);
                await action(t, const Key('announcement-save'), source);
              }
              final intent = port.writes.single;
              expect(intent.action, operation);
              expect(intent.targetRef, target);
              expect(intent.requestId, matches(RegExp(r'^[a-f0-9]{32}$')));
              expect(
                intent.announcementRef,
                operation == 'publish' ? null : original,
              );
              if (operation != 'withdraw') {
                expect(
                  (intent.title, intent.content),
                  ('Updated title', 'Full announcement body'),
                );
              }
              expect(
                port.origins.single,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(model.success, isNotNull);
              expect(model.dirty, false);
              await action(t, const Key('announcement-close'), source);
              expect(find.byType(CommunityAnnouncementsDialog), findsNothing);
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox());
            } finally {
              semantics.dispose();
            }
          },
        );
      }
      testWidgets(
        'log filter search paging selection and explicit deletion $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(), port = Logs();
          addTearDown(port.changes.close);
          try {
            await mount(
              t,
              CommunityLogsDialog(
                port: port,
                targetRef: target,
                embedded: true,
              ),
              suite,
              width: 850,
            );
            await action(t, const Key('log-filter-公告'), source);
            await t.enterText(
              find.byKey(const Key('log-search')),
              ' retained query ',
            );
            await t.pump();
            await action(t, const Key('log-search-submit'), source);
            expect(port.readCalls.last.$1, '公告');
            expect(port.readCalls.last.$2, 'retained query');
            await action(t, const Key('log-next'), source);
            expect(port.readCalls.last.$3, 20);
            await action(t, const Key('log-previous'), source);
            expect(port.readCalls.last.$3, 0);
            final selectedRef = port.firstRef;
            await action(t, Key('log-delete-$selectedRef'), source);
            expect(port.writes, isEmpty);
            await action(t, const Key('log-keep'), source);
            expect(port.writes, isEmpty);
            await action(t, Key('log-delete-$selectedRef'), source);
            await action(t, const Key('log-confirm-delete'), source);
            expect(port.writes, [
              (
                target,
                selectedRef,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              ),
            ]);
            expect(port.readCalls.last.$2, 'retained query');
            expect(port.empty, true);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      'borrowed announcement owner survives entry disposal but both dialogs retire $suite',
      (t) async {
        final port = Announcements();
        // Use the same explicit owner for this entry; it is not owned by the entry.
        final borrowed = CommunityAnnouncementsController(port, target);
        addTearDown(borrowed.dispose);
        addTearDown(port.changes.close);
        final live = await mount(
          t,
          CommunityAnnouncementEntry(
            port: port,
            targetRef: target,
            controller: borrowed,
          ),
          suite,
          width: 900,
        );
        await action(t, const Key('community-announcement-entry'), 'keyboard');
        await action(t, const Key('announcement-withdraw'), 'keyboard');
        live.change(() => live.visible = false);
        await settleCommunityImages(t);
        expect(find.byType(CommunityAnnouncementsDialog), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(borrowed.active, true);
        expect(port.writes, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'announcement embedded editor retires its secondary route on departure $suite',
      (t) async {
        final port = Announcements();
        final model = CommunityAnnouncementsController(port, target);
        addTearDown(model.dispose);
        addTearDown(port.changes.close);
        await model.refresh();
        final live = await mount(
          t,
          CommunityAnnouncementsDialog(model: model, embedded: true),
          suite,
          width: 850,
        );
        await action(t, const Key('announcement-withdraw'), 'pointer');
        live.change(() => live.visible = false);
        await settleCommunityImages(t);
        expect(find.byType(AlertDialog), findsNothing);
        expect(model.active, true);
        expect(port.writes, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final embedded in [false, true]) {
      testWidgets(
        'announcement owner replacement detaches old private routes $suite embedded=$embedded',
        (t) async {
          final oldPort = Announcements(), nextPort = Announcements();
          final oldOwner = CommunityAnnouncementsController(oldPort, target);
          final nextOwner = CommunityAnnouncementsController(nextPort, target);
          addTearDown(oldPort.changes.close);
          addTearDown(nextPort.changes.close);
          addTearDown(oldOwner.dispose);
          addTearDown(nextOwner.dispose);
          await nextOwner.refresh();
          if (embedded) {
            nextOwner.startEditing();
            nextOwner.updateDraft('New owner draft', 'New owner content');
          }
          var owner = oldOwner;
          late StateSetter rebuild;
          await mount(
            t,
            StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return CommunityAnnouncementEntry(
                  port: owner == oldOwner ? oldPort : nextPort,
                  targetRef: target,
                  controller: owner,
                  embedded: embedded,
                );
              },
            ),
            suite,
            width: 900,
          );
          if (!embedded) {
            await action(
              t,
              const Key('community-announcement-entry'),
              'keyboard',
            );
          }
          await action(t, const Key('announcement-withdraw'), 'keyboard');
          rebuild(() => owner = nextOwner);
          await settleCommunityImages(t);
          expect(
            find.byKey(const Key('announcement-confirm-accept')),
            findsNothing,
          );
          expect(oldOwner.active, true);
          expect(nextOwner.active, true);
          expect(oldPort.writes, isEmpty);
          expect(nextPort.writes, isEmpty);
          if (!embedded) {
            expect(find.byType(CommunityAnnouncementsDialog), findsNothing);
            await action(
              t,
              const Key('community-announcement-entry'),
              'keyboard',
            );
          } else {
            expect(
              t
                  .widget<TextField>(
                    find.byKey(const Key('announcement-title')),
                  )
                  .controller!
                  .text,
              'New owner draft',
            );
          }
          oldPort.changes.add(null);
          await settleCommunityImages(t);
          expect(find.byType(CommunityAnnouncementsDialog), findsOneWidget);
          expect(
            t
                .widget<CommunityAnnouncementsDialog>(
                  find.byType(CommunityAnnouncementsDialog),
                )
                .model,
            same(nextOwner),
          );
          expect(nextOwner.active, true);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'announcement editor cancels draft leaving and uses live reduce setting $suite',
      (t) async {
        final port = Announcements();
        addTearDown(port.changes.close);
        final live = await mount(
          t,
          CommunityAnnouncementEntry(port: port, targetRef: target),
          suite,
          width: 900,
        );
        await action(t, const Key('community-announcement-entry'), 'keyboard');
        await action(t, const Key('announcement-edit'), 'pointer');
        await draft(t, title: 'Retained draft');
        final state = t.state<CommunityAnnouncementsDialogState>(
              find.byType(CommunityAnnouncementsDialog),
            ),
            editor = t
                .widget<TextField>(find.byKey(const Key('announcement-title')))
                .controller;
        await action(
          t,
          const Key('announcement-close'),
          'pointer',
          settle: false,
        );
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        final route =
            ModalRoute.of(
                  t.element(
                    find.byKey(const Key('announcement-confirm-cancel')),
                  ),
                )!
                as StarBridgeDialogRoute;
        expect(route.animation!.value, 1);
        await action(t, const Key('announcement-confirm-cancel'), 'keyboard');
        expect(state.title.text, 'Retained draft');
        expect(
          t
              .widget<TextField>(find.byKey(const Key('announcement-title')))
              .controller,
          same(editor),
        );
        expect(port.writes, isEmpty);
        await action(t, const Key('announcement-close'), 'keyboard');
        await action(t, const Key('announcement-confirm-accept'), 'keyboard');
        expect(find.byType(CommunityAnnouncementsDialog), findsNothing);
        expect(port.writes, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('ordinary announcement readers have no writer targets $suite', (
      t,
    ) async {
      final port = Announcements()..allowed = false;
      addTearDown(port.changes.close);
      await entry(t, port, suite, 'pointer');
      expect(find.byKey(const Key('announcement-create')), findsNothing);
      expect(find.byKey(const Key('announcement-edit')), findsNothing);
      expect(find.byKey(const Key('announcement-withdraw')), findsNothing);
      expect(port.writes, isEmpty);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      'unknown announcement cannot auto retry and review is explicit $suite',
      (t) async {
        final port = Announcements()
          ..outcome = const CommunityAnnouncementOutcome(
            'unknown',
            error: 'outcomeUnknown',
          );
        addTearDown(port.changes.close);
        final model = await entry(t, port, suite, 'pointer');
        await action(t, const Key('announcement-create'), 'pointer');
        await draft(t);
        await action(t, const Key('announcement-save'), 'keyboard');
        expect(port.writes.length, 1);
        expect(model.uncertain, true);
        expect(
          button(t, const Key('announcement-review-unknown')).onActivate,
          isNull,
        );
        await action(t, const Key('announcement-refresh'), 'pointer');
        await action(t, const Key('announcement-review-unknown'), 'pointer');
        await action(t, const Key('announcement-confirm-cancel'), 'keyboard');
        expect(model.uncertain, true);
        expect(port.writes.length, 1);
        await action(t, const Key('announcement-review-unknown'), 'pointer');
        await action(t, const Key('announcement-confirm-accept'), 'keyboard');
        expect(model.uncertain, false);
        expect(port.writes.length, 1);
        expect(model.title, 'Updated title');
        port.outcome = null;
        await action(t, const Key('announcement-save'), 'keyboard');
        expect(port.writes.length, 2);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'announcement refresh revokes private confirmation without new write $suite',
      (t) async {
        final port = Announcements();
        addTearDown(port.changes.close);
        final model = await entry(t, port, suite, 'keyboard');
        await action(t, const Key('announcement-withdraw'), 'keyboard');
        port.failure = 'notAllowed';
        await model.refresh();
        await settleCommunityImages(t);
        expect(
          find.byKey(const Key('announcement-confirm-accept')),
          findsNothing,
        );
        expect(port.writes, isEmpty);
        expect(model.canManage, false);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'pending announcement save locks and late account answer stays private $suite',
      (t) async {
        final port = Announcements()
          ..heldWrite = Completer<CommunityAnnouncementOutcome>();
        addTearDown(port.changes.close);
        var changed = 0;
        await mount(
          t,
          CommunityAnnouncementEntry(
            port: port,
            targetRef: target,
            onChanged: () async {
              changed++;
            },
          ),
          suite,
          width: 900,
        );
        await action(t, const Key('community-announcement-entry'), 'pointer');
        await action(t, const Key('announcement-create'), 'pointer');
        await draft(t);
        await action(
          t,
          const Key('announcement-save'),
          'keyboard',
          settle: false,
        );
        expect(port.writes.length, 1);
        expect(button(t, const Key('announcement-save')).onActivate, isNull);
        port.changes.add(null);
        await t.pump();
        await t.pump();
        port.heldWrite!.complete(
          const CommunityAnnouncementOutcome('accepted', revision: 31),
        );
        await settleCommunityImages(t);
        expect(find.byType(CommunityAnnouncementsDialog), findsNothing);
        expect(changed, 0);
        expect(port.writes.length, 1);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('history paging and details retry remain readonly $suite', (
      t,
    ) async {
      final port = Announcements()..addHistory(21);
      addTearDown(port.changes.close);
      final model = await entry(t, port, suite, 'pointer');
      await t.scrollUntilVisible(
        find.byKey(const Key('announcement-more')),
        500,
        scrollable: find
            .descendant(
              of: find.byType(CommunityAnnouncementsDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await action(t, const Key('announcement-more'), 'keyboard');
      expect(model.history.length, 21);
      expect(port.reads.last, (20, 30));
      port.detailFailure = 'unavailable';
      await t.scrollUntilVisible(
        find.byKey(const Key('announcement-details-$itemRef')),
        -500,
        scrollable: find
            .descendant(
              of: find.byType(CommunityAnnouncementsDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await action(t, const Key('announcement-details-$itemRef'), 'keyboard');
      expect(
        find.byKey(const Key('announcement-detail-retry')),
        findsOneWidget,
      );
      port.detailFailure = null;
      await action(t, const Key('announcement-detail-retry'), 'keyboard');
      expect(find.byKey(const Key('announcement-detail-retry')), findsNothing);
      expect(port.writes, isEmpty);
      await action(t, const Key('announcement-back'), 'keyboard');
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      'unknown log deletion consumes selection requires new read and reference $suite',
      (t) async {
        final port = Logs()
          ..outcome = const CommunityLogOutcome(
            'unknown',
            error: 'outcomeUnknown',
          );
        addTearDown(port.changes.close);
        await mount(
          t,
          CommunityLogsDialog(port: port, targetRef: target, embedded: true),
          suite,
          width: 850,
        );
        final old = port.firstRef;
        await action(t, Key('log-delete-$old'), 'pointer');
        await action(t, const Key('log-confirm-delete'), 'keyboard');
        expect(port.writes.length, 1);
        expect(find.byKey(const Key('log-confirm-delete')), findsNothing);
        await action(t, const Key('log-reload'), 'keyboard');
        expect(port.writes.length, 1);
        expect(port.firstRef, isNot(old));
        port.outcome = const CommunityLogOutcome('accepted');
        await action(t, Key('log-delete-${port.firstRef}'), 'pointer');
        await action(t, const Key('log-confirm-delete'), 'keyboard');
        expect(port.writes.length, 2);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'pending log deletion cannot repeat and identity clears late state $suite',
      (t) async {
        final port = Logs()..pending = Completer<CommunityLogOutcome>();
        addTearDown(port.changes.close);
        await mount(
          t,
          CommunityLogsDialog(port: port, targetRef: target, embedded: true),
          suite,
          width: 850,
        );
        await action(t, Key('log-delete-${port.firstRef}'), 'pointer');
        await action(
          t,
          const Key('log-confirm-delete'),
          'keyboard',
          settle: false,
        );
        expect(port.writes.length, 1);
        expect(button(t, const Key('log-confirm-delete')).onActivate, isNull);
        port.changes.add(null);
        await t.pump();
        await t.pump();
        port.pending!.complete(const CommunityLogOutcome('accepted'));
        await settleCommunityImages(t);
        expect(find.text('Visible detail'), findsNothing);
        expect(port.writes.length, 1);
        expect(find.text('日志已删除'), findsNothing);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'log native search text survives palette but clears invalidation $suite',
      (t) async {
        final port = Logs();
        addTearDown(port.changes.close);
        final live = await mount(
          t,
          CommunityLogsDialog(port: port, targetRef: target, embedded: true),
          suite,
          width: 850,
        );
        await t.enterText(
          find.byKey(const Key('log-search')),
          'Unsubmitted query',
        );
        await t.pump();
        final editor = t
            .widget<TextField>(find.byKey(const Key('log-search')))
            .controller;
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        expect(
          t.widget<TextField>(find.byKey(const Key('log-search'))).controller,
          same(editor),
        );
        expect(editor!.text, 'Unsubmitted query');
        expect(port.reads, 1);
        port.changes.add(null);
        await settleCommunityImages(t);
        expect(editor.text, isEmpty);
        expect(find.byKey(const Key('log-search')), findsNothing);
        expect(port.writes, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('read-only log snapshot exposes no deletion target $suite', (
      t,
    ) async {
      final port = Logs()..allowed = false;
      addTearDown(port.changes.close);
      await mount(
        t,
        CommunityLogsDialog(port: port, targetRef: target, embedded: true),
        suite,
        width: 850,
      );
      expect(find.byKey(Key('log-delete-${port.firstRef}')), findsNothing);
      expect(port.writes, isEmpty);
      await t.pumpWidget(const SizedBox());
    });
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('announcement body complete rendered text review $suite', (
      t,
    ) async {
      final port = Announcements(), capture = GlobalKey();
      addTearDown(port.changes.close);
      await mount(
        t,
        CommunityAnnouncementEntry(
          port: port,
          targetRef: target,
          expanded: true,
        ),
        suite,
        width: 800,
        capture: capture,
      );
      final body = find.widgetWithText(SelectableText, '出发前请检查补给，并在组织聊天中确认分工。'),
          rect = t.getRect(body);
      await t.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(),
            png = await image.toByteData(format: ImageByteFormat.png),
            raw = (await image.toByteData(format: ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        var foreground = 0;
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
          for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
            final i = (y * image.width + x) * 4;
            if (raw[i] > 90 && raw[i + 1] > 100 && raw[i + 2] > 110) {
              foreground++;
            }
          }
        }
        expect(foreground, greaterThan(20));
        Directory('build/reviews/interaction-batch3an')
            .createSync(recursive: true);
        File(
          'build/reviews/interaction-batch3an/${suite.name}-announcement.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
      await t.pumpWidget(const SizedBox());
    });
  }
}
