import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/settings/gameplay_data_export_panel.dart';
import 'package:starbridge_flutter/features/settings/gameplay_data_export_dialog.dart';
import 'package:starbridge_flutter/features/settings/gameplay_data_export_port.dart';
import 'package:starbridge_flutter/features/settings/gameplay_data_export_copy.dart';
import 'package:starbridge_flutter/features/settings/player_activity_dialog.dart';
import 'package:starbridge_flutter/features/settings/player_activity_controller.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_activity.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import '../../features/settings/player_activity_test.dart' as player;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3bb_test.dart' show Peer, projection;

class ExportPort implements GameplayDataExportPort {
  int calls = 0, cancels = 0;
  GameplayExportOutcome outcome = GameplayExportOutcome.saved;
  Completer<GameplayExportOutcome>? held;
  bool fail = false;
  final origins = <InteractionSource>[];
  @override
  Future<GameplayExportOutcome> export(String locale) async {
    calls++;
    origins.add(currentStarBridgeActivationSource);
    if (fail) throw StateError('lost reply');
    return held == null ? outcome : held!.future;
  }

  @override
  void cancel() {
    cancels++;
  }
}

StarBridgeActionButton action(WidgetTester t, String key) => t.widget(
  find
      .ancestor(
        of: find.byKey(Key(key)),
        matching: find.byType(StarBridgeActionButton),
      )
      .first,
);
Future<void> activate(WidgetTester t, String key, String source) async {
  final target = find.byKey(Key(key));
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    final text = find.descendant(of: target, matching: find.byType(Text)).first;
    Focus.of(t.element(text)).requestFocus();
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final node = t.getSemantics(target);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  }
  await t.pump();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite current bootstrap invalidation cancels old export lease',
      (t) async {
        final peer = Peer()..holdExports = true;
        final account = ValueNotifier(projection());
        addTearDown(peer.close);
        addTearDown(account.dispose);
        await mount(
          t,
          GameplayDataExportDialog(account: account, session: peer.session),
          suite,
        );
        await activate(t, 'gameplay-data-export-start', 'pointer');
        final pending = peer.held.single;
        await peer.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'bootstrap.invalidated',
            sessionGeneration: 4,
            sequence: 1,
            payload: const {},
          ),
        );
        await t.pump();
        await t.pumpAndSettle();
        expect(peer.count('account.getCurrent'), 2);
        expect(peer.count('bridge.cancel'), greaterThan(0));
        await peer.reply(pending);
        await t.pumpAndSettle();
        expect(find.text('游玩数据已导出。'), findsNothing);
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final outcome in GameplayExportOutcome.values) {
      testWidgets('$suite export $outcome stays distinct from saved', (
        t,
      ) async {
        final port = ExportPort()..outcome = outcome;
        await mount(t, GameplayDataExportPanel(port: port), suite);
        await activate(t, 'gameplay-data-export-start', 'pointer');
        await t.pumpAndSettle();
        expect(port.calls, 1);
        final copy = gameplayExportCopy(
          t.element(find.byType(GameplayDataExportPanel)),
          outcome.name,
        );
        expect(find.text(copy), findsOneWidget);
        expect(
          find.text('游玩数据已导出。'),
          outcome == GameplayExportOutcome.saved
              ? findsOneWidget
              : findsNothing,
        );
        final frame = t.widget<SuiteBusyFrame>(find.byType(SuiteBusyFrame));
        expect(
          frame.doneToken,
          outcome == GameplayExportOutcome.cancelled ? 0 : 1,
        );
        if (outcome != GameplayExportOutcome.cancelled) {
          expect(
            frame.doneOutcome,
            outcome == GameplayExportOutcome.saved
                ? TaskOutcome.success
                : TaskOutcome.failure,
          );
        }
        await t.pumpWidget(const SizedBox());
      });
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite export $source input arrives once with source', (
        t,
      ) async {
        final handle = t.ensureSemantics();
        final port = ExportPort();
        await mount(t, GameplayDataExportPanel(port: port), suite);
        await activate(t, 'gameplay-data-export-start', source);
        await t.pumpAndSettle();
        expect(port.calls, 1);
        expect(
          port.origins.single,
          source == 'pointer'
              ? InteractionSource.pointer
              : InteractionSource.keyboard,
        );
        await t.pumpWidget(const SizedBox());
        handle.dispose();
      });
    }
    testWidgets('$suite held export stops FX live and fences cached old port', (
      t,
    ) async {
      final a = ExportPort()..held = Completer<GameplayExportOutcome>(),
          b = ExportPort();
      var current = a;
      late StateSetter update;
      final live = await mount(
        t,
        StatefulBuilder(
          builder: (_, s) {
            update = s;
            return GameplayDataExportPanel(port: current);
          },
        ),
        suite,
      );
      final old = action(t, 'gameplay-data-export-start').onActivate!;
      await activate(t, 'gameplay-data-export-start', 'pointer');
      old(InteractionSource.pointer);
      await t.pump();
      expect(a.calls, 1);
      live.change(() => live.reduce = true);
      await t.pump();
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      update(() => current = b);
      await t.pump();
      old(InteractionSource.pointer);
      a.held!.complete(GameplayExportOutcome.saved);
      await t.pumpAndSettle();
      expect(b.calls, 0);
      expect(a.cancels, 1);
      expect(find.text('游玩数据已导出。'), findsNothing);
      b.fail = true;
      await activate(t, 'gameplay-data-export-start', 'pointer');
      await t.pumpAndSettle();
      expect(find.text('未能确认导出结果，请检查所选文件夹。'), findsOneWidget);
      b.fail = false;
      await activate(t, 'gameplay-data-export-start', 'pointer');
      await t.pumpAndSettle();
      expect(b.calls, 2);
      expect(find.text('游玩数据已导出。'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      '$suite player position draft preserves failed save and old lease',
      (t) async {
        var writes = 0;
        var fail = true;
        final c = PlayerActivityController((name, payload) async {
          if (name == 'playerActivity.save') {
            writes++;
            if (fail) throw StateError('unconfirmed');
            return player.data()
              ..['position'] = payload['position']
              ..['offline'] = payload['offline'];
          }
          return player.data();
        }, generation: () => 4);
        addTearDown(c.dispose);
        late PrivacyPageDrafts group;
        await mount(
          t,
          NotificationEditorFrame(
            owner: Object(),
            child: Builder(
              builder: (context) {
                group = NotificationDraftScope.of(context)!;
                return PlayerActivityConnectedPanel(
                  controller: c,
                  showClose: false,
                );
              },
            ),
          ),
          suite,
        );
        final panel = t.widget<PlayerActivityNotificationPanel>(
          find.byType(PlayerActivityNotificationPanel),
        );
        await panel.onSave(
          panel.settings.copyWith(
            playerActivity: panel.settings.playerActivity.copyWith(
              notifyOffline: true,
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(writes, 0);
        expect(group.dirty, true);
        await activate(t, 'notification-save', 'pointer');
        await t.pumpAndSettle();
        expect(group.failed, true);
        expect(group.dirty, true);
        expect(writes, 1);
        fail = false;
        await activate(t, 'player-activity-reload', 'pointer');
        await t.pumpAndSettle();
        await activate(t, 'notification-save', 'pointer');
        await t.pumpAndSettle();
        expect(writes, 2);
        expect(group.dirty, false);
        group.discard();
        await t.pump();
        expect(await panel.onSave(panel.settings), false);
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final result in ['submitted', 'suppressed', 'unavailable']) {
      testWidgets('$suite player test $result has truthful feedback', (
        t,
      ) async {
        var tests = 0;
        final c = PlayerActivityController((name, payload) async {
          if (name == 'playerActivity.test') {
            tests++;
            if (result == 'unavailable') throw StateError('no output');
            return {
              'schemaVersion': 1,
              'submitted': result == 'submitted',
              'reason': result,
            };
          }
          return player.data();
        }, generation: () => 4);
        addTearDown(c.dispose);
        await mount(
          t,
          PlayerActivityConnectedPanel(controller: c, showClose: false),
          suite,
        );
        final before = t
            .widget<SuiteBusyFrame>(find.byType(SuiteBusyFrame))
            .doneToken;
        await activate(t, 'player-activity-test', 'pointer');
        await t.pumpAndSettle();
        expect(tests, 1);
        expect(c.testResult, result);
        expect(c.canEdit, true);
        if (result == 'suppressed') {
          expect(
            t.widget<SuiteBusyFrame>(find.byType(SuiteBusyFrame)).doneToken,
            before,
          );
          expect(find.text('测试提醒已发送。'), findsNothing);
        }
        if (result == 'unavailable') {
          expect(
            t.widget<SuiteBusyFrame>(find.byType(SuiteBusyFrame)).doneOutcome,
            TaskOutcome.failure,
          );
        }
        await t.pumpWidget(const SizedBox());
      });
    }
    testWidgets(
      '$suite export binding retires old delayed resolution and invalidation',
      (t) async {
        final a = Peer('old')..holdReads = true, b = Peer('new');
        final account = ValueNotifier(projection());
        addTearDown(a.close);
        addTearDown(b.close);
        addTearDown(account.dispose);
        var current = a.session;
        late StateSetter update;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, s) {
              update = s;
              return GameplayDataExportDialog(
                account: account,
                session: current,
              );
            },
          ),
          suite,
        );
        final pending = a.held.single;
        update(() => current = b.session);
        await t.pump();
        await t.pumpAndSettle();
        expect(b.count('account.getCurrent'), 1);
        await a.reply(pending);
        await t.pump();
        await t.pumpAndSettle();
        await a.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'event',
            name: 'bootstrap.invalidated',
            sessionGeneration: 4,
            sequence: 1,
            payload: const {},
          ),
        );
        await t.pump();
        await t.pumpAndSettle();
        expect(b.count('account.getCurrent'), 1);
        await activate(t, 'gameplay-data-export-start', 'pointer');
        await t.pumpAndSettle();
        expect(a.count('gameplayTime.export'), 0);
        expect(b.count('gameplayTime.export'), 1);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite open export route follows reduction and keyboard close',
      (t) async {
        final peer = Peer(), account = ValueNotifier(projection());
        addTearDown(peer.close);
        addTearDown(account.dispose);
        late BuildContext caller;
        final live = await mount(
          t,
          Builder(
            builder: (context) {
              caller = context;
              return const Text('Open');
            },
          ),
          suite,
        );
        final pending = showGameplayDataExportDialog(
          caller,
          account,
          peer.session,
        );
        await t.pump();
        await t.pumpAndSettle();
        final route =
            ModalRoute.of(
                  t.element(
                    find.byKey(
                      const Key('settings-entry-local-data-management'),
                    ),
                  ),
                )!
                as StarBridgeDialogRoute;
        live.change(() => live.reduce = true);
        await t.pump();
        await t.pump();
        expect(route.transitionDuration, Duration.zero);
        await activate(t, 'settings-entry-close', 'keyboard');
        await t.pump();
        await pending;
        expect(
          find.byKey(const Key('settings-entry-local-data-management')),
          findsNothing,
        );
        expect(peer.count('gameplayTime.export'), 0);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final suite in [
    InteractionSuite.rail,
    InteractionSuite.scan,
    InteractionSuite.glow,
  ]) {
    testWidgets('$suite export review frames', (t) async {
      final capture = GlobalKey(), peer = Peer()..holdExports = true;
      final account = ValueNotifier(projection());
      addTearDown(peer.close);
      addTearDown(account.dispose);
      late BuildContext caller;
      final live = await mount(
        t,
        Builder(
          builder: (context) {
            caller = context;
            return const Text('Open');
          },
        ),
        suite,
        width: 1000,
        capture: capture,
      );
      final pending = showGameplayDataExportDialog(
        caller,
        account,
        peer.session,
      );
      await t.pump();
      await t.pumpAndSettle();
      Future<void> save(String phase) async {
        await t.pump();
        final titleRect = t.getRect(find.text('本地数据管理'));
        await t.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final raw = await image.toByteData(format: ImageByteFormat.rawRgba);
          var bright = 0;
          for (
            var y = titleRect.top.ceil();
            y < titleRect.bottom.floor();
            y++
          ) {
            for (
              var x = titleRect.left.ceil();
              x < titleRect.right.floor();
              x++
            ) {
              final offset = (y * image.width + x) * 4;
              final sum =
                  raw!.getUint8(offset) +
                  raw.getUint8(offset + 1) +
                  raw.getUint8(offset + 2);
              if (phase == 'light' ? sum < 300 : sum > 500) bright++;
            }
          }
          expect(
            bright,
            greaterThan(10),
            reason: '$suite $phase title glyphs must be painted',
          );
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          final dir = Directory('build/reviews/interaction-batch3bb');
          await dir.create(recursive: true);
          await File('${dir.path}/${suite.name}-$phase.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await activate(t, 'gameplay-data-export-start', 'pointer');
      await t.pump(const Duration(milliseconds: 100));
      await save('busy');
      peer.exportOutcome = 'unknown';
      await peer.reply(peer.held.single);
      await t.pump();
      await t.pump(const Duration(milliseconds: 80));
      await save('unknown');
      live.change(() => live.light = true);
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      await save('light');
      expect(peer.count('account.getCurrent'), 1);
      await activate(t, 'settings-entry-close', 'keyboard');
      await pending;
      await t.pumpWidget(const SizedBox());
    });
  }
}
