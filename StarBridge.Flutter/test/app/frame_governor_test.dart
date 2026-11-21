import 'dart:async';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/frame_governor.dart';

FramePressure pressure({
  bool game = false,
  bool front = false,
  bool own = false,
}) => (gameRunning: game, gameInFront: front, ownForeground: own);

void main() {
  test('mode follows who is in front and whether a game runs', () {
    expect(frameModeFor(null), FrameMode.open);
    expect(frameModeFor(pressure(own: true)), FrameMode.open);
    expect(
      frameModeFor(pressure(game: true, own: true)),
      FrameMode.focusedWithGame,
    );
    expect(frameModeFor(pressure()), FrameMode.background);
    expect(frameModeFor(pressure(game: true)), FrameMode.background);
    expect(frameModeFor(pressure(front: true)), FrameMode.gameInFront);
    expect(
      frameModeFor(pressure(game: true, front: true)),
      FrameMode.gameInFront,
    );
  });

  test('decoration runs only in front and without a game', () {
    expect(decorativeMotionAllowedFor(null), isTrue);
    expect(decorativeMotionAllowedFor(pressure(own: true)), isTrue);
    expect(decorativeMotionAllowedFor(pressure(own: true, game: true)), isFalse);
    expect(decorativeMotionAllowedFor(pressure()), isFalse);
    expect(decorativeMotionAllowedFor(pressure(front: true)), isFalse);
  });

  // C-lite: light visuals only while a game is known to run.
  test('light visuals follow a running game, unknown keeps the full look', () {
    expect(lightVisualsFor(null), isFalse);
    expect(lightVisualsFor(pressure(own: true)), isFalse);
    expect(lightVisualsFor(pressure()), isFalse);
    expect(
      lightVisualsFor(pressure(game: true, own: true), performanceMode: true),
      isTrue,
    );
    expect(
      lightVisualsFor(pressure(game: true, front: true), performanceMode: true),
      isTrue,
    );
    // Off by default (user 11-10): a game alone keeps the full look.
    expect(lightVisualsFor(pressure(game: true, own: true)), isFalse);
    expect(lightVisuals().value, isFalse, reason: 'no lab define in tests');
    // Performance mode (user setting, off by default) gates the light look.
    final game = pressure(game: true, own: true);
    expect(lightVisualsFor(game, performanceMode: true), isTrue);
    expect(lightVisualsFor(pressure(own: true), performanceMode: true), isFalse);
    expect(lightVisualsFor(game, performanceMode: false), isFalse);
  });

  test('limits per mode and surface', () {
    expect(frameIntervalFor(FrameMode.open, FrameSurface.main), isNull);
    expect(
      frameIntervalFor(FrameMode.focusedWithGame, FrameSurface.main),
      const Duration(microseconds: 16666),
    );
    expect(
      frameIntervalFor(
        FrameMode.focusedWithGame,
        FrameSurface.main,
        focusedFps: 30,
      ),
      const Duration(microseconds: 33333),
    );
    expect(
      frameIntervalFor(FrameMode.background, FrameSurface.friends),
      const Duration(microseconds: 33333),
    );
    expect(
      frameIntervalFor(FrameMode.gameInFront, FrameSurface.main),
      const Duration(milliseconds: 200),
    );
    expect(
      frameIntervalFor(FrameMode.gameInFront, FrameSurface.menu),
      const Duration(microseconds: 33333),
    );
  });

  group('governor', () {
    late FakeAsync clockOwner;
    late int reads;
    late FramePressure? current;
    late int scheduled;

    FrameGovernor governor({FrameSurface surface = FrameSurface.main}) =>
        FrameGovernor(
          surface: surface,
          clock: () => clockOwner.elapsed,
          readPressure: () async {
            reads++;
            return current;
          },
          performanceMode: const AlwaysStoppedAnimation(true),
        );

    void schedule() => scheduled++;

    setUp(() {
      reads = 0;
      scheduled = 0;
      current = null;
    });

    test('an idle surface reads nothing', () {
      fakeAsync((async) {
        clockOwner = async;
        governor();
        async.elapse(const Duration(seconds: 10));
        expect(reads, 0);
      });
    });

    test('game in front: frames wait for the 5 fps slot', () {
      fakeAsync((async) {
        clockOwner = async;
        current = pressure(game: true, front: true);
        final g = governor();
        g.request(schedule); // first request: unknown pressure, no wait
        async.flushMicrotasks();
        expect(scheduled, 1);
        expect(g.mode, FrameMode.gameInFront);
        g.frameStarted();
        async.elapse(const Duration(milliseconds: 10));
        g.request(schedule);
        expect(scheduled, 1);
        expect(g.hasDeferredFrame, isTrue);
        async.elapse(const Duration(milliseconds: 180));
        expect(scheduled, 1);
        async.elapse(const Duration(milliseconds: 15));
        expect(scheduled, 2);
        expect(g.deferrals, 1);
        expect(g.frames[FrameMode.gameInFront], 1);
        expect(g.decorativeMotion.value, isFalse);
      });
    });

    test('coming back to the client releases a waiting frame at once', () {
      fakeAsync((async) {
        clockOwner = async;
        current = pressure(game: true, front: true);
        final g = governor();
        g.request(schedule);
        async.flushMicrotasks();
        g.frameStarted();
        async.elapse(const Duration(milliseconds: 600));
        g.frameStarted();
        // The player switched back; the read that tells us so is still
        // pending, so this frame waits under the old 5 fps rule first.
        current = pressure(game: true, own: true);
        g.request(schedule);
        expect(g.hasDeferredFrame, isTrue);
        async.flushMicrotasks();
        expect(g.mode, FrameMode.focusedWithGame);
        // 16.7 ms since the last frame start has not passed: still waits,
        // but only for the new, shorter slot.
        expect(scheduled, 1);
        async.elapse(const Duration(milliseconds: 17));
        expect(scheduled, 2);
      });
    });

    test('pressure is read at most every half second while drawing', () {
      fakeAsync((async) {
        clockOwner = async;
        current = pressure(own: true);
        final g = governor();
        for (var i = 0; i < 120; i++) {
          g.request(schedule);
          async.flushMicrotasks();
          g.frameStarted();
          async.elapse(const Duration(milliseconds: 4));
        }
        // 480 ms of continuous frames, unlimited, one read.
        expect(scheduled, 120);
        expect(reads, 1);
        async.elapse(const Duration(milliseconds: 100));
        g.request(schedule);
        async.flushMicrotasks();
        expect(reads, 2);
      });
    });

    test('a host without the channel is never limited', () {
      fakeAsync((async) {
        clockOwner = async;
        var calls = 0;
        final g = FrameGovernor(
          surface: FrameSurface.main,
          clock: () => async.elapsed,
          readPressure: () async {
            calls++;
            throw MissingPluginException();
          },
        );
        for (var i = 0; i < 5; i++) {
          g.request(schedule);
          async.flushMicrotasks();
          g.frameStarted();
          async.elapse(const Duration(seconds: 1));
        }
        expect(scheduled, 5);
        expect(calls, 1);
        expect(g.mode, FrameMode.open);
      });
    });

    // Review P2-1: a channel that answers once and then never again must not
    // keep the 5 fps limit or the paused decoration.
    test('a channel that stops answering returns to unlimited', () {
      fakeAsync((async) {
        clockOwner = async;
        var answer = true;
        final g = FrameGovernor(
          surface: FrameSurface.main,
          clock: () => async.elapsed,
          readPressure: () => answer
              ? Future.value(pressure(game: true, front: true))
              : Completer<FramePressure?>().future,
        );
        g.request(schedule);
        async.flushMicrotasks();
        expect(g.mode, FrameMode.gameInFront);
        expect(g.decorativeMotion.value, isFalse);
        answer = false;
        async.elapse(const Duration(seconds: 2)); // probe starts a read
        expect(g.mode, FrameMode.gameInFront);
        async.elapse(const Duration(seconds: 2)); // the read times out
        expect(g.mode, FrameMode.open);
        expect(g.decorativeMotion.value, isTrue);
        expect(g.isProbing, isFalse);
        g.dispose();
      });
    });

    // Review 2 P3: after a timeout a fresh read decides; the old answer that
    // arrives late changes nothing.
    test('a late answer after the timeout never overrides a newer read', () {
      fakeAsync((async) {
        clockOwner = async;
        final late = Completer<FramePressure?>();
        var first = true;
        final g = FrameGovernor(
          surface: FrameSurface.main,
          clock: () => async.elapsed,
          readPressure: () {
            if (first) {
              first = false;
              return late.future;
            }
            return Future.value(pressure(game: true, own: true));
          },
        );
        g.request(schedule);
        async.elapse(const Duration(seconds: 2)); // the first read times out
        expect(g.mode, FrameMode.open);
        async.elapse(const Duration(milliseconds: 600));
        g.request(schedule); // stale: a new read starts and succeeds
        async.flushMicrotasks();
        expect(g.mode, FrameMode.focusedWithGame);
        late.complete(pressure(game: true, front: true));
        async.flushMicrotasks();
        expect(g.mode, FrameMode.focusedWithGame);
        g.dispose();
      });
    });

    // Review 2 P2: disposing while a read is in flight must not apply its
    // answer or restart the probe.
    test('a read that returns after dispose changes nothing', () {
      fakeAsync((async) {
        clockOwner = async;
        final pending = Completer<FramePressure?>();
        final g = FrameGovernor(
          surface: FrameSurface.main,
          clock: () => async.elapsed,
          readPressure: () => pending.future,
        );
        g.request(schedule);
        g.dispose();
        pending.complete(pressure(game: true, front: true));
        async.flushMicrotasks();
        expect(g.mode, FrameMode.open);
        expect(g.isProbing, isFalse);
        async.elapse(const Duration(seconds: 10));
        expect(g.isProbing, isFalse);
      });
    });

    test('performance mode switches the light look live; the frame cap stays', () {
      fakeAsync((async) {
        clockOwner = async;
        final mode = ValueNotifier(true);
        final g = FrameGovernor(
          surface: FrameSurface.main,
          clock: () => async.elapsed,
          readPressure: () async => pressure(game: true, own: true),
          performanceMode: mode,
        );
        g.request(schedule);
        async.flushMicrotasks();
        expect(g.lightVisuals.value, isTrue, reason: 'on + game: light');
        mode.value = false;
        expect(g.lightVisuals.value, isFalse, reason: 'off + game: full look');
        expect(g.mode, FrameMode.focusedWithGame, reason: 'A keeps working');
        mode.value = true;
        expect(g.lightVisuals.value, isTrue);
        g.dispose();
        mode.value = false;
        expect(g.lightVisuals.value, isTrue, reason: 'no updates after dispose');
        mode.dispose();
      });
    });

    // Review P2-3: the probe recovers decoration even when nothing asks for
    // a frame (the paused animation was the last frame source).
    test('paused decoration resumes after the game closes without frames', () {
      fakeAsync((async) {
        clockOwner = async;
        current = pressure(game: true, own: true);
        final g = governor();
        g.request(schedule);
        async.flushMicrotasks();
        expect(g.decorativeMotion.value, isFalse);
        expect(g.isProbing, isTrue);
        expect(g.lightVisuals.value, isTrue, reason: "a game runs");
        final readsBefore = reads;
        current = pressure(own: true); // the game closed; no frame requested
        async.elapse(const Duration(seconds: 2));
        expect(reads, greaterThan(readsBefore));
        expect(g.decorativeMotion.value, isTrue);
        expect(g.lightVisuals.value, isFalse, reason: 'full look returns');
        expect(g.mode, FrameMode.open);
        expect(g.isProbing, isFalse);
        final idle = reads;
        async.elapse(const Duration(seconds: 20));
        expect(reads, idle, reason: 'an unlimited idle surface reads nothing');
        g.dispose();
      });
    });
  });

  // Review P2-2: an incomplete or failed native answer is unknown, never a
  // limit.
  test('only a complete native answer counts', () {
    expect(parseFramePressure(null), isNull);
    expect(parseFramePressure({}), isNull);
    expect(
      parseFramePressure({'gameRunning': true, 'gameInFront': false}),
      isNull,
    );
    expect(
      parseFramePressure({
        'gameRunning': true,
        'gameInFront': 'yes',
        'ownForeground': false,
      }),
      isNull,
    );
    expect(
      parseFramePressure({
        'gameRunning': true,
        'gameInFront': false,
        'ownForeground': true,
      }),
      pressure(game: true, own: true),
    );
    expect(frameModeFor(parseFramePressure({})), FrameMode.open);
    final native = File(
      'windows/runner/frame_pressure_channel.h',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(native, contains('if (!pressure.valid)'));
    expect(native, contains('TryStarCitizenProcessIds'));
    // Reviews 3 and 4 (no native test harness; structure checks scoped to the
    // function bodies): valid only after a branch fully classified the
    // foreground; every failed query returns the default (invalid).
    String body(String source, String signature) {
      final start = source.indexOf(signature);
      expect(start, isNonNegative, reason: signature);
      final end = source.indexOf('\n}\n', start);
      return source.substring(start, end);
    }

    final read = body(native, 'inline Pressure ReadUncached()');
    final pid = read.indexOf('GetWindowThreadProcessId(foreground, &pid) == 0');
    final valids = RegExp(r'pressure\.valid = true;')
        .allMatches(read)
        .map((m) => m.start)
        .toList();
    expect(valids, hasLength(5), reason: 'own, hidden, shell, game, fullscreen check');
    expect(valids.every((i) => i > pid), isTrue,
        reason: 'nothing is valid before the foreground process is known');
    // Review 5: a window destroyed mid-read is "not visible"; that is unknown.
    expect(read, contains('if (!IsWindowVisible(foreground)) {\n    return pressure;\n  }'));
    final unknown = read.indexOf('SurfaceKind::kUnknown) {\n    return pressure;');
    final shell = read.indexOf('SurfaceKind::kShell) {\n    pressure.valid = true;');
    expect(unknown, isNonNegative, reason: 'an unreadable class is unknown');
    expect(shell, greaterThan(unknown));
    final monitorFailure = read.indexOf('!GetMonitorInfoW(handle, &monitor)) {\n    return pressure;');
    final covers = read.indexOf('CoversMonitor(window, monitor.rcMonitor)');
    expect(monitorFailure, isNonNegative, reason: 'a failed monitor query is unknown');
    expect(covers, greaterThan(monitorFailure));
    expect(valids.last, greaterThan(covers), reason: 'the last valid follows the fullscreen check');
    final probe = File('windows/runner/game_activity_probe.h')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final walk = body(probe, 'inline bool TryStarCitizenProcessIds');
    final first = walk.indexOf('Process32FirstW(snapshot, &entry);');
    expect(walk.indexOf('DWORD end = more ? ERROR_SUCCESS : GetLastError();'), greaterThan(first),
        reason: 'the code is captured right after First');
    final next = walk.indexOf('more = Process32NextW(snapshot, &entry);');
    expect(walk.indexOf('if (!more) end = GetLastError();'), greaterThan(next),
        reason: 'and right after Next');
    expect(walk, contains('return end == ERROR_NO_MORE_FILES;'),
        reason: 'a partial process walk is unknown, not "no game"');
    final classify = body(probe, 'inline SurfaceKind ClassifySurface');
    expect(classify, contains('GetClassNameW(window, name, 32) == 0) return SurfaceKind::kUnknown;'));
  });

  // Review P2-4: the log follows the settings switch at run time.
  test('the governor log writes only while the switch is on', () async {
    final dir = Directory.systemTemp.createTempSync('frame-governor-log');
    addTearDown(() => dir.deleteSync(recursive: true));
    final marker = File('${dir.path}${Platform.pathSeparator}frame-pace.on');
    final out = File('${dir.path}${Platform.pathSeparator}log.jsonl');
    final g = FrameGovernor(surface: FrameSurface.main);
    final log = FrameGovernorLog(g, out, marker);
    g.frameStarted();
    await log.tick(); // off: nothing written, counts reset
    expect(out.existsSync(), isFalse);
    expect(g.frames, isEmpty);
    marker.writeAsStringSync('1'); // turned on while running
    g.frameStarted();
    await log.tick();
    expect(out.readAsLinesSync(), hasLength(1));
    marker.deleteSync(); // turned off while running
    g.frameStarted();
    await log.tick();
    expect(out.readAsLinesSync(), hasLength(1));
    expect(g.frames, isEmpty);
  });

  testWidgets('an existing binding is kept', (tester) async {
    expect(
      StarBridgeBinding.ensureInitialized(FrameSurface.main),
      same(tester.binding),
    );
  });

  test('every engine goes through the governed binding', () {
    final diagnostics = File(
      'lib/app/diagnostics/loading_diagnostics.dart',
    ).readAsStringSync();
    expect(
      'StarBridgeBinding.ensureInitialized(_frameSurface(auxiliarySurface))'
          .allMatches(diagnostics)
          .length,
      2,
    );
    expect(
      File('lib/app/tray/tray_surface_app.dart').readAsStringSync(),
      contains('StarBridgeBinding.ensureInitialized(FrameSurface.tray)'),
    );
    final plain = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) => f
              .readAsStringSync()
              .contains('WidgetsFlutterBinding.ensureInitialized('),
        )
        .map((f) => f.path)
        .toList();
    expect(plain, isEmpty);
  });
}
