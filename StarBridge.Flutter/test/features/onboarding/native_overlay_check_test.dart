import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/onboarding/native_overlay_check_controller.dart';
import 'package:starbridge_flutter/features/onboarding/native_overlay_check_panel.dart';
import 'package:starbridge_flutter/features/onboarding/native_overlay_observation.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';

import 'native_overlay_observation_test.dart' show observationWire;

final class ObservationPort implements NativeOverlayObservationPort {
  final events = StreamController<void>.broadcast(sync: true);
  Map<String, Object?> raw = observationWire();
  int generation = 3, reads = 0;
  bool unavailable = false, fail = false;
  Completer<NativeOverlayObservation?>? pending;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<NativeOverlayObservation?> read() async {
    reads++;
    if (pending case final pending?) return pending.future;
    if (fail) throw StateError('synthetic failure');
    return unavailable
        ? null
        : NativeOverlayObservationWire.parse(raw, generation);
  }

  void hotkey(Map<String, Object?> change) {
    raw = {
      ...raw,
      'hotkey': {...raw['hotkey'] as Map<String, Object?>, ...change},
    };
  }
}

void main() {
  test(
    'registration and previously admitted inputs are not a new check',
    () async {
      final port = ObservationPort()
        ..raw = observationWire(count: 5, outcome: 'open');
      final c = NativeOverlayCheckController(port);
      addTearDown(c.dispose);
      expect(port.reads, 0);
      await c.refresh();
      expect(c.value.hotkey, NativeHotkeyCheck.notStarted);
      await c.startHotkeyCheck();
      await c.refresh();
      expect(c.value.hotkey, NativeHotkeyCheck.waiting);
      expect(c.value.busy, true);
      c.stopHotkeyCheck();
      expect(c.value.hotkey, NativeHotkeyCheck.notStarted);
      expect(c.value.busy, false);
    },
  );

  test('received input preserves failure, not fabricated success', () async {
    final port = ObservationPort();
    final c = NativeOverlayCheckController(port);
    addTearDown(c.dispose);
    await c.startHotkeyCheck();
    port.raw = observationWire(count: 1, outcome: 'failed');
    await c.refresh();
    expect(c.value.hotkey, NativeHotkeyCheck.observed);
    expect(c.value.observation!.hotkey.lastOutcome, 'failed');
    expect(c.value.observation!.nativeWindowVisible, false);
    expect(c.value.observation!.firstFrameCommitted, false);
    expect(c.value.busy, false);
  });

  for (final change in [
    'generation',
    'runtime',
    'binding',
    'configuration',
    'reset',
  ]) {
    test('observed input cannot survive a $change change', () async {
      final port = ObservationPort();
      final c = NativeOverlayCheckController(port);
      addTearDown(c.dispose);
      await c.startHotkeyCheck();
      port.raw = observationWire(count: 1, outcome: 'open');
      await c.refresh();
      switch (change) {
        case 'generation':
          port.generation++;
        case 'runtime':
          port.raw = {
            ...port.raw,
            'runtimeId': '22222222222222222222222222222222',
          };
        case 'binding':
          port.hotkey({'binding': 'Alt+F11'});
        case 'configuration':
          port.hotkey({'configurationRevision': 2});
        case 'reset':
          port.hotkey({'acceptedInputCount': 0, 'lastOutcome': null});
      }
      await c.refresh();
      expect(c.value.hotkey, NativeHotkeyCheck.interrupted);
    });
  }

  test('disabled, conflict, missing capability and active preview cannot start a key check', () async {
    final port = ObservationPort();
    final c = NativeOverlayCheckController(port);
    addTearDown(c.dispose);
    for (final state in [
      'disabled',
      'conflict',
      'invalid',
      'failed',
      'unavailable',
    ]) {
      port.hotkey({'state': state});
      await c.startHotkeyCheck();
      expect(c.value.hotkey, NativeHotkeyCheck.notStarted);
      expect(c.value.canCheckHotkey, false);
    }
    port.unavailable = true;
    await c.startHotkeyCheck();
    expect(c.value.canCheckHotkey, false);
    port.unavailable = false;
    port.hotkey({'state': 'registered'});
    port.raw = {
      ...port.raw,
      'preview': <String, Object?>{
        'sessionId': '33333333333333333333333333333333',
        'appliedRevision': 0,
        'nativeWindowVisible': true,
        'firstFrameCommitted': true,
      },
    };
    await c.startHotkeyCheck();
    expect(c.value.hotkey, NativeHotkeyCheck.notStarted);
  });

  testWidgets(
    'check ends at 30 seconds; outstanding read stays busy and cannot award a late input',
    (tester) async {
      final port = ObservationPort();
      final c = NativeOverlayCheckController(port);
      addTearDown(c.dispose);
      await c.startHotkeyCheck();
      final pending = port.pending = Completer();
      await tester.pump(const Duration(milliseconds: 750));
      expect(port.reads, 2);
      await tester.pump(const Duration(seconds: 30));
      expect(port.reads, 2);
      expect(c.value.hotkey, NativeHotkeyCheck.timedOut);
      expect(c.value.busy, true);
      pending.complete(
        NativeOverlayObservationWire.parse(
          observationWire(count: 1, outcome: 'open'),
          3,
        ),
      );
      await tester.pump();
      expect(c.value.hotkey, NativeHotkeyCheck.timedOut);
      expect(c.value.busy, false);
    },
  );

  test('scope invalidation clears evidence immediately without releasing an active read', () async {
    final port = ObservationPort();
    final c = NativeOverlayCheckController(port);
    addTearDown(c.dispose);
    await c.startHotkeyCheck();
    final pending = port.pending = Completer();
    final read = c.refresh();
    port.events.add(null);
    expect(c.value.observation, null);
    expect(c.value.hotkey, NativeHotkeyCheck.interrupted);
    expect(c.value.busy, true);
    pending.complete(
      NativeOverlayObservationWire.parse(
        observationWire(count: 1, outcome: 'open'),
        3,
      ),
    );
    await read;
    expect(c.value.observation, null);
    expect(c.value.hotkey, NativeHotkeyCheck.interrupted);
    expect(c.value.busy, false);
  });

  test('latest failed read does not retain a checked baseline', () async {
    final port = ObservationPort();
    final c = NativeOverlayCheckController(port);
    addTearDown(c.dispose);
    await c.startHotkeyCheck();
    port.fail = true;
    await c.refresh();
    expect(c.value.observation, null);
    expect(c.value.readError, true);
    expect(c.value.hotkey, NativeHotkeyCheck.interrupted);
  });

  test(
    'foreign preview blocks a visit without calling its launcher or close',
    () async {
      final port = ObservationPort();
      port.raw = {
        ...port.raw,
        'preview': <String, Object?>{
          'sessionId': '33333333333333333333333333333333',
          'appliedRevision': 0,
          'nativeWindowVisible': true,
          'firstFrameCommitted': true,
        },
      };
      final c = NativeOverlayCheckController(port);
      addTearDown(c.dispose);
      var opened = 0;
      await c.visitPreview(() async {
        opened++;
      });
      expect(opened, 0);
      expect(c.value.preview, NativePreviewVisit.blocked);
      expect(c.value.hotkey, NativeHotkeyCheck.notStarted);
    },
  );

  test('visit uses one borrowed original route; a returned route is not preview or key acceptance', () async {
    final port = ObservationPort();
    final c = NativeOverlayCheckController(port);
    addTearDown(c.dispose);
    final pending = Completer<void>();
    var opened = 0;
    final visit = c.visitPreview(() {
      opened++;
      return pending.future;
    });
    await Future<void>.delayed(Duration.zero);
    expect(c.value.preview, NativePreviewVisit.opening);
    expect(c.value.busy, true);
    await c.visitPreview(() async {
      opened++;
    });
    await c.startHotkeyCheck();
    expect(opened, 1);
    pending.complete();
    await visit;
    expect(c.value.preview, NativePreviewVisit.returned);
    expect(c.value.hotkey, NativeHotkeyCheck.notStarted);
    expect(c.value.observation!.firstFrameCommitted, false);
    expect(c.value.busy, false);
  });

  test('invalidated visit keeps its lifecycle lock until the original route returns', () async {
    final port = ObservationPort();
    final c = NativeOverlayCheckController(port);
    addTearDown(c.dispose);
    final pending = Completer<void>();
    final visit = c.visitPreview(() => pending.future);
    await Future<void>.delayed(Duration.zero);
    port.events.add(null);
    expect(c.value.busy, true);
    expect(c.value.observation, null);
    pending.complete();
    await visit;
    expect(c.value.preview, NativePreviewVisit.failed);
    expect(c.value.busy, false);
  });

  test(
    'launcher failure and unresolved Native preview are not a returned visit',
    () async {
      final port = ObservationPort();
      final c = NativeOverlayCheckController(port);
      addTearDown(c.dispose);
      await c.visitPreview(() async {
        throw StateError('failure');
      });
      expect(c.value.preview, NativePreviewVisit.failed);
      await c.visitPreview(() async {
        port.raw = {
          ...port.raw,
          'preview': <String, Object?>{
            'sessionId': '33333333333333333333333333333333',
            'appliedRevision': 0,
            'nativeWindowVisible': false,
            'firstFrameCommitted': false,
          },
        };
      });
      expect(c.value.preview, NativePreviewVisit.blocked);
    },
  );

  test(
    'dispose discards a late read and only cancels the borrowed subscription',
    () async {
      final port = ObservationPort()..pending = Completer();
      final c = NativeOverlayCheckController(port);
      final read = c.refresh();
      c.dispose();
      port.pending!.complete(
        NativeOverlayObservationWire.parse(observationWire(), 3),
      );
      await read;
      expect(port.events.isClosed, false);
      port.events.add(null);
      await port.events.close();
    },
  );

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    testWidgets(
      '$locale panel is explicit, fits 320px and 160% text, and preserves failed outcome',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = ObservationPort();
        final c = NativeOverlayCheckController(port);
        addTearDown(c.dispose);
        var opened = 0;
        final copy = OnboardingCopy(locale);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildStarBridgeTheme(
              FutureRestraintStyle.resolve(AppearanceMode.dark),
              locale,
            ),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: NativeOverlayCheckPanel(
                    controller: c,
                    copy: copy,
                    enabled: true,
                    openPreview: () async {
                      opened++;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(port.reads, 1);
        expect(opened, 0);
        expect(
          find.text(copy.text('native.hotkey.registered')),
          findsOneWidget,
        );
        await tester.ensureVisible(find.byKey(const Key('native-start-check')));
        await tester.tap(find.byKey(const Key('native-start-check')));
        await tester.pump();
        port.raw = observationWire(count: 1, outcome: 'failed');
        await tester.pump(const Duration(milliseconds: 750));
        expect(find.text(copy.text('native.outcome.failed')), findsOneWidget);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }

  testWidgets('disabled panel does not even read or open Native', (
    tester,
  ) async {
    final port = ObservationPort();
    final c = NativeOverlayCheckController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark),
          const Locale('en', 'US'),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: NativeOverlayCheckPanel(
              controller: c,
              copy: const OnboardingCopy(Locale('en')),
              enabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(port.reads, 0);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('native-refresh')))
          .onPressed,
      null,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('native-open-preview')))
          .onPressed,
      null,
    );
  });
}
