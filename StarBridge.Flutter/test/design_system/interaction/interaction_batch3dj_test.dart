import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/client_license.dart';
import 'package:starbridge_flutter/features/settings/client_license_dialog.dart';
import 'package:starbridge_flutter/features/settings/client_version_dialog.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

Future<void> activate(
  WidgetTester t,
  String key, {
  bool keyboard = false,
}) async {
  final target = find.byKey(Key(key));
  if (!keyboard) {
    await t.tap(target);
    return;
  }
  final widget = t.widget(target);
  final node = switch (widget) {
    ButtonStyleButton button => button.focusNode!,
    SuitePressable pressable => pressable.focusNode!,
    _ => throw StateError('No focus owner at $key'),
  };
  node.requestFocus();
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
}

Future<void> visibleFrames(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 700));
  await t.pump();
}

Future<void> remove(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

Widget licenseHost(
  InteractionSuite suite,
  ClientLicenseRead read, {
  bool reduce = false,
}) => scopedApp(
  ClientLicenseButton(
    open: (context) => showClientLicenseDialog(context, read: read),
  ),
  suite,
  reduce: reduce,
);
Widget versionHost(
  InteractionSuite suite,
  ClientVersionRead read, {
  bool reduce = false,
}) => scopedApp(
  ClientVersionButton(
    open: (context) => showClientVersionDialog(context, read: read),
  ),
  suite,
  reduce: reduce,
);

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite keyboard license loading has no decorative ticker', (
      t,
    ) async {
      size(t, const Size(1000, 900));
      final read = Completer<ClientLicenseDocument>();
      var calls = 0;
      await t.pumpWidget(
        licenseHost(suite, () {
          calls++;
          return read.future;
        }),
      );
      await t.pumpAndSettle();
      await activate(t, 'client-license-open', keyboard: true);
      await visibleFrames(t);
      expect(calls, 1);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('正在读取…'), findsOneWidget);
      expect(t.hasRunningAnimations, isFalse);
      await remove(t);
      read.complete(const ClientLicenseDocument(ClientLicenseState.missing));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
    testWidgets(
      '$suite pointer version read has suite wait without fake progress',
      (t) async {
        size(t, const Size(1000, 900));
        final read = Completer<String?>();
        await t.pumpWidget(versionHost(suite, () => read.future));
        await t.pumpAndSettle();
        await activate(t, 'client-version-open');
        await visibleFrames(t);
        expect(find.byType(HelpSupportWaiting), findsOneWidget);
        expect(
          t.widget<SuiteProgressBar>(find.byType(SuiteProgressBar)).value,
          isNull,
        );
        expect(find.text('正在读取…'), findsOneWidget);
        await remove(t);
        read.complete('1.2.3+exact');
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite pointer copy stays waiting for actual platform receipt',
      (t) async {
        size(t, const Size(1000, 900));
        final clipboard = Completer<void>();
        String? copied;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
              await clipboard.future;
            }
            return null;
          },
        );
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await t.pumpWidget(versionHost(suite, () async => '1.2.3+exact'));
        await t.pumpAndSettle();
        await activate(t, 'client-version-open');
        await t.pumpAndSettle();
        await activate(t, 'client-version-copy');
        await visibleFrames(t);
        expect(copied, '1.2.3+exact');
        expect(find.text('版本号已复制'), findsNothing);
        expect(find.text('正在复制…'), findsOneWidget);
        expect(find.byType(HelpSupportWaiting), findsOneWidget);
        clipboard.complete();
        await t.pumpAndSettle();
        expect(find.text('版本号已复制'), findsOneWidget);
        expect(find.byType(HelpSupportWaiting), findsNothing);
        await remove(t);
        expect(t.takeException(), isNull);
      },
    );
  }
}
