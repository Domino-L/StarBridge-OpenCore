import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/hangar/cached_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_cloud.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';

base class _Port implements LocalHangarCloudPort {
  _Port(this.state);
  LocalHangarCloudState state;
  final calls = <String>[];
  Future<void>? gate;

  @override
  Future<LocalHangarCloudState> readCloud() async {
    calls.add('read');
    await gate;
    return state;
  }

  @override
  Future<LocalHangarCloudState> acknowledgeCloud(String notice) async {
    calls.add('ack:$notice');
    return state = LocalHangarCloudState(available: state.available);
  }
}

Widget _app(_Port port, {Locale locale = const Locale('zh', 'CN')}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      home: Scaffold(body: LocalHangarCloudBar(port: port, revision: 1)),
    );

void main() {
  wrapperTests();
  // User 11-05: the account copy is not optional; no switch, no dialog.
  testWidgets('available: account line and never a switch', (tester) async {
    final port = _Port(const LocalHangarCloudState(available: true));
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hangar-cloud-switch')), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.textContaining('机库已保存到你的账号'), findsOneWidget);
    expect(find.textContaining('只保存在这台电脑'), findsNothing);
    expect(port.calls, ['read']);
  });

  testWidgets('unavailable (legacy or before the HK release): local line', (
    tester,
  ) async {
    final port = _Port(const LocalHangarCloudState(available: false));
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hangar-cloud-switch')), findsNothing);
    expect(find.textContaining('机库只保存在这台电脑上'), findsOneWidget);
  });

  testWidgets('the line says nothing until the first answer arrives', (
    tester,
  ) async {
    final answer = Completer<void>();
    final port = _Port(const LocalHangarCloudState(available: true))
      ..gate = answer.future;
    await tester.pumpWidget(_app(port));
    await tester.pump();
    final line = find.byKey(const Key('hangar-device-storage'));
    expect(
      tester
          .widget<Visibility>(
            find.ancestor(of: line, matching: find.byType(Visibility)),
          )
          .visible,
      isFalse,
    );
    answer.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Visibility>(
            find.ancestor(of: line, matching: find.byType(Visibility)),
          )
          .visible,
      isTrue,
    );
    expect(find.textContaining('机库已保存到你的账号'), findsOneWidget);
  });

  testWidgets(
    'first upload and restore notices show once and are acknowledged',
    (tester) async {
      final port = _Port(
        const LocalHangarCloudState(available: true, firstUploadNotice: true),
      );
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('hangar-cloud-notice-firstUpload')),
        findsOneWidget,
      );
      expect(find.textContaining('仍然按你的共享设置'), findsOneWidget);
      expect(port.calls, contains('ack:firstUpload'));

      final restored = _Port(
        const LocalHangarCloudState(available: true, restoredShips: 12),
      );
      // A fresh page (as after an account change), so the earlier notice is gone.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(restored, locale: const Locale('en')));
      await tester.pumpAndSettle();
      expect(
        find.text('Loaded the hangar saved to your account (12 ships).'),
        findsOneWidget,
      );
      expect(restored.calls, contains('ack:restored'));
    },
  );
}

final class _Both extends _Port implements LocalHangarPort {
  _Both(super.state);
  @override
  Future<LocalHangarSnapshot> read() async => throw UnimplementedError();
  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) async => throw UnimplementedError();
}

void wrapperTests() {
  test('the page wrapper forwards the account copy while current', () async {
    var current = true;
    final source = _Both(const LocalHangarCloudState(available: true));
    final cached = CachedLocalHangar(source, isCurrent: () => current);
    expect(cached, isA<LocalHangarCloudPort>());
    expect((await cached.readCloud()).available, isTrue);
    expect(source.calls, ['read']);
    current = false;
    expect((await cached.readCloud()).available, isFalse);
    expect(source.calls, ['read'], reason: 'nothing reaches an old account');
  });
}
