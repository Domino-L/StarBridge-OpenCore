import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/settings/client_license.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3aa_test.dart' show reader;
import 'interaction_batch3dj_test.dart'
    show activate, visibleFrames, remove, licenseHost, versionHost;

Future<void> input(
  WidgetTester t,
  String key,
  String label,
  String source,
) async {
  if (source == 'reader') {
    reader(t, label);
    return;
  }
  await activate(t, key, keyboard: source == 'keyboard');
}

StarBridgeActionButton action(WidgetTester t, String key) =>
    t.widget<StarBridgeActionButton>(
      find.byWidgetPredicate(
        (w) => w is StarBridgeActionButton && w.controlKey == Key(key),
      ),
    );
void waitMode(WidgetTester t, bool moving) {
  expect(find.byType(HelpSupportWaiting), findsOneWidget);
  expect(find.byType(SuiteProgressBar), moving ? findsOneWidget : findsNothing);
  if (!moving) expect(t.hasRunningAnimations, isFalse);
}

void mockCopy(WidgetTester t, Future<Object?> Function(MethodCall) handler) {
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    handler,
  );
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final license in [false, true]) {
      final prefix = license ? 'client-license' : 'client-version';
      final openLabel = license ? '查看使用条款与声明' : '查看当前版本';
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite $prefix $source admitted wait follows live reduce and stays one read',
          (t) async {
            size(t, const Size(1000, 900));
            final licenseRead = Completer<ClientLicenseDocument>(),
                versionRead = Completer<String?>();
            var calls = 0;
            Future<ClientLicenseDocument> readLicense() {
              calls++;
              return licenseRead.future;
            }

            Future<String?> readVersion() {
              calls++;
              return versionRead.future;
            }

            Widget host(bool reduce) => license
                ? licenseHost(suite, readLicense, reduce: reduce)
                : versionHost(suite, readVersion, reduce: reduce);
            final semantics = t.ensureSemantics();
            await t.pumpWidget(host(false));
            await t.pumpAndSettle();
            await input(t, '$prefix-open', openLabel, source);
            await visibleFrames(t);
            expect(calls, 1);
            waitMode(t, source == 'pointer');
            expect(action(t, '$prefix-retry').onActivate, isNull);
            await t.tapAt(t.getCenter(find.byKey(Key('$prefix-retry'))));
            await t.pump();
            expect(calls, 1);
            await t.pumpWidget(host(true));
            await t.pump();
            await t.pump();
            waitMode(t, false);
            expect(calls, 1);
            await t.pumpWidget(host(false));
            await t.pump();
            await t.pump();
            waitMode(t, source == 'pointer');
            if (license) {
              licenseRead.complete(
                const ClientLicenseDocument(
                  ClientLicenseState.ready,
                  'Exact terms\r\n完整许可',
                ),
              );
            } else {
              versionRead.complete('9.8.7+exact');
            }
            await t.pumpAndSettle();
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(
              find.text(license ? 'Exact terms\r\n完整许可' : '9.8.7+exact'),
              findsOneWidget,
            );
            expect(calls, 1);
            await remove(t);
            semantics.dispose();
            expect(t.takeException(), isNull);
          },
        );
      }
      testWidgets(
        '$suite $prefix retry gets new source but stale callback cannot duplicate request',
        (t) async {
          size(t, const Size(1000, 900));
          final requests = <Completer<Object?>>[];
          Future<Object?> read() {
            final c = Completer<Object?>();
            requests.add(c);
            return c.future;
          }

          final semantics = t.ensureSemantics();
          await t.pumpWidget(
            license
                ? licenseHost(
                    suite,
                    () async => (await read()) as ClientLicenseDocument,
                  )
                : versionHost(suite, () async => (await read()) as String?),
          );
          await t.pumpAndSettle();
          await input(t, '$prefix-open', openLabel, 'keyboard');
          await visibleFrames(t);
          waitMode(t, false);
          requests.single.complete(
            license
                ? const ClientLicenseDocument(ClientLicenseState.missing)
                : null,
          );
          await t.pumpAndSettle();
          final stale = action(t, '$prefix-retry').onActivate!;
          await activate(t, '$prefix-retry');
          await visibleFrames(t);
          expect(requests, hasLength(2));
          waitMode(t, true);
          stale(InteractionSource.pointer);
          await t.pump();
          expect(requests, hasLength(2));
          requests.last.complete(
            license
                ? const ClientLicenseDocument(ClientLicenseState.unreadable)
                : null,
          );
          await t.pumpAndSettle();
          await input(t, '$prefix-retry', license ? '重试' : '重新读取', 'reader');
          await visibleFrames(t);
          waitMode(t, false);
          expect(requests, hasLength(3));
          requests.last.complete(
            license
                ? const ClientLicenseDocument(
                    ClientLicenseState.ready,
                    'Recovered exact terms',
                  )
                : '3.2.1+recovered',
          );
          await t.pumpAndSettle();
          expect(
            find.text(license ? 'Recovered exact terms' : '3.2.1+recovered'),
            findsOneWidget,
          );
          await remove(t);
          semantics.dispose();
          expect(t.takeException(), isNull);
        },
      );
      testWidgets(
        '$suite $prefix original 15s timeout permits explicit retry and rejects late old result',
        (t) async {
          size(t, const Size(1000, 900));
          final first = Completer<Object?>(), second = Completer<Object?>();
          var calls = 0;
          Future<Object?> read() => ++calls == 1 ? first.future : second.future;
          await t.pumpWidget(
            license
                ? licenseHost(
                    suite,
                    () async => (await read()) as ClientLicenseDocument,
                  )
                : versionHost(suite, () async => (await read()) as String?),
          );
          await t.pumpAndSettle();
          await activate(t, '$prefix-open');
          await visibleFrames(t);
          await t.pump(const Duration(seconds: 16));
          await t.pumpAndSettle();
          expect(calls, 1);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          expect(action(t, '$prefix-retry').onActivate, isNotNull);
          await activate(t, '$prefix-retry', keyboard: true);
          await visibleFrames(t);
          waitMode(t, false);
          first.complete(
            license
                ? const ClientLicenseDocument(
                    ClientLicenseState.ready,
                    'STALE TERMS',
                  )
                : 'stale',
          );
          await t.pump();
          await t.pump();
          expect(find.textContaining('STALE'), findsNothing);
          expect(find.text('stale'), findsNothing);
          expect(find.byType(HelpSupportWaiting), findsOneWidget);
          second.complete(
            license
                ? const ClientLicenseDocument(
                    ClientLicenseState.ready,
                    'Current terms',
                  )
                : 'new',
          );
          await t.pumpAndSettle();
          expect(find.text(license ? 'Current terms' : 'new'), findsOneWidget);
          expect(calls, 2);
          await remove(t);
          expect(t.takeException(), isNull);
        },
      );
      for (final leaving in ['escape', 'unmount']) {
        testWidgets(
          '$suite $prefix pending $leaving ignores late read and removes wait',
          (t) async {
            size(t, const Size(1000, 900));
            final read = Completer<Object?>();
            var calls = 0;
            Future<Object?> pending() {
              calls++;
              return read.future;
            }

            await t.pumpWidget(
              license
                  ? licenseHost(
                      suite,
                      () async => (await pending()) as ClientLicenseDocument,
                    )
                  : versionHost(
                      suite,
                      () async => (await pending()) as String?,
                    ),
            );
            await t.pumpAndSettle();
            await activate(t, '$prefix-open');
            await visibleFrames(t);
            if (leaving == 'escape') {
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
              await t.pump();
              await t.pump();
            } else {
              await remove(t);
            }
            expect(find.byKey(Key('$prefix-dialog')), findsNothing);
            read.complete(
              license
                  ? const ClientLicenseDocument(
                      ClientLicenseState.ready,
                      'Late terms',
                    )
                  : 'late',
            );
            await t.pumpAndSettle();
            expect(find.text('Late terms'), findsNothing);
            expect(find.text('late'), findsNothing);
            expect(calls, 1);
            await remove(t);
            expect(t.takeException(), isNull);
          },
        );
      }
    }
    for (final source in ['keyboard', 'reader']) {
      testWidgets(
        '$suite $source copy failure stays static and pointer retry waits for true success',
        (t) async {
          size(t, const Size(1000, 900));
          final requests = <Completer<void>>[];
          final payloads = <String>[];
          var reads = 0;
          mockCopy(t, (call) async {
            if (call.method == 'Clipboard.setData') {
              payloads.add((call.arguments as Map)['text'] as String);
              final c = Completer<void>();
              requests.add(c);
              await c.future;
            }
            return null;
          });
          final semantics = t.ensureSemantics();
          await t.pumpWidget(
            versionHost(suite, () async {
              reads++;
              return '2.3.4+copy';
            }),
          );
          await t.pumpAndSettle();
          await activate(t, 'client-version-open');
          await t.pumpAndSettle();
          await input(t, 'client-version-copy', '复制版本号', source);
          await visibleFrames(t);
          waitMode(t, false);
          expect(find.text('2.3.4+copy'), findsOneWidget);
          expect(action(t, 'client-version-copy').onActivate, isNull);
          expect(action(t, 'client-version-retry').onActivate, isNull);
          requests.single.completeError(
            PlatformException(code: 'busy', message: 'private detail'),
          );
          await t.pumpAndSettle();
          expect(find.text('未能复制，请重试。'), findsOneWidget);
          expect(find.textContaining('private detail'), findsNothing);
          final result = t
              .getSemantics(find.text('未能复制，请重试。'))
              .getSemanticsData();
          expect(result.flagsCollection.isLiveRegion, isTrue);
          await activate(t, 'client-version-copy');
          await visibleFrames(t);
          waitMode(t, true);
          expect(reads, 1);
          expect(payloads, ['2.3.4+copy', '2.3.4+copy']);
          requests.last.complete();
          await t.pumpAndSettle();
          expect(find.text('版本号已复制'), findsOneWidget);
          await remove(t);
          semantics.dispose();
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets(
      '$suite copy timeout is 5s and late completion cannot finish a new copy',
      (t) async {
        size(t, const Size(1000, 900));
        final requests = <Completer<void>>[];
        var reads = 0;
        mockCopy(t, (call) async {
          if (call.method == 'Clipboard.setData') {
            final c = Completer<void>();
            requests.add(c);
            await c.future;
          }
          return null;
        });
        await t.pumpWidget(
          versionHost(suite, () async {
            reads++;
            return 'exact';
          }),
        );
        await t.pumpAndSettle();
        await activate(t, 'client-version-open');
        await t.pumpAndSettle();
        await activate(t, 'client-version-copy');
        await visibleFrames(t);
        await t.pump(const Duration(seconds: 5));
        await t.pumpAndSettle();
        expect(find.text('未能复制，请重试。'), findsOneWidget);
        await activate(t, 'client-version-copy');
        await visibleFrames(t);
        requests.first.complete();
        await t.pump();
        await t.pump();
        expect(find.text('版本号已复制'), findsNothing);
        expect(find.text('正在复制…'), findsOneWidget);
        expect(reads, 1);
        requests.last.complete();
        await t.pumpAndSettle();
        expect(find.text('版本号已复制'), findsOneWidget);
        await remove(t);
        expect(t.takeException(), isNull);
      },
    );
    for (final leaving in ['escape', 'unmount']) {
      testWidgets('$suite pending copy $leaving ignores late platform answer', (
        t,
      ) async {
        size(t, const Size(1000, 900));
        final copy = Completer<void>();
        mockCopy(t, (call) async {
          if (call.method == 'Clipboard.setData') await copy.future;
          return null;
        });
        await t.pumpWidget(versionHost(suite, () async => 'exact'));
        await t.pumpAndSettle();
        await activate(t, 'client-version-open');
        await t.pumpAndSettle();
        await activate(t, 'client-version-copy');
        await visibleFrames(t);
        if (leaving == 'escape') {
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
        } else {
          await remove(t);
        }
        expect(find.byKey(const Key('client-version-dialog')), findsNothing);
        copy.complete();
        await t.pumpAndSettle();
        expect(find.text('版本号已复制'), findsNothing);
        await remove(t);
        expect(t.takeException(), isNull);
      });
    }
  }
}
