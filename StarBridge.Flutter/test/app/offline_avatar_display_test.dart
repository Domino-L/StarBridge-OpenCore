import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/account_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_connection_mode_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/features/account/account_payload_decoder.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/shared/bounded_inline_avatar.dart';

import '../features/account/account_staged_read_test.dart'
    show StagedProfileHost;

import '../features/onboarding/connection_mode_test.dart'
    show ModePort, modeFact, modeWire;
import 'presence/direct_online_restore_flow_test.dart' show RetainedAccount;

const avatarBytes =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

void main() {
  const wirePath = String.fromEnvironment('STARBRIDGE_OFFLINE_AVATAR_WIRE');
  test(
    'actual Native warm and cold offline avatar wire reaches shell without account authority',
    () async {
      final fixtures = jsonDecode(File(wirePath).readAsStringSync()) as Map;
      DateTime? originalTime;
      for (final label in ['warm', 'cold']) {
        final envelope = BridgeEnvelope.fromJson(
          (fixtures[label] as Map).cast<String, Object?>(),
        );
        expect(envelope.accountContext, isNull);
        final fact = ConnectionModeWire.parse(
          envelope.payload,
          envelope.sessionGeneration,
        );
        expect(fact.offlineAccount!.avatarImageData, avatarBytes);
        originalTime ??= fact.offlineAccount!.avatarCachedAtUtc;
        expect(fact.offlineAccount!.avatarCachedAtUtc, originalTime);
        final port = ModePort()..current = fact;
        final mode = ConnectionModeController(port);
        final account = RetainedAccount(
          () => envelope.sessionGeneration,
          coldStart: true,
        );
        final chrome = AccountShellChrome(
          base: InMemoryShellChrome(
            initial: InMemoryShellChrome.connectedProjection,
          ),
          account: account,
        )..observeConnectionMode(mode);
        try {
          await mode.refresh();
          expect(chrome.projection.value.accountAvatarImageData, avatarBytes);
          expect(chrome.projection.value.accountLabel, 'Synthetic Pilot');
          expect(chrome.projection.value.accountSignedIn, isFalse);
          expect(chrome.projection.value.presenceKey, 'presence.offline');
        } finally {
          chrome.dispose();
          account.dispose();
          mode.dispose();
          await port.events.close();
        }
      }
    },
    skip: wirePath.isEmpty
        ? 'Requires actual Native offline avatar wire'
        : false,
  );

  test('media dimensions, decoded byte budget and original observation are bounded', () {
    final bytes = base64Decode(avatarBytes.substring(22));
    ByteData.sublistView(bytes).setUint32(16, 1025);
    for (final invalid in [
      'data:image/png;base64,${base64Encode(bytes)}',
      'data:image/png;base64,${base64Encode(Uint8List(512 * 1024 + 1))}',
      'file:///synthetic/avatar.png',
      'data:image/svg+xml;base64,PHN2Zz4=',
    ]) {
      expect(boundedInlineAvatar(invalid), isNull);
    }
    for (final time in [
      null,
      'invalid',
      '1970-01-01T00:00:00Z',
      '2099-01-01T00:00:00Z',
    ]) {
      expect(inlineAvatarObservedAt(time), isNull);
    }
    final jpeg = Uint8List(24)
      ..setRange(0, 11, [255, 216, 255, 192, 0, 17, 8, 0, 1, 0, 1]);
    final jpegData = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
    expect(boundedInlineAvatar(jpegData), jpegData);
    ByteData.sublistView(jpeg).setUint16(7, 1025);
    expect(
      boundedInlineAvatar('data:image/jpeg;base64,${base64Encode(jpeg)}'),
      isNull,
    );
  });

  test('retained root projection accepts optional bytes without creating account context', () {
    final display = {
      'displayName': 'Pilot',
      'cachedAtUtc': '2026-10-14T12:00:00Z',
      'avatarImageData': avatarBytes,
      'avatarCachedAtUtc': '2026-10-14T11:00:00Z',
      'readId': 'a' * 32,
    };
    final envelope = BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: 'account.getCurrent',
      sessionGeneration: 7,
      status: 'ok',
      payload: {'retainedDisplay': display},
    );
    final retained = AccountPayloadDecoder.retainedDisplay(
      envelope,
      AccountSessionState.credentialTemporarilyUnavailable,
    )!;
    expect(retained.profile.avatarImageData, avatarBytes);
    expect(retained.profile.email, isNull);
    expect(retained.readId, 'a' * 32);
    expect(
      () => AccountPayloadDecoder.retainedDisplay(
        envelope,
        AccountSessionState.signedOut,
      ),
      throwsA(isA<BridgeFormatException>()),
    );
  });
  for (final code in [
    'personal_profile.read_forbidden',
    'personal_profile.read_transient',
  ]) {
    test(
      'staged avatar failure is field scoped: $code',
      () async {
        final h = await StagedProfileHost.create();
        addTearDown(h.close);
        h.session.acceptHostCapabilities([
          ...h.session.hostCapabilities,
          'account.avatar.read',
        ]);
        h.extraReplies['account.readAvatar'] = {
          'schemaVersion': 1,
          'imageData': avatarBytes,
          'callSign': 'Pilot',
        };
        await h.module.initialize();
        for (var step = 0; step < 4; step++) {
          await h.preparation.prepareNextRead();
        }
        expect(h.module.projection.value.profile?.avatarImageData, avatarBytes);
        h.extraReplies.remove('account.readAvatar');
        h.extraErrors['account.readAvatar'] = BridgeErrorBody(
          code: code,
          message: 'Synthetic field read failure',
          retryable: code.endsWith('transient'),
        );
        await h.module.refresh();
        for (var step = 0; step < 4; step++) {
          await h.preparation.prepareNextRead();
        }
        expect(
          h.module.projection.value.profile?.avatarImageData,
          code.endsWith('transient') ? avatarBytes : isNull,
        );
        expect(h.module.projection.value.isSignedIn, isTrue);
        expect(h.module.projection.value.profile, isNotNull);
      },
      skip:
          const String.fromEnvironment('STARBRIDGE_STAGED_PROFILE_WIRE').isEmpty
          ? 'Requires actual staged Native wire'
          : false,
    );
  }
  for (final image in <String?>[
    avatarBytes,
    'https://invalid.example/avatar',
    'data:image/png;base64,bad!',
    null,
  ]) {
    test(
      'offline chrome uses bounded actual bytes, optional media: $image',
      () async {
        final port = ModePort()
          ..current = ConnectionModeWire.parse({
            ...modeWire('offline'),
            'offlineAccount': {
              'displayName': 'Retained Pilot',
              'cachedAtUtc': '2026-10-14T12:00:00Z',
              'avatarImageData': image,
              'avatarCachedAtUtc': '2026-10-14T11:00:00Z',
            },
          }, 7);
        final mode = ConnectionModeController(port);
        final account = RetainedAccount(() => 7, coldStart: true);
        final chrome = AccountShellChrome(
          base: InMemoryShellChrome(
            initial: InMemoryShellChrome.connectedProjection,
          ),
          account: account,
        )..observeConnectionMode(mode);
        addTearDown(() async {
          chrome.dispose();
          account.dispose();
          mode.dispose();
          await port.events.close();
        });
        await mode.refresh();
        expect(chrome.projection.value.accountLabel, 'Retained Pilot');
        expect(
          chrome.projection.value.accountAvatarImageData,
          image == avatarBytes ? avatarBytes : isNull,
        );
        expect(chrome.projection.value.accountSignedIn, isFalse);
        expect(chrome.projection.value.presenceKey, 'presence.offline');
        port.current = modeFact('local');
        await mode.refresh();
        expect(chrome.projection.value.accountAvatarImageData, isNull);
        expect(chrome.projection.value.accountLabel, isEmpty);
      },
    );
  }
}
