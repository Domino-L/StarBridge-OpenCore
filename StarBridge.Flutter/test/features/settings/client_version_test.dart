import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/client_version_dialog.dart';

Future<void> mount(
  WidgetTester tester,
  ClientVersionRead? read, {
  Locale locale = const Locale('zh', 'CN'),
  Brightness brightness = Brightness.dark,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: ClientVersionButton(
          open: (context) => showClientVersionDialog(context, read: read),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('client-version-open')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shows exact version, copies only version, no network status claim',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester, () async => '1.2.3+build.9');
      expect(find.text('1.2.3+build.9'), findsOneWidget);
      await tester.tap(find.byKey(const Key('client-version-copy')));
      await tester.pumpAndSettle();
      expect(copied, '1.2.3+build.9');
      expect(find.text('版本号已复制'), findsOneWidget);
      expect(find.textContaining('最新'), findsNothing);
    },
  );

  for (final failure in ['missing-reader', 'null', 'exception']) {
    testWidgets('$failure is unavailable without fallback version', (
      tester,
    ) async {
      await mount(
        tester,
        failure == 'missing-reader'
            ? null
            : () async {
                if (failure == 'exception') throw StateError('private path');
                return null;
              },
      );
      expect(find.text('暂时无法读取版本，请重试。'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('client-version-copy')))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('private path'), findsNothing);
    });
  }

  testWidgets('failed refresh removes old version and retry can recover', (
    tester,
  ) async {
    String? value = '2.0.0';
    await mount(tester, () async => value);
    value = null;
    await tester.tap(find.byKey(const Key('client-version-retry')));
    await tester.pumpAndSettle();
    expect(find.text('2.0.0'), findsNothing);
    value = '2.0.1';
    await tester.tap(find.byKey(const Key('client-version-retry')));
    await tester.pumpAndSettle();
    expect(find.text('2.0.1'), findsOneWidget);
  });

  testWidgets(
    'pending load blocks repeat reads and closing ignores late completion',
    (tester) async {
      final pending = Completer<String?>();
      var calls = 0;
      await mount(tester, () {
        calls++;
        return pending.future;
      });
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('client-version-retry')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      pending.complete('1.0.0');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(calls, 1);
    },
  );

  testWidgets('bounded timeout permits retry and late response stays ignored', (
    tester,
  ) async {
    final pending = Completer<String?>();
    var calls = 0;
    await mount(
      tester,
      () => ++calls == 1 ? pending.future : Future.value('3.0.0'),
    );
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取版本，请重试。'), findsOneWidget);
    await tester.tap(find.byKey(const Key('client-version-retry')));
    await tester.pumpAndSettle();
    pending.complete('old');
    await tester.pumpAndSettle();
    expect(find.text('3.0.0'), findsOneWidget);
    expect(find.text('old'), findsNothing);
  });

  testWidgets('clipboard failure is visible and retryable', (tester) async {
    var fail = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData' && fail) {
          throw PlatformException(code: 'busy');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await mount(tester, () async => '1.0.0');
    await tester.tap(find.byKey(const Key('client-version-copy')));
    await tester.pumpAndSettle();
    expect(find.text('未能复制，请重试。'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('client-version-copy')));
    await tester.pumpAndSettle();
    expect(find.text('版本号已复制'), findsOneWidget);
  });

  testWidgets('button prevents repeated opening using same callback', (
    tester,
  ) async {
    final pending = Completer<void>();
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientVersionButton(
            open: (_) {
              opens++;
              return pending.future;
            },
          ),
        ),
      ),
    );
    final callback = tester
        .widget<OutlinedButton>(find.byKey(const Key('client-version-open')))
        .onPressed!;
    callback();
    callback();
    expect(opens, 1);
    pending.complete();
    await tester.pumpAndSettle();
  });

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('small window $locale $brightness', (tester) async {
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(
          tester,
          () async => '1.0.0+build.123456789',
          locale: locale,
          brightness: brightness,
        );
        expect(find.text('1.0.0+build.123456789'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
