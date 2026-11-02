import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_activity.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_common.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/features/settings/in_memory_notification_settings_adapter.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';

import 'interaction_batch3ae_test.dart' show mount;
import '../../features/friends/social_layout_test.dart' show loadFonts;

List<SemanticsNode> taps(SemanticsNode root) {
  final result = <SemanticsNode>[];
  void visit(SemanticsNode n) {
    if (n.getSemanticsData().hasAction(SemanticsAction.tap)) result.add(n);
    n.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return result;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite retry preserves input source and does not repeat', (
      t,
    ) async {
      var calls = 0;
      InteractionSource? source;
      await mount(
        t,
        NotificationFailureBanner(
            messageKey: 'settings.notification.loading',
          onRetry: () async {
            calls++;
            source = currentStarBridgeActivationSource;
          },
        ),
        suite,
      );
      final target = find.byKey(const Key('notification-failure-retry'));
      await t.tap(target);
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(source, InteractionSource.pointer);
      Focus.of(
        t.element(
          find.descendant(of: target, matching: find.byType(Text)).first,
        ),
      ).requestFocus();
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(calls, 2);
      expect(source, InteractionSource.keyboard);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      '$suite seven compact controls keep pointer keyboard and disabled contract',
      (t) async {
        final settings =
            InMemoryNotificationSettingsAdapter.forReview().current.settings!;
        var enabled = true;
        late StateSetter update;
        var calls = 0;
        final sources = <InteractionSource>[];
        await mount(
          t,
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return SingleChildScrollView(
                child: PlayerActivityNotificationPanel(
                  settings: settings.copyWith(
                    playerActivity: settings.playerActivity.copyWith(
                      enabled: true,
                    ),
                  ),
                  enabled: enabled,
                  onSave: (_) async {
                    calls++;
                    sources.add(currentStarBridgeActivationSource);
                    return true;
                  },
                ),
              );
            },
          ),
          suite,
        );
        for (final id in [
          'fleet',
          'friends',
          'room',
          'online',
          'offline',
          'game-start',
          'game-stop',
        ]) {
          final target = find.byKey(Key('notification-activity-$id'));
          await t.ensureVisible(target);
          await t.pumpAndSettle();
          await t.tapAt(t.getCenter(target));
          await t.pumpAndSettle();
          final pressable = find
              .ancestor(of: target, matching: find.byType(SuitePressable))
              .first;
          t.widget<SuitePressable>(pressable).focusNode!.requestFocus();
          await t.pumpAndSettle();
          await t.sendKeyEvent(LogicalKeyboardKey.space);
          await t.pumpAndSettle();
        }
        expect(calls, 14);
        expect(sources, [
          for (var i = 0; i < 7; i++) ...[
            InteractionSource.pointer,
            InteractionSource.keyboard,
          ],
        ]);
        update(() => enabled = false);
        await t.pump();
        for (final id in [
          'fleet',
          'friends',
          'room',
          'online',
          'offline',
          'game-start',
          'game-stop',
        ]) {
          final target = find.byKey(Key('notification-activity-$id'));
          final pressable = find
              .ancestor(of: target, matching: find.byType(SuitePressable))
              .first;
          expect(t.widget<SuitePressable>(pressable).onActivate, isNull);
        }
        expect(calls, 14);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('$suite keyboard leave and live reduction are source aware', (
      t,
    ) async {
      final owner = Object();
      late PrivacyPageDrafts group;
      final live = await mount(
        t,
        NotificationEditorFrame(
          owner: owner,
          child: Builder(
            builder: (context) {
              group = NotificationDraftScope.of(context)!;
              return const Text('Editor');
            },
          ),
        ),
        suite,
      );
      group.edit('a', 0, 1, (_) async => true);
      await t.pump();
      final result = runStarBridgeActivation<bool>(
        InteractionSource.keyboard,
        () => confirmNotificationLeave(owner),
      );
      await t.pump();
      final context = t.element(
        find.byKey(const Key('notification-leave-dialog')),
      );
      final route = ModalRoute.of(context)! as StarBridgeDialogRoute;
      expect(route.instant, true);
      live.change(() => live.reduce = true);
      await t.pump();
      await t.pump();
      expect(route.transitionDuration, Duration.zero);
      await t.tap(find.byKey(const Key('notification-leave-stay')));
      await t.pumpAndSettle();
      expect(await result, false);
      expect(group.dirty, true);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('$suite actual compact toggle exposes reader action', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      var calls = 0;
      final settings =
          InMemoryNotificationSettingsAdapter.forReview().current.settings!;
      await mount(
        t,
        SingleChildScrollView(
          child: PlayerActivityNotificationPanel(
            settings: settings.copyWith(
              playerActivity: settings.playerActivity.copyWith(enabled: true),
            ),
            enabled: true,
            onSave: (_) async {
              calls++;
              return true;
            },
          ),
        ),
        suite,
      );
      final target = find.byKey(const Key('notification-activity-fleet'));
      await t.ensureVisible(target);
      await t.pumpAndSettle();
      final pressable = find
          .ancestor(of: target, matching: find.byType(SuitePressable))
          .first;
      final nodes = taps(t.getSemantics(pressable));
      expect(nodes, hasLength(1));
      final node = nodes.single;
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
      t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await t.pump();
      expect(calls, 1);
      await t.pumpWidget(const SizedBox());
      handle.dispose();
    });
    testWidgets('$suite editor owner replacement rotates drafts and guard', (
      t,
    ) async {
      final a = Object(), b = Object();
      var owner = a;
      late StateSetter update;
      late PrivacyPageDrafts current;
      await mount(
        t,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return NotificationEditorFrame(
              owner: owner,
              child: Builder(
                builder: (context) {
                  current = NotificationDraftScope.of(context)!;
                  return const Text('Editor');
                },
              ),
            );
          },
        ),
        suite,
      );
      final old = current;
      old.edit('a', 0, 1, (_) async => true);
      update(() => owner = b);
      await t.pump();
      expect(notificationLeaveGuards[a], isNull);
      expect(notificationLeaveGuards[b], isNotNull);
      expect(current, isNot(same(old)));
      expect(current.dirty, false);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      '$suite disposing older same-owner editor preserves current guard',
      (t) async {
        final owner = Object();
        var first = true;
        late StateSetter update;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return Column(
                children: [
                  if (first)
                    Expanded(
                      key: const Key('first-slot'),
                      child: NotificationEditorFrame(
                        key: const Key('first'),
                        owner: owner,
                        child: const Text('First'),
                      ),
                    ),
                  Expanded(
                    key: const Key('second-slot'),
                    child: NotificationEditorFrame(
                      key: const Key('second'),
                      owner: owner,
                      child: const Text('Second'),
                    ),
                  ),
                ],
              );
            },
          ),
          suite,
        );
        final guard = notificationLeaveGuards[owner];
        expect(guard, isNotNull);
        update(() => first = false);
        await t.pump();
        expect(notificationLeaveGuards[owner], same(guard));
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('$suite initial loading respects reduced motion', (t) async {
      var loading = false;
      late StateSetter update;
      final live = await mount(
        t,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return loading ? const NotificationLoadingView() : const SizedBox();
          },
        ),
        suite,
      );
      update(() => loading = true);
      await t.pump();
      live.change(() => live.reduce = true);
      await t.pump();
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('$suite partial save retains only rejected entries and retry', (
      t,
    ) async {
      final owner = Object();
      late PrivacyPageDrafts group;
      var accepted = 0, rejected = 0;
      final answer = Completer<bool>();
      await mount(
        t,
        NotificationEditorFrame(
          owner: owner,
          child: Builder(
            builder: (context) {
              group = NotificationDraftScope.of(context)!;
              return const Text('Editor');
            },
          ),
        ),
        suite,
      );
      group.edit('accepted', 0, 1, (_) async {
        accepted++;
        return true;
      });
      group.edit('rejected', 0, 2, (_) {
        rejected++;
        return rejected == 1 ? answer.future : Future.value(true);
      });
      await t.pump();
      await t.tap(find.byKey(const Key('notification-save')));
      await t.pump();
      expect(accepted, 1);
      expect(rejected, 1);
      expect(group.saving, true);
      expect(await confirmNotificationLeave(owner), false);
      await t.tap(find.byKey(const Key('notification-save')));
      await t.pump();
      expect(rejected, 1);
      answer.complete(false);
      await t.pump();
      await t.pumpAndSettle();
      expect(group.failed, true);
      expect(group.dirty, true);
      expect(group.value('accepted', 0), 0);
      expect(group.value('rejected', 0), 2);
      await t.tap(find.byKey(const Key('notification-save')));
      await t.pump();
      await t.pumpAndSettle();
      expect(accepted, 1);
      expect(rejected, 2);
      expect(group.dirty, false);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('$suite owner change fences pending save and cached action', (
      t,
    ) async {
      var owner = Object();
      late StateSetter update;
      late PrivacyPageDrafts group;
      final answer = Completer<bool>();
      var calls = 0;
      await mount(
        t,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return NotificationEditorFrame(
              owner: owner,
              child: Builder(
                builder: (context) {
                  group = NotificationDraftScope.of(context)!;
                  return const Text('Editor');
                },
              ),
            );
          },
        ),
        suite,
      );
      group.edit('old', 0, 1, (_) {
        calls++;
        return answer.future;
      });
      await t.pump();
      final cached = t
          .widget<StarBridgeActionButton>(
            find
                .ancestor(
                  of: find.byKey(const Key('notification-save')),
                  matching: find.byType(StarBridgeActionButton),
                )
                .first,
          )
          .onActivate!;
      await t.tap(find.byKey(const Key('notification-save')));
      await t.pump();
      expect(calls, 1);
      update(() => owner = Object());
      await t.pump();
      final next = group;
      next.edit('new', 0, 3, (_) async {
        calls++;
        return true;
      });
      await t.pump();
      cached(InteractionSource.pointer);
      answer.complete(true);
      await t.pump();
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(next.dirty, true);
      expect(next.value('new', 0), 3);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('$suite leave stay discard and keyboard save keep contract', (
      t,
    ) async {
      final owner = Object();
      late PrivacyPageDrafts group;
      var writes = 0;
      await mount(
        t,
        NotificationEditorFrame(
          owner: owner,
          child: Builder(
            builder: (context) {
              group = NotificationDraftScope.of(context)!;
              return const Text('Editor');
            },
          ),
        ),
        suite,
      );
      void edit() => group.edit('a', 0, 1, (_) async {
        writes++;
        return true;
      });
      edit();
      await t.pump();
      final stay = confirmNotificationLeave(owner);
      await t.pump();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('notification-leave-stay')));
      await t.pumpAndSettle();
      expect(await stay, false);
      expect(group.dirty, true);
      final discard = confirmNotificationLeave(owner);
      await t.pump();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('notification-leave-discard')));
      await t.pumpAndSettle();
      expect(await discard, true);
      expect(group.dirty, false);
      expect(writes, 0);
      edit();
      await t.pump();
      final save = confirmNotificationLeave(owner);
      await t.pump();
      await t.pumpAndSettle();
      final button = find.byKey(const Key('notification-leave-save'));
      final text = find
          .descendant(of: button, matching: find.byType(Text))
          .first;
      Focus.of(t.element(text)).requestFocus();
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      await t.pumpAndSettle();
      expect(await save, true);
      expect(writes, 1);
      expect(group.dirty, false);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('$suite old leave dialog retires on owner change', (t) async {
      var owner = Object();
      late StateSetter update;
      late PrivacyPageDrafts group;
      await mount(
        t,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return NotificationEditorFrame(
              owner: owner,
              child: Builder(
                builder: (context) {
                  group = NotificationDraftScope.of(context)!;
                  return const Text('Editor');
                },
              ),
            );
          },
        ),
        suite,
      );
      group.edit('a', 0, 1, (_) async => true);
      await t.pump();
      final first = confirmNotificationLeave(owner);
      final second = confirmNotificationLeave(owner);
      await t.pump();
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('notification-leave-dialog')),
        findsOneWidget,
      );
      final cached = t
          .widget<StarBridgeActionButton>(
            find
                .ancestor(
                  of: find.byKey(const Key('notification-leave-discard')),
                  matching: find.byType(StarBridgeActionButton),
                )
                .first,
          )
          .onActivate!;
      update(() => owner = Object());
      await t.pump();
      await t.pump();
      cached(InteractionSource.pointer);
      await t.pump();
      expect(await first, false);
      expect(await second, false);
      expect(find.byKey(const Key('notification-leave-dialog')), findsNothing);
      expect(group.dirty, false);
      await t.pumpWidget(const SizedBox());
    });
  }
  for (final suite in [
    InteractionSuite.rail,
    InteractionSuite.scan,
    InteractionSuite.glow,
  ]) {
    testWidgets('$suite production notification editor review', (t) async {
      final capture = GlobalKey();
      final owner = Object();
      late PrivacyPageDrafts group;
      final answer = Completer<bool>();
      final base =
          InMemoryNotificationSettingsAdapter.forReview().current.settings!;
      var settings = base.copyWith(
        playerActivity: base.playerActivity.copyWith(enabled: true),
      );
      final live = await mount(
        t,
        NotificationEditorFrame(
          owner: owner,
          child: Builder(
            builder: (context) {
              group = NotificationDraftScope.of(context)!;
              return SingleChildScrollView(
                child: PlayerActivityNotificationPanel(
                  settings: group.value('activity', settings),
                  enabled: !group.saving,
                  onSave: (next) async {
                    group.edit('activity', settings, next, (value) async {
                      final ok = await answer.future;
                      if (ok) settings = value;
                      return ok;
                    });
                    return true;
                  },
                ),
              );
            },
          ),
        ),
        suite,
        capture: capture,
      );
      Future<void> save(String phase) async {
        await t.pump();
        await t.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          final dir = Directory('build/reviews/interaction-batch3az');
          await dir.create(recursive: true);
          await File('${dir.path}/${suite.name}-$phase.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      final compact = find.byKey(const Key('notification-activity-fleet'));
      await t.tapAt(t.getCenter(compact));
      await t.pump();
      await t.pump(const Duration(milliseconds: 80));
      await save('active');
      await t.tap(find.byKey(const Key('notification-save')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 150));
      await save('saving');
      answer.complete(false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 80));
      await save('rejected');
      live.change(() => live.light = true);
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      await save('light');
      await t.pumpWidget(const SizedBox());
    });
  }
}
