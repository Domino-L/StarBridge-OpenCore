import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_avatar_read_preparation.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const _owner = BridgeAccountContext(
  environment: 'synthetic',
  authority: 'scm',
  subject: 'pilot',
);
const _image = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB';

void main() {
  test('avatar lane is owner scoped, read only and does not duplicate a completed read', () async {
    final h = _Host();
    addTearDown(h.close);
    final pending = h.read.read(_owner, 7);
    await Future<void>.delayed(Duration.zero);
    expect(await h.read.read(_owner, 7), isNull);
    h.reply();
    final result = (await pending)!;
    expect(result.hasPresentation, isTrue);
    expect(
      result.matches(
        const AccountRoute(
          environment: 'synthetic',
          authority: 'scm',
          subject: 'pilot',
        ),
        7,
      ),
      isTrue,
    );
    expect(
      result.matches(
        const AccountRoute(
          environment: 'synthetic',
          authority: 'scm',
          subject: 'other',
        ),
        7,
      ),
      isFalse,
    );
    final presentation = result.apply(
      const AccountProfile(email: 'synthetic@example.invalid', locale: 'en-US'),
    );
    expect(presentation.avatarImageData, _image);
    expect(presentation.displayName, 'Current pilot');
    expect(presentation.email, 'synthetic@example.invalid');
    expect(presentation.locale, 'en-US');
    expect(await h.read.read(_owner, 7), isNull);
    expect(h.requests.map((r) => r.name), ['account.readAvatar']);
  });
  test('a call sign survives when the Bridge drops a null image, and the reverse', () async {
    final noImage = _Host();
    addTearDown(noImage.close);
    final named = noImage.read.read(_owner, 7);
    await Future<void>.delayed(Duration.zero);
    noImage.reply(image: null, dropNulls: true);
    final namedResult = (await named)!;
    expect(namedResult.callSign, 'Current pilot');
    expect(namedResult.imageData, isNull);
    final noName = _Host();
    addTearDown(noName.close);
    final pictured = noName.read.read(_owner, 7);
    await Future<void>.delayed(Duration.zero);
    noName.reply(name: null, dropNulls: true);
    final picturedResult = (await pictured)!;
    expect(picturedResult.imageData, _image);
    expect(picturedResult.callSign, isNull);
  });
  test('transient failure retains presentation and retries only when admitted explicitly', () async {
    final h = _Host();
    addTearDown(h.close);
    final first = h.read.read(_owner, 7);
    await Future<void>.delayed(Duration.zero);
    h.reply(
      error: const BridgeErrorBody(
        code: 'personal_profile.read_transient',
        message: 'Synthetic outage',
        retryable: true,
      ),
    );
    final failure = (await first)!;
    expect(failure.retryable, isTrue);
    expect(failure.hasPresentation, isFalse);
    expect(h.read.confirmed, isNull);
    expect(await h.read.read(_owner, 7), isNull);
    final retry = h.read.read(_owner, 7, retry: true);
    await Future<void>.delayed(Duration.zero);
    h.reply();
    expect((await retry)!.imageData, _image);
    expect(h.requests.length, 2);
  });
  test('cancelled or retired work cannot publish late presentation', () async {
    for (final retire in [false, true]) {
      final h = _Host();
      final pending = h.read.read(_owner, 7);
      await Future<void>.delayed(Duration.zero);
      if (retire) {
        h.session.advanceGeneration(8);
      } else {
        h.read.cancel();
      }
      h.reply();
      expect(await pending, isNull);
      expect(h.read.confirmed, isNull);
      await h.close();
    }
  });
  test('confirmed removal and denied photo clear only presentation', () async {
    for (final denied in [false, true]) {
      final h = _Host();
      addTearDown(h.close);
      final pending = h.read.read(_owner, 7);
      await Future<void>.delayed(Duration.zero);
      h.reply(
        image: null,
        error: denied
            ? const BridgeErrorBody(
                code: 'personal_profile.read_forbidden',
                message: 'Synthetic denial',
                retryable: false,
              )
            : null,
      );
      final result = (await pending)!;
      expect(result.hasPresentation, isTrue);
      expect(
        result
            .apply(const AccountProfile(avatarImageData: _image))
            .avatarImageData,
        isNull,
      );
    }
  });
  test('malformed name never becomes visible and invalidation permits a fresh read', () async {
    final h = _Host();
    addTearDown(h.close);
    final pending = h.read.read(_owner, 7);
    await Future<void>.delayed(Duration.zero);
    h.reply(name: 'invalid\nname');
    expect((await pending)!.callSign, isNull);
    h.read.invalidate();
    final next = h.read.read(_owner, 7);
    await Future<void>.delayed(Duration.zero);
    h.reply();
    expect((await next)!.callSign, 'Current pilot');
  });
}

final class _Host {
  _Host() {
    incoming = pair.host.incoming.listen((request) {
      if (request.name == 'account.readAvatar') requests.add(request);
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 7,
  );
  late final read = AccountAvatarReadPreparation(session);
  late final StreamSubscription<BridgeEnvelope> incoming;
  final requests = <BridgeEnvelope>[];
  void reply({
    String? image = _image,
    String? name = 'Current pilot',
    BridgeErrorBody? error,
    bool dropNulls = false,
  }) {
    final request = requests.last;
    unawaited(
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: request.accountContext,
          status: error == null ? 'ok' : 'error',
          payload: {
            'schemaVersion': 1,
            if (image != null || !dropNulls) 'imageData': image,
            if (name != null || !dropNulls) 'callSign': name,
          },
          error: error,
        ),
      ),
    );
  }

  Future<void> close() async {
    read.cancel();
    await incoming.cancel();
    await session.close();
    await pair.host.close();
  }
}
