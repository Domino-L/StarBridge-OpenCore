import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/community_bridge_composition.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/bridge_account_adapter.dart';
import 'package:starbridge_flutter/features/communities/bridge_communities.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'community_offline_directory_test.dart' show offlineLogo;
import 'community_workspace_test.dart' show WorkspaceTestPort;

/// Runs the real account adapter/module, composition and community module.
/// The finite Host models Native's existing rule: a new root read retires
/// the previous display selection even when the generation has not changed.
class RetainedRenewalHost {
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 7,
  );
  late final account = createAccountModule(BridgeAccountAdapter(session));
  late final BridgeCommunities port;
  late final CommunitiesModule model;
  late final StreamSubscription<BridgeEnvelope> incoming;
  final seen = <BridgeEnvelope>[];
  final oldStarted = Completer<void>(), releaseOld = Completer<void>();
  String? current;
  int roots = 0;
  String? initialReadId;
  bool closed = false;
  String heldKind = 'communityMedia';
  int heldOffset = 0;
  bool proveContinuity = true;
  String? nextState;
  bool holdReplacement = false;
  Future<void> Function(BridgeEnvelope request)? answerDirectory;
  final replacementStarted = Completer<void>(),
      releaseReplacement = Completer<void>();
  late final bytes = [
    ...base64Decode(offlineLogo.substring(22)),
    ...List.filled(192 * 1024, 0),
  ];
  late final image = 'data:image/png;base64,${base64Encode(bytes)}';
  late final logoHash = sha256.convert(bytes).toString();
  final Map<String, dynamic>? nativeRoots = _nativeRoots();
  static Map<String, dynamic>? _nativeRoots() {
    const path = String.fromEnvironment('STARBRIDGE_RETAINED_RENEWAL_WIRE');
    return path.isEmpty
        ? null
        : jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  }

  final stamp = '2026-10-14T12:00:00Z';

  Future<void> initialize() async {
    session.acceptHostCapabilities([
      'onboarding.mode.directory.v1',
      'communities.read',
    ]);
    incoming = pair.host.incoming.listen(_answer);
    await account.initialize();
    port = composeCommunityBridge(session, account.projection, null);
    model = CommunitiesModule(port);
  }

  Future<void> _answer(BridgeEnvelope request) async {
    seen.add(request);
    if (request.name == 'bridge.cancel') return;
    if (request.name == 'account.getCurrent') {
      final previous = current;
      current = (++roots).toString().padLeft(32, '0');
      var payload = <String, Object?>{
        'schemaVersion': 1,
        'state': 'credentialTemporarilyUnavailable',
        'displayName': null,
        'avatarUrl': null,
        'retainedDisplay': {
          'displayName': 'Saved pilot',
          'cachedAtUtc': stamp,
          'readId': current,
          if (previous != null && proveContinuity) 'previousReadId': previous,
        },
      };
      if (nativeRoots != null) {
        payload =
            ((nativeRoots![roots == 1
                            ? 'second'
                            : proveContinuity
                            ? 'renewed'
                            : 'replaced']
                        as Map)['payload']
                    as Map)
                .cast<String, Object?>();
        current = (payload['retainedDisplay'] as Map)['readId'] as String;
      }
      if (nextState != null && roots > 1) {
        payload = {
          'schemaVersion': 1,
          'state': nextState,
          'displayName': null,
          'avatarUrl': null,
        };
        current = null;
      }
      if (roots == 1) initialReadId = current;
      await respond(request, payload);
      return;
    }
    if (request.name != 'account.offlineData.read') {
      throw StateError('Unexpected request ${request.name}');
    }
    final body = request.payload;
    if (holdReplacement && roots > 1 && body['kind'] == 'communities') {
      if (!replacementStarted.isCompleted) replacementStarted.complete();
      await releaseReplacement.future;
    }
    final first = body['readId'] == initialReadId;
    if (first &&
        body['kind'] == heldKind &&
        (body['offset'] ?? 0) == heldOffset &&
        !oldStarted.isCompleted) {
      oldStarted.complete();
      await releaseOld.future;
    }
    if (closed) return;
    if (body['readId'] != current) {
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: 'error',
          error: const BridgeErrorBody(
            code: 'offlineAccount.context_changed',
            message: 'Display selection retired.',
            retryable: false,
          ),
          payload: const {},
        ),
      );
      return;
    }
    if (body['kind'] == 'communities') {
      if (answerDirectory != null) {
        await answerDirectory!(request);
        return;
      }
      await respond(request, {
        'schemaVersion': 1,
        'source': 'cached',
        'cachedAtUtc': stamp,
        'complete': true,
        'directoryVersion': 'a' * 32,
        'items': [
          {
            'id': 'b' * 64,
            'name': 'Retained Organization',
            'logoAvailable': true,
            'logoVersion': logoHash,
            'logoCachedAtUtc': stamp,
          },
        ],
      });
    } else {
      expect(body['kind'], 'communityMedia');
      final offset = body['offset']! as int;
      final end = (offset + 192 * 1024).clamp(0, bytes.length);
      await respond(request, {
        'schemaVersion': 1,
        'kind': 'logo',
        'version': logoHash,
        'mimeType': 'image/png',
        'totalBytes': bytes.length,
        'offset': offset,
        'data': base64Encode(bytes.sublist(offset, end)),
        if (end < bytes.length) 'next': end,
      });
    }
  }

  Future<void> respond(BridgeEnvelope request, Map<String, Object?> body) =>
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: 'ok',
          payload: body,
        ),
      );

  Future<void> close() async {
    closed = true;
    if (!releaseOld.isCompleted) releaseOld.complete();
    if (!releaseReplacement.isCompleted) releaseReplacement.complete();
    model.dispose();
    account.dispose();
    await incoming.cancel();
    await session.close();
    await pair.host.close();
  }
}

void main() {
  test(
    'unproven replacement retires the original private workspace owner',
    () async {
      final h = RetainedRenewalHost()
        ..holdReplacement = true
        ..proveContinuity = false;
      final privatePort = WorkspaceTestPort();
      await h.initialize();
      try {
        final old = h.model.workspaceSession.obtain(
          privatePort,
          'a' * 32,
          'original-organization',
        );
        await old.load();
        expect(old.workspace?.description, 'Members only details');
        await h.model.refreshJoined();
        await h.oldStarted.future.timeout(const Duration(seconds: 2));
        await h.account.refresh();
        await h.replacementStarted.future.timeout(const Duration(seconds: 2));
        final next = h.model.workspaceSession.obtain(
          privatePort,
          'a' * 32,
          'original-organization',
        );
        expect(identical(old, next), isFalse);
        expect(next.workspace, isNull);
      } finally {
        await h.close();
        await privatePort.changes.close();
      }
    },
  );
  test('proven renewal retains names while the new metadata is held', () async {
    final h = RetainedRenewalHost()..holdReplacement = true;
    await h.initialize();
    try {
      await h.model.refreshJoined();
      await h.oldStarted.future.timeout(const Duration(seconds: 2));
      final original = h.model.joined.single;
      await h.account.refresh();
      await h.replacementStarted.future.timeout(const Duration(seconds: 2));
      expect(h.model.joined.single.name, original.name);
      expect(h.model.joinedCachedAtUtc, DateTime.utc(2026, 10, 14, 12));
      expect(h.model.joined.single.displayOnly, isTrue);
      expect(h.model.joinedBusy, isTrue);
      expect(h.model.canExecute(h.model.joined.single), isFalse);
    } finally {
      await h.close();
    }
  });
  test('a root withdrawal cancels held bytes and cannot restart saved presentation', () async {
    final h = RetainedRenewalHost()..nextState = 'signedOut';
    await h.initialize();
    try {
      await h.model.refreshJoined();
      await h.oldStarted.future.timeout(const Duration(seconds: 2));
      final reads = h.seen
          .where((r) => r.name == 'account.offlineData.read')
          .length;
      await h.account.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(h.model.joined, isEmpty);
      h.releaseOld.complete();
      await Future<void>.delayed(Duration.zero);
      expect(h.model.joined, isEmpty);
      expect(
        h.seen.where((r) => r.name == 'account.offlineData.read').length,
        reads,
      );
    } finally {
      await h.close();
    }
  });
  test(
    'unproven replacement withdraws old names before preparing new display',
    () async {
      final h = RetainedRenewalHost()
        ..holdReplacement = true
        ..proveContinuity = false;
      await h.initialize();
      try {
        await h.model.refreshJoined();
        await h.oldStarted.future.timeout(const Duration(seconds: 2));
        expect(h.model.joined.single.name, 'Retained Organization');
        await h.account.refresh();
        await h.replacementStarted.future.timeout(const Duration(seconds: 2));
        expect(h.model.joined, isEmpty);
      } finally {
        await h.close();
      }
    },
  );
  test(
    'unchanged display selection completes the original bounded chunks',
    () async {
      final h = RetainedRenewalHost();
      await h.initialize();
      final completed = Completer<void>();
      h.model.addListener(() {
        if (!completed.isCompleted &&
            h.model.joined.firstOrNull?.logo == h.image) {
          completed.complete();
        }
      });
      try {
        await h.model.refreshJoined();
        await h.oldStarted.future.timeout(const Duration(seconds: 2));
        h.releaseOld.complete();
        await completed.future.timeout(const Duration(seconds: 2));
        expect(h.roots, 1);
        expect(
          h.seen.where((r) => r.payload['kind'] == 'communityMedia').length,
          2,
        );
      } finally {
        await h.close();
      }
    },
  );
  for (final held in [
    ('communityMedia', 0),
    ('communityMedia', 192 * 1024),
    ('communities', 0),
  ]) {
    final (kind, offset) = held;
    test(
      'fresh root display selection resumes held $kind offset=$offset without authorizing it',
      () async {
        final h = RetainedRenewalHost()
          ..heldKind = kind
          ..heldOffset = offset;
        await h.initialize();
        expect(h.account.projection.value.retainedReadId, h.initialReadId);
        final completed = Completer<void>();
        h.model.addListener(() {
          if (!completed.isCompleted &&
              h.model.joined.firstOrNull?.logo == h.image) {
            completed.complete();
          }
        });
        try {
          final firstRead = h.model.refreshJoined();
          await h.oldStarted.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () =>
                throw StateError('Original $kind read never started'),
          );
          if (kind == 'communityMedia') {
            await firstRead;
            expect(h.model.joined.single.name, 'Retained Organization');
          }
          final before = h.account.projection.value.retainedReadId;
          await h.account.refresh();
          expect(h.account.projection.value.retainedReadId, isNot(before));
          expect(h.session.activeGeneration, 7);
          await completed.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () =>
                throw StateError('New selection did not finish $kind'),
          );
          expect(h.model.joinedCachedAtUtc, DateTime.utc(2026, 10, 14, 12));
          final row = h.model.joined.single;
          expect(row.displayOnly, isTrue);
          expect(row.targetRef, isEmpty);
          expect(row.actions, isEmpty);
          expect(h.model.canExecute(row), isFalse);
          expect(h.roots, 2);
          expect(h.seen.every((r) => r.accountContext == null), isTrue);
          expect(h.seen.any((r) => r.name == 'bridge.cancel'), isTrue);
          h.releaseOld.complete();
          await firstRead;
          await Future<void>.delayed(Duration.zero);
          expect(h.model.joined.single.logo, h.image);
        } finally {
          await h.close();
        }
      },
    );
  }
}
