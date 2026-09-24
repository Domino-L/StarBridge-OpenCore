import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_snapshot.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_coordinator.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_app.dart';
import 'package:starbridge_flutter/app/tray/tray_star_arrival.dart';
import 'package:starbridge_flutter/app/tray/tray_quick_panel.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';

const sample = TraySurfaceSnapshot(
  scope: 4,
  state: TrayQuickPanelState(runtime: TrayRuntimeState.running),
  presence: PresenceVisibility.invisible,
  canChangePresence: true,
  canToggleOverlay: true,
  reduceMotion: true,
);
Future<Object?> native(
  TestWidgetsFlutterBinding binding,
  String channel,
  String method,
  Object? args,
) async {
  final result = Completer<Object?>();
  await binding.defaultBinaryMessenger.handlePlatformMessage(
    channel,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (data) {
      try {
        result.complete(
          data == null
              ? null
              : const StandardMethodCodec().decodeEnvelope(data),
        );
      } catch (e, stack) {
        result.completeError(e, stack);
      }
    },
  );
  return result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'opening tray refreshes facts without executing an overlay action',
    (tester) async {
      const channel = MethodChannel('starbridge/tray-primary');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => null,
      );
      final value = ValueNotifier(sample);
      var refreshes = 0, writes = 0;
      final coordinator = TraySurfaceCoordinator(
        snapshot: value,
        refresh: () async {
          refreshes++;
        },
        toggleOverlay: () async {
          writes++;
        },
      );
      await native(tester.binding, channel.name, 'refresh', null);
      expect(refreshes, 1);
      expect(writes, 0);
      coordinator.dispose();
      await tester.pump();
      value.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );
  testWidgets('white star lands at actual logo and finishes once', (
    tester,
  ) async {
    final logo = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: TrayStarArrival(
            logoKey: logo,
            child: SizedBox(
              width: 336,
              height: 450,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(key: logo, width: 36, height: 36),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    final star = find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_ArrivalStar',
    );
    expect(star, findsOneWidget);
    final dynamic painter = tester.widget<CustomPaint>(star).painter;
    expect(painter.target, const Offset(18, 18));
    await tester.pump(const Duration(milliseconds: 300));
    expect(star, findsNothing);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
  });
  test('display projection round trips and rejects invalid states', () {
    expect(
      TraySurfaceSnapshot.parse(sample.toMap()).presence,
      PresenceVisibility.invisible,
    );
    expect(
      () => TraySurfaceSnapshot.parse({...sample.toMap(), 'mode': 'invented'}),
      throwsFormatException,
    );
    expect(sample.toMap().keys, isNot(contains('accountContext')));
  });
  testWidgets(
    'coordinator rejects stale context and duplicate pending action',
    (tester) async {
      const channel = MethodChannel('starbridge/tray-primary');
      final seen = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        seen.add(call.method);
        return null;
      });
      final value = ValueNotifier(sample);
      final pending = Completer<void>();
      var called = 0;
      final coordinator = TraySurfaceCoordinator(
        snapshot: value,
        setPresence: (_) async {
          called++;
          await pending.future;
        },
      );
      await tester.pump();
      await expectLater(
        native(tester.binding, channel.name, 'action', {
          'scope': 3,
          'action': 'presence',
          'mode': 'online',
        }),
        throwsA(isA<PlatformException>()),
      );
      final changing = native(tester.binding, channel.name, 'action', {
        'scope': 4,
        'action': 'presence',
        'mode': 'online',
      });
      await tester.pump();
      await expectLater(
        native(tester.binding, channel.name, 'action', {
          'scope': 4,
          'action': 'presence',
          'mode': 'inGame',
        }),
        throwsA(isA<PlatformException>()),
      );
      expect(called, 1);
      pending.complete();
      await changing;
      coordinator.dispose();
      await tester.pump();
      expect(seen, containsAll(['configure', 'detach']));
      value.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );
  for (final keyboard in [false, true]) {
    testWidgets(
      'star arrival immediate for reduced motion or keyboard=$keyboard',
      (tester) async {
        final logo = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: TrayStarArrival(
              logoKey: logo,
              reduceMotion: !keyboard,
              keyboard: keyboard,
              child: SizedBox(
                width: 336,
                height: 450,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(key: logo, width: 36, height: 36),
                ),
              ),
            ),
          ),
        );
        expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }
  testWidgets(
    'native height follows content and can grow beyond a short viewport',
    (tester) async {
      const channel = MethodChannel('starbridge/tray-surface');
      final calls = <MethodCall>[];
      await tester.binding.setSurfaceSize(const Size(336, 552));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return call.method == 'ready'
            ? {...sample.toMap(), 'opening': 1}
            : null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(const TraySurfaceApp());
      await tester.pumpAndSettle();
      int height() =>
          (calls.lastWhere((c) => c.method == 'layout').arguments
                  as Map)['height']
              as int;
      final initial = height();
      expect(
        initial,
        tester.getSize(find.byType(TrayQuickPanel)).height.ceil(),
      );
      expect(initial, lessThan(552));
      expect(
        calls.indexWhere((c) => c.method == 'layout'),
        lessThan(calls.indexWhere((c) => c.method == 'painted')),
      );
      await tester.binding.setSurfaceSize(const Size(336, 240));
      await native(tester.binding, channel.name, 'snapshot', {
        ...sample.toMap(),
        'opening': 1,
        'version': '1.0 test',
        'scene': 'A scene whose name takes a second line at this width',
      });
      await tester.pumpAndSettle();
      expect(height(), greaterThan(initial));
      expect(
        height(),
        tester.getSize(find.byType(TrayQuickPanel)).height.ceil(),
      );
      expect(
        calls.where((c) => c.method == 'painted'),
        hasLength(1),
        reason: 'Background resizing must not replay opening or reclaim focus',
      );
      await tester.ensureVisible(find.byKey(const Key('tray-exit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tray-exit')).hitTestable(), findsOneWidget);
      await native(tester.binding, channel.name, 'snapshot', {
        ...sample.toMap(),
        'opening': 2,
      });
      await tester.pumpAndSettle();
      expect(height(), initial);
      expect(calls.where((c) => c.method == 'painted'), hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'auxiliary entry consumes shared invisible state and dismisses with Escape',
    (tester) async {
      const channel = MethodChannel('starbridge/tray-surface');
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return call.method == 'ready'
            ? {...sample.toMap(), 'opening': 1}
            : null;
      });
      await tester.pumpWidget(const TraySurfaceApp());
      await tester.pumpAndSettle();
      expect(find.text('隐身'), findsOneWidget);
      expect(calls, contains('painted'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(calls, contains('dismiss'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );
}
