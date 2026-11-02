import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/presence/manual_presence_widgets.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_coordinator.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_snapshot.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_app.dart';
import 'package:starbridge_flutter/platform/window/menu_action_validation.dart';
import 'package:starbridge_flutter/app/tray/tray_quick_panel.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';

import '../../features/onboarding/connection_mode_test.dart'
    show ModePort, modeFact;
import '../tray_quick_panel_test.dart' show app;
import '../tray_surface_test.dart' show native;
import '../menu_overlay/menu_friends_session_test.dart' show Port;

void main() {
  testWidgets(
    'pending physical exit is observed until terminal receipt without another write',
    (tester) async {
      final port = ModePort(), mode = ConnectionModeController(port);
      final initialRead = mode.refresh();
      await tester.pump(const Duration(milliseconds: 1));
      await initialRead;
      final writing = mode.enterOffline();
      port.current = modeFact('switching');
      port.pending!.completeError(TimeoutException('Observer expired'));
      expect(await writing, false);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(mode.snapshot.state, ConnectionModeState.switching);
      port.current = modeFact('offline');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(mode.snapshot.isOffline, true);
      expect(port.writes, [4]);
      expect(mode.busy, false);
      final reads = port.reads;
      await tester.pump(const Duration(seconds: 8));
      expect(port.reads, reads);
      mode.dispose();
      await port.events.close();
    },
  );
  test('friends forwarding permits only bounded exact offline intent', () {
    const good = {
      'opening': 7,
      'action': 'offlineMode',
      'key': 'self1',
      'value': '',
    };
    expect(validMenuFriendsAction(good, 7), true);
    for (final bad in [
      {'opening': 6},
      {'action': 'offline'},
      {'action': 'offlineMode.extra'},
      {'value': 'offline'},
      {'key': 7},
      {'key': 'x' * 65},
    ]) {
      expect(validMenuFriendsAction({...good, ...bad}, 7), false);
    }
  });
  for (final sameScope in [false, true]) {
    testWidgets(
      'actual tray rejects delayed offline ack over newer projection sameScope=$sameScope',
      (tester) async {
        const channel = MethodChannel('starbridge/tray-surface');
        Map<String, Object?> projection(
          int scope,
          int revision,
          ConnectionModeState state,
        ) => TraySurfaceSnapshot(
          scope: scope,
          revision: revision,
          state: const TrayQuickPanelState(runtime: TrayRuntimeState.running),
          presence: PresenceVisibility.online,
          canChangePresence: true,
          connectionMode: state,
          canEnterOffline: state == ConnectionModeState.online,
          reduceMotion: true,
        ).toMap();
        final response = Completer<Object?>();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'ready') {
              return projection(7, 1, ConnectionModeState.online);
            }
            if (call.method == 'action') return response.future;
            return null;
          },
        );
        await tester.binding.setSurfaceSize(const Size(336, 650));
        await tester.pumpWidget(const TraySurfaceApp());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('tray-presence-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('manual-presence-offline')));
        await tester.pump();
        await tester.pump();
        await native(
          tester.binding,
          channel.name,
          'snapshot',
          projection(sameScope ? 7 : 8, 3, ConnectionModeState.online),
        );
        await tester.pump();
        response.complete(projection(7, 2, ConnectionModeState.offline));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const Key('manual-presence-self')))
              .data,
          isNot('离线'),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.binding.setSurfaceSize(null);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      },
    );
  }
  testWidgets('held initial tray receipt cannot replace a newer pushed owner', (
    tester,
  ) async {
    const channel = MethodChannel('starbridge/tray-surface');
    final ready = Completer<Object?>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      return call.method == 'ready' ? ready.future : null;
    });
    await tester.binding.setSurfaceSize(const Size(336, 650));
    await tester.pumpWidget(const TraySurfaceApp());
    await tester.pump();
    const online = TraySurfaceSnapshot(
      scope: 8,
      revision: 2,
      state: TrayQuickPanelState(runtime: TrayRuntimeState.running),
      presence: PresenceVisibility.online,
      connectionMode: ConnectionModeState.online,
      canEnterOffline: true,
      reduceMotion: true,
    );
    await native(tester.binding, channel.name, 'snapshot', online.toMap());
    await tester.pumpAndSettle();
    ready.complete(
      const TraySurfaceSnapshot(
        scope: 7,
        revision: 1,
        state: TrayQuickPanelState(runtime: TrayRuntimeState.running),
        connectionMode: ConnectionModeState.offline,
        reduceMotion: true,
      ).toMap(),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('manual-presence-self'))).data,
      isNot('离线'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets('offline is red only after actual confirmation $locale', (
      tester,
    ) async {
      final port = ModePort(), mode = ConnectionModeController(port);
      final source = ValueNotifier(
        const ManualPresenceSnapshot(
          scope: 7,
          confirmedMode: PresenceVisibility.online,
          canChange: true,
        ),
      );
      final control = ManualPresenceController(
        source: source,
        connectionMode: mode,
        write: (_, _) async {},
      );
      await tester.runAsync(mode.refresh);
      await tester.pumpWidget(
        app(
          SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ManualPresenceBadge(controller: control),
                ManualPresenceChoices(controller: control),
              ],
            ),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      final colors = tester
          .element(find.byType(ManualPresenceBadge))
          .tokens
          .colors;
      final item = find.byKey(const Key('manual-presence-offline'));
      expect(tester.widget<MenuItemButton>(item).onPressed, isNotNull);
      expect(
        find.text(
          locale.languageCode == 'en'
              ? 'Offline'
              : locale.countryCode == 'TW'
              ? '離線'
              : '离线',
        ),
        findsOneWidget,
      );
      expect(
        (tester
                    .widget<DecoratedBox>(
                      find.byKey(const ValueKey('manual-presence-dot-offline')),
                    )
                    .decoration
                as BoxDecoration)
            .color,
        colors.danger,
      );
      await tester.tap(item);
      await tester.pump();
      await tester.pump();
      expect(control.isOffline, false);
      expect(control.busy, true);
      expect(control.canChange, false);
      expect(tester.widget<MenuItemButton>(item).onPressed, isNull);
      port.pending!.complete(modeFact('offline'));
      await tester.pumpAndSettle();
      final label = tester.widget<Text>(
        find.byKey(const Key('manual-presence-self')),
      );
      expect(label.style!.color, colors.danger);
      expect(control.selfKey, 'presence.manualOffline');
      expect(port.writes, [4]);
      expect(menuPresenceColor('manualOffline'), colors.danger);
      expect(menuPresenceColor('offline'), colors.offline);
      expect(menuPresenceColor('invisible'), colors.offline);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      control.dispose();
      source.dispose();
      mode.dispose();
      await port.events.close();
    });
  }
  testWidgets(
    'friends offline validates exact self key and remains usable during directory read',
    (tester) async {
      final port = ModePort(), mode = ConnectionModeController(port);
      await tester.runAsync(mode.refresh);
      final source = ValueNotifier(const ManualPresenceSnapshot(scope: 7));
      final control = ManualPresenceController(
        source: source,
        connectionMode: mode,
      );
      final friends = Port(), views = <Map<String, Object?>>[];
      final lease = MenuFriendsSession(friends, views.add, presence: control);
      lease.show(true);
      var view = MenuFriendsView.parse(jsonEncode(views.last));
      expect(view.canEnterOffline, true);
      final oldKey = view.self!.key;
      lease.act('offlineMode', 'invented', '');
      lease.act('offlineMode', oldKey, 'offline');
      lease.act('presence', oldKey, 'offline');
      expect(port.writes, isEmpty);
      source.value = const ManualPresenceSnapshot(scope: 8);
      lease.act('offlineMode', oldKey, '');
      expect(port.writes, isEmpty);
      view = MenuFriendsView.parse(jsonEncode(views.last));
      lease.act('offlineMode', view.self!.key, '');
      expect(port.writes, [4]);
      lease.act('offlineMode', view.self!.key, '');
      expect(port.writes, [4]);
      port.pending!.complete(modeFact('offline'));
      await tester.pump();
      expect(
        MenuFriendsView.parse(jsonEncode(views.last)).self!.status,
        'presence.manualOffline',
      );
      friends.reads.single.completeError(StateError('Stopped read'));
      await tester.pump();
      lease.dispose();
      await tester.pump();
      control.dispose();
      source.dispose();
      mode.dispose();
      await port.events.close();
    },
  );
  testWidgets(
    'tray offline routes only fresh scope and never translates into presence',
    (tester) async {
      const channel = MethodChannel('starbridge/tray-primary');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => null,
      );
      var calls = 0, presenceWrites = 0;
      final pending = Completer<void>();
      final source = ValueNotifier(
        const TraySurfaceSnapshot(
          scope: 7,
          state: TrayQuickPanelState(runtime: TrayRuntimeState.running),
          connectionMode: ConnectionModeState.online,
          canEnterOffline: true,
        ),
      );
      final lease = TraySurfaceCoordinator(
        snapshot: source,
        enterOffline: () {
          calls++;
          return pending.future;
        },
        setPresence: (_) async {
          presenceWrites++;
        },
      );
      Future<Object?> command(int scope, {String? mode}) => native(
        tester.binding,
        channel.name,
        'action',
        {'action': 'offlineMode', 'scope': scope, 'mode': ?mode},
      );
      await expectLater(command(6), throwsA(isA<PlatformException>()));
      await expectLater(
        command(7, mode: 'offline'),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, 0);
      final writing = command(7);
      await tester.pump();
      expect(calls, 1);
      await expectLater(command(7), throwsA(isA<PlatformException>()));
      pending.complete();
      await writing;
      expect(presenceWrites, 0);
      lease.dispose();
      await tester.pump();
      source.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );
  test('tray mode projection retains backward compatibility but rejects contradictions', () {
    const sample = TraySurfaceSnapshot(
      scope: 7,
      state: TrayQuickPanelState(runtime: TrayRuntimeState.running),
      connectionMode: ConnectionModeState.offline,
    );
    expect(
      TraySurfaceSnapshot.parse(sample.toMap()).connectionMode,
      ConnectionModeState.offline,
    );
    final old = sample.toMap()
      ..remove('connectionMode')
      ..remove('canEnterOffline');
    expect(
      TraySurfaceSnapshot.parse(old).connectionMode,
      ConnectionModeState.unsupported,
    );
    expect(
      () => TraySurfaceSnapshot.parse({
        ...sample.toMap(),
        'canEnterOffline': true,
      }),
      throwsFormatException,
    );
    expect(
      () => TraySurfaceSnapshot.parse({
        ...sample.toMap(),
        'connectionMode': 'invented',
      }),
      throwsFormatException,
    );
    expect(
      () =>
          TraySurfaceSnapshot.parse({...sample.toMap(), 'canEnterOffline': 1}),
      throwsFormatException,
    );
  });
}
