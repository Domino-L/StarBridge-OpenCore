import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/bridge_communities.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../onboarding/connection_mode_test.dart' show ModePort, modeFact;

const offlineLogo =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
const logoHash =
    '431ced6916a2a21a156e38701afe55bbd7f88969fbbfc56d7fe099d47f265460';

final class OfflineDirectoryHost {
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 7,
  );
  final modePort = ModePort()..current = modeFact('offline');
  late final mode = ConnectionModeController(modePort);
  late final BridgeCommunities port;
  late final StreamSubscription<BridgeEnvelope> incoming;
  final seen = <BridgeEnvelope>[];
  final mediaGate = Completer<void>();
  bool closed = false, missing = false, holdMedia = true;
  Map<String, Object?> metadata = {
    'schemaVersion': 1,
    'source': 'cached',
    'cachedAtUtc': '2026-10-14T12:00:00Z',
    'complete': true,
    'directoryVersion': 'a' * 32,
    'items': [
      {
        'id': 'b' * 64,
        'name': 'Retained Organization',
        'logoAvailable': true,
        'logoVersion': logoHash,
        'logoCachedAtUtc': '2026-10-14T11:00:00Z',
      },
    ],
  };
  Map<String, Object?>? errorResponse;
  Map<String, Object?> media = {
    'schemaVersion': 1,
    'kind': 'logo',
    'version': logoHash,
    'mimeType': 'image/png',
    'totalBytes': base64Decode(offlineLogo.substring(22)).length,
    'offset': 0,
    'data': offlineLogo.substring(22),
  };
  static Future<OfflineDirectoryHost> create() async {
    final h = OfflineDirectoryHost();
    await h.mode.refresh();
    h.session.acceptHostCapabilities([
      'onboarding.mode.directory.v1',
      'communities.read',
    ]);
    h.port = BridgeCommunities(h.session, connectionMode: h.mode);
    h.incoming = h.pair.host.incoming.listen((request) async {
      h.seen.add(request);
      if (request.name == 'bridge.cancel') return;
      final isMedia = request.name == 'onboarding.mode.communityMedia';
      if (isMedia && h.holdMedia) await h.mediaGate.future;
      if (h.closed) return;
      if (h.missing && h.errorResponse != null) {
        await h.pair.host.send(
          BridgeEnvelope.fromJson({
            ...h.errorResponse!,
            'name': request.name,
            'correlationId': request.correlationId,
            'sessionGeneration': request.sessionGeneration,
          }),
        );
        return;
      }
      await h.pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: h.missing ? 'error' : 'ok',
          error: h.missing
              ? const BridgeErrorBody(
                  code: 'offlineAccount.unavailable',
                  message: 'No saved display.',
                  retryable: false,
                )
              : null,
          payload: h.missing
              ? const {}
              : isMedia
              ? h.media
              : h.metadata,
        ),
      );
    });
    return h;
  }

  Future<void> releaseMedia() async {
    holdMedia = false;
    if (!mediaGate.isCompleted) mediaGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  Future<void> close() async {
    closed = true;
    if (!mediaGate.isCompleted) mediaGate.complete();
    await port.close();
    await incoming.cancel();
    await session.close();
    await pair.host.close();
    mode.dispose();
    await modePort.events.close();
  }
}

void main() {
  const denialPath = String.fromEnvironment(
    'STARBRIDGE_OFFLINE_COMMUNITY_DENIAL_WIRE',
  );
  for (final phase in ['warmUnavailable', 'coldUnavailable']) {
    test(
      'actual Native $phase withdraws old cached names and ignores late media',
      () async {
        final fixtures = jsonDecode(File(denialPath).readAsStringSync()) as Map;
        final h = await OfflineDirectoryHost.create();
        h.metadata = (fixtures['before'] as Map)['payload']
            .cast<String, Object?>();
        h.errorResponse = (fixtures[phase] as Map).cast<String, Object?>();
        final model = CommunitiesModule(h.port);
        try {
          await model.refreshJoined();
          expect(model.joined.single.name, 'Retained Organization');
          expect(model.joined.single.displayOnly, isTrue);
          await Future<void>.delayed(Duration.zero);
          h.missing = true;
          await model.refreshJoined();
          expect(model.joined, isEmpty);
          expect(model.joinedError, 'offlineCacheUnavailable');
          await h.releaseMedia();
          expect(model.joined, isEmpty);
          final requests = h.seen.length;
          await model.refreshJoined();
          expect(h.seen.length, requests);
          expect(h.seen.every((r) => r.accountContext == null), isTrue);
          expect(
            h.seen.any(
              (r) =>
                  r.name == 'account.getCurrent' ||
                  r.name == 'communities.read',
            ),
            isFalse,
          );
        } finally {
          model.dispose();
          await h.close();
        }
      },
      skip: denialPath.isEmpty
          ? 'Requires actual Native organization refusal fixture.'
          : false,
    );
  }
  test('offline names render before media, stay passive and retain hydrated logo on same-version refresh', () async {
    final h = await OfflineDirectoryHost.create();
    final model = CommunitiesModule(h.port);
    try {
      await model.refreshJoined();
      expect(model.joined.single.name, 'Retained Organization');
      expect(model.joinedCachedAtUtc, DateTime.utc(2026, 10, 14, 12));
      expect(model.joined.single.logo, isNull);
      final row = model.joined.single;
      expect(row.displayOnly, isTrue);
      expect(row.targetRef, isEmpty);
      expect(row.relationship, 'none');
      expect(row.memberCount, isNull);
      expect(row.actions, isEmpty);
      expect(model.canExecute(row), isFalse);
      await model.openJoined(row);
      await model.execute(row, 'leave');
      expect(model.selected, isNull);
      await h.releaseMedia();
      expect(model.joined.single.logo, offlineLogo);
      await model.refreshJoined();
      expect(model.joined.single.logo, offlineLogo);
      expect(
        h.seen.every(
          (r) => {
            'onboarding.mode.communities',
            'onboarding.mode.communityMedia',
          }.contains(r.name),
        ),
        isTrue,
      );
      expect(h.seen.every((r) => r.accountContext == null), isTrue);
    } finally {
      model.dispose();
      await h.close();
    }
  });
  test('mode retirement cancels deferred media without republishing old organization bytes', () async {
    final h = await OfflineDirectoryHost.create();
    final model = CommunitiesModule(h.port);
    try {
      await model.refreshJoined();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        h.seen.any((r) => r.name == 'onboarding.mode.communityMedia'),
        isTrue,
      );
      h.modePort.current = modeFact('local');
      await h.mode.refresh();
      await Future<void>.delayed(Duration.zero);
      await h.releaseMedia();
      expect(model.joined, isEmpty);
      expect(h.seen.any((r) => r.name == 'bridge.cancel'), isTrue);
      expect(h.seen.any((r) => r.name == 'account.getCurrent'), isFalse);
    } finally {
      model.dispose();
      await h.close();
    }
  });
  test(
    'missing or corrupt cached directory is honest and stops automatic retry',
    () async {
      for (final missing in [true, false]) {
        final h = await OfflineDirectoryHost.create();
        h.missing = missing;
        if (!missing) h.metadata = {...h.metadata, 'role': 'owner'};
        final model = CommunitiesModule(h.port);
        try {
          await model.refreshJoined();
          expect(model.joined, isEmpty);
          expect(model.joinedError, 'offlineCacheUnavailable');
          await model.refreshJoined();
          expect(h.seen.length, 1);
        } finally {
          model.dispose();
          await h.close();
        }
      }
    },
  );
  test(
    'independent media failure keeps cached names and original timestamp',
    () async {
      final h = await OfflineDirectoryHost.create();
      final model = CommunitiesModule(h.port);
      try {
        await model.refreshJoined();
        h.media = {...h.media, 'version': '0' * 64};
        await h.releaseMedia();
        expect(model.joined.single.name, 'Retained Organization');
        expect(model.joined.single.logo, isNull);
        expect(model.joinedCachedAtUtc, DateTime.utc(2026, 10, 14, 12));
        expect(model.joinedError, isNull);
      } finally {
        model.dispose();
        await h.close();
      }
    },
  );
  const path = String.fromEnvironment('STARBRIDGE_OFFLINE_COMMUNITY_WIRE');
  test(
    'actual Native warm and cold metadata and logo chunks reach the Flutter module without a root read',
    () async {
      final fixtures = jsonDecode(File(path).readAsStringSync()) as Map;
      for (final label in ['warm', 'cold']) {
        final h = await OfflineDirectoryHost.create();
        h.metadata = (fixtures[label] as Map)['payload']
            .cast<String, Object?>();
        h.media = (fixtures['${label}Media'] as Map)['payload']
            .cast<String, Object?>();
        final model = CommunitiesModule(h.port);
        try {
          await model.refreshJoined();
          expect(model.joined.single.name, 'Retained Organization');
          await h.releaseMedia();
          expect(model.joined.single.logo, offlineLogo);
          expect(h.seen.any((r) => r.name == 'account.getCurrent'), isFalse);
        } finally {
          model.dispose();
          await h.close();
        }
      }
    },
    skip: path.isEmpty
        ? 'Requires actual Native offline community wire'
        : false,
  );
}
