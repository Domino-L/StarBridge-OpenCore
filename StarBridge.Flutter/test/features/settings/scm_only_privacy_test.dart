import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/account_card_title.dart';
import 'package:starbridge_flutter/features/settings/event_sharing_controller.dart';
import 'package:starbridge_flutter/features/settings/recently_played_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/recently_played_privacy_setting.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../gameplay_time/gameplay_time_test.dart' as support;

String _recentScmOnly(bool migrationOffered) =>
    '这个 SCM 账号还没有关联旧账号，暂时设置不了“最近一起玩”。其他设置不受影响。'
    '有旧账号的，可以到 设置 › 账号与识别 › '
    '${migrationOffered ? '迁移旧账号' : '旧数据兼容'}。';
const _recentIdentity = '账号状态已变化，请重新登录后再试。';

void main() {
  for (final scmOnly in [true, false]) {
    test(
      'event sharing refusal ${scmOnly ? 'is SCM-only and stops rechecking' : 'keeps rechecking'}',
      () {
        fakeAsync((async) {
          final host = _EventHost();
          final flag = ValueNotifier(scmOnly);
          final controller = EventSharingController(
            host.session,
            scmOnly: flag,
          );
          async.flushMicrotasks();
          expect(controller.error, 'events.identity_unavailable');
          expect(controller.scmOnlyUnavailable, scmOnly);
          final reads = host.reads;
          async.elapse(const Duration(seconds: 16));
          expect(host.reads, scmOnly ? reads : greaterThan(reads));
          controller.dispose();
          unawaited(host.close());
          async.flushMicrotasks();
          flag.dispose();
        });
      },
    );
  }

  test('event sharing controller follows a later SCM-only answer', () {
    fakeAsync((async) {
      final host = _EventHost();
      final flag = ValueNotifier(false);
      final controller = EventSharingController(host.session, scmOnly: flag);
      async.flushMicrotasks();
      expect(controller.error, 'events.identity_unavailable');
      expect(controller.scmOnlyUnavailable, isFalse);
      var notified = 0;
      controller.addListener(() => notified++);
      flag.value = true;
      expect(controller.scmOnlyUnavailable, isTrue);
      expect(notified, 1);
      controller.dispose();
      flag.value = false;
      expect(notified, 1, reason: 'a disposed controller stops listening');
      unawaited(host.close());
      async.flushMicrotasks();
      flag.dispose();
    });
  });

  for (final (scmOnly, offered) in [
    (true, false),
    (true, true),
    (false, false),
  ]) {
    testWidgets(
      'recent players refusal reads as ${scmOnly ? 'SCM-only' : 'a changed account'}'
      '${offered ? ', migration offered' : ''}',
      (tester) async {
        final module = RecentlyPlayedPrivacyModule(_RecentPort());
        await module.initialize();
        final flag = ValueNotifier(false);
        final migration = ValueNotifier(offered);
        await tester.pumpWidget(
          support.app(
            AccountCardTitle(
              migrationOffered: migration,
              child: RecentlyPlayedPrivacySetting(
                module: module,
                scmOnly: flag,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text(_recentIdentity), findsOneWidget);
        flag.value = scmOnly;
        await tester.pump();
        expect(
          find.text(_recentScmOnly(offered)),
          scmOnly ? findsOneWidget : findsNothing,
        );
        expect(find.text(_recentScmOnly(!offered)), findsNothing);
        expect(
          find.text(_recentIdentity),
          scmOnly ? findsNothing : findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        module.dispose();
        flag.dispose();
        migration.dispose();
      },
    );
  }
}

final class _RecentPort implements RecentlyPlayedPrivacyPort {
  final _changes = StreamController<void>.broadcast();
  @override
  Stream<void> get invalidations => _changes.stream;
  @override
  Future<RecentlyPlayedPrivacySnapshot> read() async =>
      const RecentlyPlayedPrivacySnapshot.unavailable(
        RecentlyPlayedPrivacyFailure.identityUnavailable,
      );
  @override
  Future<RecentlyPlayedPrivacyWriteResult> save(
    bool enabled,
    int expectedRevision,
  ) async => const RecentlyPlayedPrivacyWriteResult.rejected(
    RecentlyPlayedPrivacyFailure.identityUnavailable,
  );
  @override
  Future<void> close() => _changes.close();
}

final class _EventHost {
  _EventHost() {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 4)
      ..acceptHostCapabilities(const ['eventSharing.settings']);
    subscription = connection.incoming.listen((request) {
      if (request.name == 'bridge.cancel') return;
      if (request.name == 'eventSharing.read') reads++;
      final account = request.name == 'account.getCurrent';
      unawaited(
        connection.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            accountContext: const BridgeAccountContext(
              environment: 'test',
              authority: 'scm',
              subject: 'synthetic-owner',
            ),
            status: account ? 'ok' : 'error',
            error: account
                ? null
                : const BridgeErrorBody(
                    code: 'events.identity_unavailable',
                    message: 'fixture',
                    retryable: false,
                  ),
            payload: account
                ? const {'schemaVersion': 1, 'state': 'signedIn'}
                : const {},
          ),
        ),
      );
    });
  }
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  int reads = 0;

  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await connection.close();
  }
}
