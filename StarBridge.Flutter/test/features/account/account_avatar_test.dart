import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/account/account_avatar_editor.dart';
import 'package:starbridge_flutter/features/account/account_avatar.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

void main() {
  testWidgets('avatar editor crops and confirms a separate account update', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final connection = _Connection();
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 7,
    )..acceptHostCapabilities({'account.avatar', 'account.avatarImages'});
    addTearDown(session.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(
          body: AccountAvatarScope(
            port: AccountAvatarPort(session),
            imageData: null,
            editable: true,
            child: const AccountAvatarEditor(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-change-account-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('采用图片'));
    await tester.pumpAndSettle();
    expect(
      connection.requests.any((r) => r.name == 'account.updateAvatar'),
      isFalse,
    );
    expect(find.textContaining('此操作会单独保存'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '更换账号头像'));
    await tester.pumpAndSettle();
    expect(find.text('账号头像已更换。'), findsOneWidget);
    expect(
      connection.requests.where((r) => r.name == 'account.updateAvatar').length,
      1,
    );
    expect(tester.takeException(), isNull);
  });
  test(
    'avatar selection, crop and confirmed write stay on the account boundary',
    () async {
      final connection = _Connection();
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 7,
      )..acceptHostCapabilities({'account.avatar', 'account.avatarImages'});
      addTearDown(session.close);
      final port = AccountAvatarPort(session);
      final source = await port.pickLogo();
      final crop = await port.cropLogo(source!.sourceRef, 0, 0, 1);
      await port.save(crop);
      await port.clearLogo();
      expect(connection.requests.map((r) => r.name), [
        'account.getCurrent',
        'account.pickAvatar',
        'account.cropAvatar',
        'account.updateAvatar',
        'account.clearAvatarDraft',
      ]);
      expect(
        connection.requests
            .skip(1)
            .every((r) => r.accountContext?.subject == 'owner'),
        isTrue,
      );
      expect(connection.requests[3].payload, {
        'schemaVersion': 1,
        'imageData': 'test-crop',
      });
      await expectLater(port.save(crop), throwsFormatException);
    },
  );
  test('account switch during selection prevents crop or write for another account', () async {
    final connection = _Connection();
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 7,
    )..acceptHostCapabilities({'account.avatar', 'account.avatarImages'});
    addTearDown(session.close);
    final port = AccountAvatarPort(session);
    await port.pickLogo();
    connection.stream.add(
      BridgeEnvelope.fromJson({
        'protocolVersion': 1,
        'messageType': 'event',
        'name': 'account.changed',
        'sessionGeneration': 8,
        'sequence': 1,
        'payload': {'schemaVersion': 1},
      }),
    );
    await Future<void>.delayed(Duration.zero);
    await expectLater(port.save('test-crop'), throwsFormatException);
    expect(
      connection.requests.any((r) => r.name == 'account.updateAvatar'),
      isFalse,
    );
  });
  test('SCM and cancelled picks do not write avatars', () async {
    final connection = _Connection()..state = 'signedIn';
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 7,
    )..acceptHostCapabilities({'account.avatar', 'account.avatarImages'});
    addTearDown(session.close);
    final port = AccountAvatarPort(session);
    await expectLater(port.pickLogo(), throwsFormatException);
    expect(connection.requests.length, 1);
    connection.state = 'legacySignedIn';
    connection.cancel = true;
    expect(await port.pickLogo(), isNull);
    await port.clearLogo();
    expect(
      connection.requests.any((r) => r.name == 'account.updateAvatar'),
      isFalse,
    );
  });
}

class _Connection implements BridgeConnection {
  final stream = StreamController<BridgeEnvelope>.broadcast();
  final requests = <BridgeEnvelope>[];
  String state = 'legacySignedIn';
  bool cancel = false;
  @override
  Stream<BridgeEnvelope> get incoming => stream.stream;
  @override
  Future<void> close() => stream.close();
  @override
  Future<void> send(BridgeEnvelope request) async {
    requests.add(request);
    stream.add(
      BridgeEnvelope.fromJson({
        'protocolVersion': 1,
        'messageType': 'response',
        'name': request.name,
        'correlationId': request.correlationId,
        'sessionGeneration': 7,
        'status': 'ok',
        'accountContext': {
          'environment': 'test',
          'authority': 'relay',
          'subject': 'owner',
        },
        'payload': {
          'schemaVersion': 1,
          'state': state,
          'imageData': 'test-crop',
          'status': cancel ? 'cancelled' : 'selected',
          'source': {
            'sourceRef': 'source',
            'previewImageData': 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            'width': 256,
            'height': 256,
          },
        },
      }),
    );
  }
}
