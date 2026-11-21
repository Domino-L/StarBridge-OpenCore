import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_port.dart';
import 'package:starbridge_flutter/platform/window/method_channel_hangar_browser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('starbridge/hangar-browser');
  final profileKey = 'A' * 64;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('the sign-in choice is read and written by native, which owns it; '
      'writing it ends the current view', () async {
    final calls = <MethodCall>[];
    var remembered = false;
    var failSave = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'open') return 42;
      if (call.method == 'readChoice') {
        return {
          'remember': remembered,
          'uncleared': !remembered,
          'unknown': false,
        };
      }
      if (call.method == 'setChoice') {
        final value = (call.arguments as Map)['remember'] as bool;
        if (failSave) throw PlatformException(code: 'choice_failed');
        remembered = value;
      }
      return null;
    });
    final browser = MethodChannelHangarBrowser();
    expect(await browser.readSignIn(), (
      remember: false,
      uncleared: true,
      unknown: false,
    ));
    await browser.open(profileKey: profileKey);
    // A choice that could not be saved leaves the view open and closable.
    failSave = true;
    await expectLater(
      browser.setRemember(true),
      throwsA(isA<HangarReaderFailure>()),
    );
    await browser.close();
    expect(calls.last.method, 'close');
    expect(calls.last.arguments, {'viewId': 42});
    failSave = false;
    await browser.open(profileKey: profileKey);
    await browser.setRemember(true);
    expect(calls.last.method, 'setChoice');
    expect(calls.last.arguments, {'remember': true});
    expect(await browser.readSignIn(), (
      remember: true,
      uncleared: false,
      unknown: false,
    ));
    // Native already closed the view while saving the choice.
    final closes = calls.where((call) => call.method == 'close').length;
    await browser.close();
    expect(calls.where((call) => call.method == 'close').length, closes);
  });

  test(
    'clearData sends no path and resets the view; native failures propagate',
    () async {
      final calls = <MethodCall>[];
      var fail = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'open') return 42;
        if (call.method == 'clearData' && fail) {
          throw PlatformException(code: 'clear_busy');
        }
        return null;
      });
      final browser = MethodChannelHangarBrowser();
      await browser.open(profileKey: profileKey);
      await browser.clearData();
      expect(calls.last.method, 'clearData');
      expect(calls.last.arguments, isEmpty);
      await browser.close();
      expect(calls.where((call) => call.method == 'close'), isEmpty);
      fail = true;
      await expectLater(
        browser.clearData(),
        throwsA(
          isA<HangarReaderFailure>().having(
            (error) => error.code,
            'code',
            'clear_busy',
          ),
        ),
      );
    },
  );

  test('clearing calls wait for native to finish deleting, beyond the '
      'ordinary timeout', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'open') return 42;
      if (['clearData', 'close', 'setChoice'].contains(call.method)) {
        // Native replies only once the deletion on its worker thread is done.
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      return null;
    });
    final browser = MethodChannelHangarBrowser(
      timeout: const Duration(milliseconds: 10),
      clearTimeout: const Duration(seconds: 5),
    );
    await browser.clearData();
    await browser.open(profileKey: profileKey);
    // close swallows failures, so check that it really waited for the reply.
    final closing = Stopwatch()..start();
    await browser.close();
    expect(
      closing.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 50)),
    );
    await browser.setRemember(false);
    expect(calls, ['clearData', 'open', 'close', 'setChoice']);
  });

  test(
    'all operations use the native view ID and close is idempotent',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'open') return 42;
        if (call.method == 'capture' || call.method == 'lock') {
          return {
            'source':
                'https://robertsspaceindustries.com/en/account/pledges?page=1',
            'documentGeneration': 3,
            'scanId': 'synthetic-native-scan',
            'locked': true,
            'json': '{"identity":{},"page":{}}',
          };
        }
        return null;
      });
      final browser = MethodChannelHangarBrowser();
      await browser.open(profileKey: profileKey);
      expect(calls.first.arguments['profileKey'], profileKey);
      final identity = await browser.lock();
      expect(identity['scanId'], 'synthetic-native-scan');
      expect(identity['locked'], true);
      await browser.page(1);
      final value = await browser.capture();
      expect(value['documentGeneration'], 3);
      expect(value['observation'], {'identity': {}, 'page': {}});
      await browser.bounds(const Rect.fromLTWH(2, 3, 40, 50), visible: true);
      await browser.focus();
      await browser.unlock();
      await browser.close();
      await browser.close();
      expect(
        calls.skip(1).every((call) => call.arguments['viewId'] == 42),
        true,
      );
      expect(calls.where((call) => call.method == 'close'), hasLength(1));
    },
  );

  test('cancel during open closes its late native view', () async {
    final opened = Completer<int>();
    final closed = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'open') return opened.future;
      if (call.method == 'close') closed.add(call.arguments['viewId'] as int);
      return null;
    });
    final browser = MethodChannelHangarBrowser();
    final opening = browser.open(profileKey: profileKey);
    final check = expectLater(opening, throwsA(isA<HangarReaderFailure>()));
    await browser.close();
    opened.complete(17);
    await check;
    await Future<void>.delayed(Duration.zero);
    expect(closed, [17]);
  });

  test('timed-out open cannot close a newer native view', () async {
    final oldOpening = Completer<int>();
    final closed = <int>[];
    var opens = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'open') return ++opens == 1 ? oldOpening.future : 22;
      if (call.method == 'close') closed.add(call.arguments['viewId'] as int);
      return null;
    });
    final browser = MethodChannelHangarBrowser(
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      browser.open(profileKey: profileKey),
      throwsA(isA<TimeoutException>()),
    );
    await browser.open(profileKey: profileKey);
    oldOpening.complete(11);
    await Future<void>.delayed(Duration.zero);
    expect(closed, [11]);
    await browser.close();
    expect(closed, [11, 22]);
  });

  test('native error codes remain actionable reader failures', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'runtime');
    });
    await expectLater(
      MethodChannelHangarBrowser().open(profileKey: profileKey),
      throwsA(
        isA<HangarReaderFailure>().having(
          (error) => error.code,
          'code',
          'runtime',
        ),
      ),
    );
  });
}
