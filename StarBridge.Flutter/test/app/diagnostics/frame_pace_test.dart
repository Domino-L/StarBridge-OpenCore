import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming, Size, TimingsCallback;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/diagnostics/frame_pace_log.dart';
import 'package:starbridge_flutter/app/diagnostics/frame_pace_recorder.dart';
import 'package:starbridge_flutter/app/diagnostics/frame_pace_summary.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/frame_pace_panel.dart';

FrameTiming _frame({
  required int buildMs,
  required int rasterMs,
  int gapMs = 0,
  int start = 1000000,
}) {
  final buildEnd = start + buildMs * 1000;
  final rasterStart = buildEnd + gapMs * 1000;
  final rasterEnd = rasterStart + rasterMs * 1000;
  return FrameTiming(
    vsyncStart: start,
    buildStart: start,
    buildFinish: buildEnd,
    rasterStart: rasterStart,
    rasterFinish: rasterEnd,
    rasterFinishWallTime: rasterEnd,
  );
}

final class _Engine {
  final callbacks = <TimingsCallback>[];
  int added = 0;
  int removed = 0;
  void add(TimingsCallback callback) {
    added++;
    callbacks.add(callback);
  }

  void remove(TimingsCallback callback) {
    removed++;
    callbacks.remove(callback);
  }

  void emit(List<FrameTiming> frames) {
    for (final callback in List.of(callbacks)) {
      callback(frames);
    }
  }
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('sb-frame-pace-'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  FramePaceRecorder recorder(
    _Engine engine, {
    List<int>? activityReads,
    int maxBytes = 1024 * 1024,
  }) => FramePaceRecorder(
    directory: Directory('${temp.path}${Platform.pathSeparator}Diagnostics'),
    clockUs: () => 0,
    addTimings: engine.add,
    removeTimings: engine.remove,
    windowSize: () => const Size(2560, 1392),
    now: () => DateTime.utc(2026, 11, 7, 8, 30),
    readActivity: () async {
      activityReads?.add(1);
      return (maximized: true, starCitizen: true, otherFullscreen: false);
    },
    maxBytes: maxBytes,
  );

  List<Map<String, Object?>> lines(FramePaceRecorder value) => [
    for (final line in value.log.current.readAsLinesSync())
      jsonDecode(line) as Map<String, Object?>,
  ];

  group('summary', () {
    test('percentiles, maxima and stutter count per page', () {
      final summary = FramePaceSummary('/fleet?tab=members');
      for (var i = 1; i <= 10; i++) {
        summary.frame(buildUs: i * 1000, rasterUs: i * 2000, totalUs: i * 4000);
      }
      final [line] = summary.take(
        now: DateTime.utc(2026, 11, 7),
        context: {'maximized': true},
      );
      expect(line['page'], '/fleet');
      expect(line['maximized'], isTrue);
      expect(line['frames'], 10);
      // 36 and 40 ms frames are over 33 ms.
      expect(line['over33'], 2);
      expect(line['buildP50Ms'], 6.0);
      expect(line['buildP90Ms'], 9.0);
      expect(line['buildMaxMs'], 10.0);
      expect(line['rasterP50Ms'], 12.0);
      expect(line['rasterP90Ms'], 18.0);
      expect(line['rasterMaxMs'], 20.0);
    });

    test('a page change inside a minute gives one line per page', () {
      final summary = FramePaceSummary('/home');
      summary.frame(buildUs: 1000, rasterUs: 1000, totalUs: 2000);
      summary.page = '/settings';
      summary.frame(buildUs: 1000, rasterUs: 1000, totalUs: 2000);
      final rows = summary.take(now: DateTime.utc(2026), context: const {});
      expect(rows.map((row) => row['page']), ['/home', '/settings']);
    });

    test('a quiet minute still names the page with zero frames', () {
      final summary = FramePaceSummary('/home');
      summary.take(now: DateTime.utc(2026), context: const {});
      final [line] = summary.take(now: DateTime.utc(2026), context: const {});
      expect(line['page'], '/home');
      expect(line['frames'], 0);
      expect(line['rasterMaxMs'], 0);
    });

    test('maxima include frames past the sample bound', () {
      final summary = FramePaceSummary('/home');
      for (var i = 0; i < FramePaceSummary.maxFramesPerPage; i++) {
        summary.frame(buildUs: 1000, rasterUs: 1000, totalUs: 2000);
      }
      summary.frame(buildUs: 100000, rasterUs: 90000, totalUs: 190000);
      final [line] = summary.take(now: DateTime.utc(2026), context: const {});
      expect(line['buildMaxMs'], 100.0);
      expect(line['rasterMaxMs'], 90.0);
    });

    test('keeps at most a bounded number of samples but counts all', () {
      final summary = FramePaceSummary('/home');
      for (var i = 0; i < FramePaceSummary.maxFramesPerPage + 5; i++) {
        summary.frame(buildUs: 1, rasterUs: 1, totalUs: 40000);
      }
      final [line] = summary.take(now: DateTime.utc(2026), context: const {});
      expect(line['frames'], FramePaceSummary.maxFramesPerPage + 5);
      expect(line['over33'], FramePaceSummary.maxFramesPerPage + 5);
    });
  });

  group('log', () {
    test('rotates to one older file and stays within two files', () async {
      final log = FramePaceLog(temp, maxBytes: 200);
      for (var i = 0; i < 30; i++) {
        await log.append([
          {'i': i, 'pad': 'x' * 40},
        ]);
      }
      final files = temp.listSync().whereType<File>().toList();
      expect(files.map((file) => file.uri.pathSegments.last).toSet(), {
        FramePaceLog.fileName,
        FramePaceLog.olderFileName,
      });
      for (final file in files) {
        expect(file.lengthSync(), lessThanOrEqualTo(200));
      }
      final last = log.current.readAsLinesSync().last;
      expect(jsonDecode(last)['i'], 29);
    });

    test('a line that cannot be encoded does not block the others', () async {
      final log = FramePaceLog(temp);
      await log.append([
        {'bad': Object()},
        {'ok': 1},
      ]);
      expect(log.current.readAsLinesSync(), ['{"ok":1}']);
    });

    test('an oversized line does not take the others with it', () async {
      final log = FramePaceLog(temp, maxBytes: 60);
      await log.append([
        {'pad': 'x' * 100},
        {'ok': 1},
        {'ok': 2},
      ]);
      expect(
        log.current.readAsLinesSync().map((line) => jsonDecode(line)['ok']),
        [1, 2],
      );
    });

    test('a line larger than the bound is dropped, not written', () async {
      final log = FramePaceLog(temp, maxBytes: 50);
      await log.append([
        {'pad': 'x' * 100},
      ]);
      expect(log.current.existsSync(), isFalse);
    });
  });

  group('recorder', () {
    test('off by default: nothing registered, nothing written', () async {
      final engine = _Engine();
      final reads = <int>[];
      final value = recorder(engine, activityReads: reads);
      addTearDown(value.dispose);
      expect(value.enabled.value, isFalse);
      expect(engine.added, 0);
      value.page = '/fleet';
      await value.writeMinute();
      expect(reads, isEmpty);
      expect(value.directory.existsSync(), isFalse);
    });

    test('records page, window, frames and game presence once on', () async {
      final engine = _Engine();
      final value = recorder(engine);
      addTearDown(value.dispose);
      value.page = '/fleet';
      expect(await value.setEnabled(true), isTrue);
      expect(value.enabled.value, isTrue);
      expect(engine.added, 1);
      engine.emit([
        _frame(buildMs: 4, rasterMs: 6),
        _frame(buildMs: 10, rasterMs: 30),
      ]);
      await value.writeMinute();
      final [line] = lines(value);
      expect(line, {
        'at': '2026-11-07T08:30:00.000Z',
        'page': '/fleet',
        'width': 2560,
        'height': 1392,
        'maximized': true,
        'starCitizen': true,
        'otherFullscreen': false,
        'frames': 2,
        'over33': 1,
        'rasterP50Ms': 30.0,
        'rasterP90Ms': 30.0,
        'rasterMaxMs': 30.0,
        'buildP50Ms': 10.0,
        'buildP90Ms': 10.0,
        'buildMaxMs': 10.0,
      });
    });

    test(
      'turning off writes the last minute, unregisters and forgets',
      () async {
        final engine = _Engine();
        final value = recorder(engine);
        addTearDown(value.dispose);
        await value.setEnabled(true);
        engine.emit([_frame(buildMs: 2, rasterMs: 2)]);
        expect(await value.setEnabled(false), isTrue);
        expect(value.enabled.value, isFalse);
        expect(engine.removed, 1);
        expect(engine.callbacks, isEmpty);
        expect(lines(value), hasLength(1));
        expect(
          File(
            '${value.directory.path}${Platform.pathSeparator}'
            '${FramePaceRecorder.markerName}',
          ).existsSync(),
          isFalse,
        );
        await value.writeMinute();
        expect(lines(value), hasLength(1));
      },
    );

    test(
      'a stop while the native answer is pending keeps each frame once',
      () async {
        final engine = _Engine();
        final answer = Completer<GameActivity?>();
        final value = FramePaceRecorder(
          directory: temp,
          clockUs: () => 0,
          addTimings: engine.add,
          removeTimings: engine.remove,
          windowSize: () => null,
          readActivity: () => answer.future,
        );
        addTearDown(value.dispose);
        await value.setEnabled(true);
        engine.emit([_frame(buildMs: 1, rasterMs: 1)]);
        final tick = value.writeMinute();
        engine.emit([_frame(buildMs: 2, rasterMs: 2)]);
        final stop = value.setEnabled(false);
        answer.complete(null);
        await tick;
        await stop;
        await value.log.idle;
        final rows = lines(value);
        expect(rows.map((row) => row['frames']), [1, 1]);
        expect(rows.every((row) => row['starCitizen'] == null), isTrue);
      },
    );

    test(
      'a late batch counts each frame on the page it was drawn on',
      () async {
        final engine = _Engine();
        var clock = 1000000;
        final value = FramePaceRecorder(
          directory: temp,
          addTimings: engine.add,
          removeTimings: engine.remove,
          windowSize: () => null,
          readActivity: () async => null,
          clockUs: () => clock,
        );
        addTearDown(value.dispose);
        value.page = '/fleet';
        await value.setEnabled(true);
        clock = 2000000;
        value.page = '/hangar';
        engine.emit([
          _frame(buildMs: 1, rasterMs: 1, start: 1500000),
          _frame(buildMs: 1, rasterMs: 1, start: 2500000),
          _frame(buildMs: 1, rasterMs: 1, start: 2600000),
        ]);
        await value.writeMinute();
        final rows = {
          for (final row in lines(value)) row['page']: row['frames'],
        };
        expect(rows, {'/fleet': 1, '/hangar': 2});
      },
    );

    test(
      'the frame being built when the page changes counts for the new page',
      () async {
        final engine = _Engine();
        var clock = 1000000;
        final value = FramePaceRecorder(
          directory: temp,
          addTimings: engine.add,
          removeTimings: engine.remove,
          windowSize: () => null,
          readActivity: () async => null,
          clockUs: () => clock,
        );
        addTearDown(value.dispose);
        value.page = '/fleet';
        await value.setEnabled(true);
        // The shell reports the page while building a frame whose vsync was at
        // 1 980 000 and whose build finishes at 2 010 000.
        clock = 2000000;
        value.page = '/hangar';
        engine.emit([
          _frame(buildMs: 5, rasterMs: 1, start: 1960000),
          _frame(buildMs: 30, rasterMs: 1, start: 1980000),
        ]);
        await value.writeMinute();
        final rows = {
          for (final row in lines(value)) row['page']: row['frames'],
        };
        expect(rows, {'/fleet': 1, '/hangar': 1});
      },
    );

    test('a new round ignores frames from before it began', () async {
      final engine = _Engine();
      var clock = 1000000;
      final value = FramePaceRecorder(
        directory: temp,
        addTimings: engine.add,
        removeTimings: engine.remove,
        windowSize: () => null,
        readActivity: () async => null,
        clockUs: () => clock,
      );
      addTearDown(value.dispose);
      await value.setEnabled(true);
      await value.setEnabled(false);
      clock = 3000000;
      await value.setEnabled(true);
      engine.emit([
        _frame(buildMs: 1, rasterMs: 1, start: 2000000),
        _frame(buildMs: 1, rasterMs: 1, start: 3100000),
      ]);
      await value.setEnabled(false);
      expect(lines(value).last['frames'], 1);
    });

    test(
      'released while the native answer is pending: nothing written',
      () async {
        final engine = _Engine();
        final answer = Completer<GameActivity?>();
        final value = FramePaceRecorder(
          directory: temp,
          clockUs: () => 0,
          addTimings: engine.add,
          removeTimings: engine.remove,
          windowSize: () => null,
          readActivity: () => answer.future,
        );
        await value.setEnabled(true);
        engine.emit([_frame(buildMs: 1, rasterMs: 1)]);
        final tick = value.writeMinute();
        value.dispose();
        answer.complete(null);
        await tick;
        await value.log.idle;
        expect(value.log.current.existsSync(), isFalse);
      },
    );

    test('the saved choice survives a restart', () async {
      final first = recorder(_Engine());
      await first.setEnabled(true);
      first.dispose();
      final engine = _Engine();
      final second = recorder(engine);
      addTearDown(second.dispose);
      expect(second.enabled.value, isTrue);
      expect(engine.added, 1);
    });

    test('dispose unregisters without writing', () async {
      final engine = _Engine();
      final value = recorder(engine);
      await value.setEnabled(true);
      value.dispose();
      expect(engine.callbacks, isEmpty);
      expect(value.log.current.existsSync(), isFalse);
    });

    test('only the real client gets a recorder', () {
      expect(FramePaceRecorder.fromEnvironment(const {}), isNull);
      expect(
        FramePaceRecorder.fromEnvironment({
          'LOCALAPPDATA': temp.path,
          'FLUTTER_TEST': 'true',
        }),
        isNull,
      );
      expect(
        FramePaceRecorder.fromEnvironment(const {'LOCALAPPDATA': 'relative'}),
        isNull,
      );
    });
  });

  group('panel', () {
    Widget app(Widget child) {
      final tokens = StyleRegistry()
          .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
          .tokens;
      return MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppStrings.runtimeSupportedLocales(),
        localizationsDelegates: const [
          AppStringsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildStarBridgeTheme(tokens, const Locale('zh', 'CN')),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );
    }

    testWidgets(
      'plain switch turns recording on and opens the folder',
      timeout: const Timeout(Duration(seconds: 60)),
      (tester) async {
        final engine = _Engine();
        final value = recorder(engine);
        addTearDown(value.dispose);
        final opened = <String>[];
        await tester.pumpWidget(
          app(
            FramePacePanel(
              recorder: value,
              openFolder: (path) async => opened.add(path),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('记录界面流畅度（排查卡顿用）', findRichText: true), findsWidgets);
        expect(find.byKey(const Key('frame-pace-open-folder')), findsNothing);
        await tester.tap(find.text('记录界面流畅度（排查卡顿用）', findRichText: true).first);
        // The file write is real IO: let it finish, then run its continuation.
        for (var i = 0; i < 50 && !value.enabled.value; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(value.enabled.value, isTrue);
        expect(engine.added, 1);
        await tester.tap(find.byKey(const Key('frame-pace-open-folder')));
        await tester.pump();
        expect(opened, [value.directory.path]);
        var off = false;
        unawaited(value.setEnabled(false).then((_) => off = true));
        for (var i = 0; i < 50 && !off; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(value.enabled.value, isFalse);
        expect(find.byKey(const Key('frame-pace-open-folder')), findsNothing);
      },
    );
  });
}
