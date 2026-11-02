import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/friend_sharing_controller.dart';
import 'package:starbridge_flutter/features/settings/friend_sharing_setting.dart';
import 'package:starbridge_flutter/features/settings/game_id_visibility_controller.dart';
import 'package:starbridge_flutter/features/settings/game_id_visibility_setting.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart' as fixture;

const _timeout = Timeout(Duration(seconds: 45));

enum _Kind { friends, gameId }

Future<void> _frames(WidgetTester t, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Map<String, Object?> _friendSnapshot(int? fields, {int revision = 1}) => {
  'schemaVersion': 1,
  'revision': fields == null ? 0 : revision,
  'operationId': fields == null ? null : '0' * 32,
  'appliedAt': fields == null ? null : '2026-10-16T00:00:00Z',
  'fields': fields,
};

Map<String, Object?> _gameSnapshot(
  int locations, {
  int revision = 1,
  bool canConfigure = true,
  String? stamp,
}) => {
  'schemaVersion': 1,
  'revision': revision,
  'locations': locations,
  'canConfigure': canConfigure,
  'identityStamp': stamp ?? 'a' * 64,
};

/// Transport only. It intentionally creates no controller: the single real
/// controller is owned by the mounted production Setting, as in the client.
class _Host {
  _Host(this.kind) {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 4)
      ..acceptHostCapabilities([
        kind == _Kind.friends
            ? 'friendSharing.settings'
            : 'gameIdVisibility.settings',
      ]);
    snapshot = kind == _Kind.friends ? _friendSnapshot(0) : _gameSnapshot(15);
    subscription = connection.incoming.listen((request) {
      if (request.messageType == 'request') unawaited(_reply(request));
    });
  }
  final _Kind kind;
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  late Map<String, Object?> snapshot;
  final reads = <BridgeEnvelope>[];
  final writes = <BridgeEnvelope>[];
  String subject = 'synthetic-first-owner';
  bool reject = false;
  bool loseReceipt = false;
  bool closed = false;
  int sequence = 0;
  Completer<void>? readGate;
  Completer<void>? writeGate;

  String get prefix =>
      kind == _Kind.friends ? 'friendSharing' : 'gameIdVisibility';
  BridgeAccountContext get account => BridgeAccountContext(
    environment: 'test',
    authority: 'scm',
    subject: subject,
  );

  Future<void> _reply(BridgeEnvelope request) async {
    final context = request.accountContext ?? account;
    final reading = request.name == '$prefix.read';
    final writing = request.name == '$prefix.save';
    final before = Map<String, Object?>.of(snapshot);
    if (reading) reads.add(request);
    if (writing) {
      writes.add(request);
      if (!reject) {
        snapshot = kind == _Kind.friends
            ? {
                'schemaVersion': 1,
                'revision': (request.payload['expectedRevision'] as int) + 1,
                'operationId': request.payload['operationId'],
                'appliedAt': '2026-10-16T00:00:00Z',
                'fields': request.payload['fields'],
              }
            : {
                ...snapshot,
                'revision': (request.payload['expectedRevision'] as int) + 1,
                'locations': request.payload['locations'],
              };
      }
    }
    final savedReply = Map<String, Object?>.of(snapshot);
    final readPause = reading ? readGate : null;
    final writePause = writing ? writeGate : null;
    final failed = writing && (reject || loseReceipt);
    if (readPause != null) await readPause.future;
    if (writePause != null) await writePause.future;
    if (closed) return;
    final body = request.name == 'account.getCurrent'
        ? <String, Object?>{'schemaVersion': 1, 'state': 'signedIn'}
        : kind == _Kind.friends
        ? <String, Object?>{
            'state': 'inactive',
            'snapshot': reading ? before : savedReply,
          }
        : reading
        ? before
        : savedReply;
    await connection.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: context,
        status: failed ? 'error' : 'ok',
        error: failed
            ? BridgeErrorBody(
                code: kind == _Kind.friends
                    ? 'friendsSharing.write_unconfirmed'
                    : 'gameId.conflict',
                message: 'synthetic refusal',
                retryable: false,
              )
            : null,
        payload: body,
      ),
    );
  }

  void finishRead() {
    final gate = readGate;
    readGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void finishWrite() {
    final gate = writeGate;
    writeGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<void> changeAccount() => connection.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: 'account.changed',
      sessionGeneration: 4,
      sequence: sequence++,
      accountContext: account,
      payload: const {'schemaVersion': 1},
    ),
  );
  Future<void> close(WidgetTester t) async {
    closed = true;
    finishRead();
    finishWrite();
    await _frames(t, count: 2);
    await t.runAsync(() async {
      await subscription.cancel();
      await session.close();
      await connection.close();
    });
  }
}

class _Mounted {
  _Mounted(this.host, this.suite, this.drafts);
  final _Host host;
  final InteractionSuite suite;
  final PrivacyPageDrafts? drafts;
  late Object controller;
  bool unmounted = false;

  Widget app() {
    Widget setting = host.kind == _Kind.friends
        ? FriendSharingSetting(session: host.session)
        : GameIdVisibilitySetting(session: host.session);
    if (drafts != null) {
      setting = PrivacyDraftScope(drafts: drafts!, child: setting);
    }
    return fixture.scopedApp(
      SingleChildScrollView(child: SizedBox(width: 640, child: setting)),
      suite,
    );
  }

  Future<void> mount(WidgetTester t, {bool settle = true}) async {
    fixture.size(t, const Size(1000, 1000));
    await t.pumpWidget(app());
    // MaterialApp's localizations can complete after its initial frame. Mount
    // the actual setting before reading its single production controller.
    await _frames(t, count: 2);
    controller = host.kind == _Kind.friends
        ? (t.state(find.byType(FriendSharingSetting)) as dynamic).controller
              as FriendSharingController
        : (t.state(find.byType(GameIdVisibilitySetting)) as dynamic).controller
              as GameIdVisibilityController;
    if (settle) await _frames(t);
  }

  int get mask => switch (controller) {
    FriendSharingController c => c.fields,
    GameIdVisibilityController c => c.locations,
    _ => throw StateError('unreachable controller'),
  };
  bool get busy => switch (controller) {
    FriendSharingController c => c.busy,
    GameIdVisibilityController c => c.busy,
    _ => false,
  };
  bool get canEdit => switch (controller) {
    FriendSharingController c => c.canEdit,
    GameIdVisibilityController c => c.canEdit,
    _ => false,
  };
  Map<String, Object?>? get snapshot => switch (controller) {
    FriendSharingController c => c.snapshot,
    GameIdVisibilityController c => c.snapshot,
    _ => null,
  };
  Future<void> refresh() => switch (controller) {
    FriendSharingController c => c.refresh(),
    GameIdVisibilityController c => c.refresh(),
    _ => throw StateError('unreachable controller'),
  };
  Future<void> unmount(WidgetTester t) async {
    if (unmounted) return;
    unmounted = true;
    await t.pumpWidget(const SizedBox.shrink());
    await _frames(t, count: 2);
  }

  Future<void> close(WidgetTester t) async {
    await unmount(t);
    await host.close(t);
    drafts?.dispose();
  }
}

StarBridgeSwitch _switch(WidgetTester t, String key) {
  final target = find.byKey(Key(key));
  if (t.widget(target) is StarBridgeSwitch) {
    return t.widget<StarBridgeSwitch>(target);
  }
  return t.widget<StarBridgeSwitch>(
    find.ancestor(of: target, matching: find.byType(StarBridgeSwitch)).first,
  );
}

Future<void> _tap(WidgetTester t, String key) async {
  final target = find
      .ancestor(
        of: find.byKey(Key(key)),
        matching: find.byType(StarBridgeSwitch),
      )
      .first;
  await t.ensureVisible(target);
  await t.pump();
  await t.tap(target);
  await t.pump();
}

void main() {
  setUpAll(fixture.loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final saved in <int?>[null, 0, 55]) {
      testWidgets(
        '$suite friend initial mask $saved preserves absent versus saved OFF without optimistic writes',
        (t) async {
          final host = _Host(_Kind.friends)..snapshot = _friendSnapshot(saved);
          final drafts = PrivacyPageDrafts();
          final page = _Mounted(host, suite, drafts);
          try {
            await page.mount(t);
            expect(host.reads, hasLength(1));
            expect(host.writes, isEmpty);
            expect(drafts.dirty, saved == null);
            final expected = saved ?? 63;
            for (final entry in const {
              1: 'presence',
              2: 'serverRelation',
              4: 'serverDetails',
              8: 'ship',
              16: 'location',
              32: 'lastOnline',
            }.entries) {
              expect(
                _switch(t, 'friend-sharing-${entry.value}').value,
                expected & entry.key != 0,
              );
            }
            final save = drafts.save();
            await _frames(t);
            expect(await save, isTrue);
            expect(host.writes.length, saved == null ? 1 : 0);
            if (saved == null) {
              expect(host.writes.single.payload['expectedRevision'], 0);
              expect(host.writes.single.payload['fields'], 63);
              expect(page.mask, 63);
            }
            expect(t.takeException(), isNull);
          } finally {
            await page.close(t);
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite friend discard never re-stages absent defaults after background notifications',
      (t) async {
        final host = _Host(_Kind.friends)..snapshot = _friendSnapshot(null);
        final drafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t);
          expect(drafts.dirty, isTrue);
          drafts.discard();
          await _frames(t);
          await page.refresh();
          await _frames(t);
          expect(drafts.dirty, isFalse);
          expect(host.writes, isEmpty);
          expect(page.mask, 0);
          expect(_switch(t, 'friend-sharing-presence').value, isFalse);
          expect(_switch(t, 'friend-sharing-ship').value, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          await page.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite friend late initial post-frame draft respects editor epoch discard',
      (t) async {
        final host = _Host(_Kind.friends)
          ..snapshot = _friendSnapshot(null)
          ..readGate = Completer<void>();
        final drafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t, settle: false);
          await _frames(t, count: 2);
          expect(host.reads, hasLength(1));
          host.finishRead();
          for (var i = 0; i < 20; i++) {
            await Future<void>.value();
          }
          expect(page.canEdit, isTrue);
          expect(drafts.dirty, isFalse);
          drafts.discard();
          await t.pump();
          await _frames(t, count: 2);
          expect(drafts.dirty, isFalse);
          expect(host.writes, isEmpty);
          expect(_switch(t, 'friend-sharing-presence').value, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          await page.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite friend lost receipt server apply confirms through readback without second mutation',
      (t) async {
        final host = _Host(_Kind.friends)
          ..snapshot = _friendSnapshot(null)
          ..loseReceipt = true;
        final drafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t);
          expect(drafts.dirty, isTrue);
          final first = drafts.save();
          await _frames(t);
          expect(await first, isFalse);
          expect(drafts.failed, isTrue);
          expect(host.snapshot['fields'], 63);
          expect(page.mask, 63);
          expect(host.reads, hasLength(2));
          expect(host.writes, hasLength(1));
          host.loseReceipt = false;
          final retry = drafts.save();
          await _frames(t);
          expect(await retry, isTrue);
          expect(drafts.dirty, isFalse);
          expect(drafts.failed, isFalse);
          expect(host.writes, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          await page.close(t);
        }
      },
      timeout: _timeout,
    );

    for (final locations in [0, 15]) {
      testWidgets(
        '$suite unconfigurable game identity mask $locations stays read-only without writes',
        (t) async {
          final host = _Host(_Kind.gameId)
            ..snapshot = _gameSnapshot(locations, canConfigure: false);
          final page = _Mounted(host, suite, PrivacyPageDrafts());
          try {
            await page.mount(t);
            expect(page.canEdit, isFalse);
            expect(page.mask, locations);
            for (final key in ['organization', 'room', 'friends', 'profile']) {
              expect(_switch(t, 'game-id-$key').onChanged, isNull);
              expect(_switch(t, 'game-id-$key').value, locations == 15);
            }
            final controller = page.controller as GameIdVisibilityController;
            await controller.change(4, locations == 0);
            expect(host.writes, isEmpty);
            expect(page.drafts!.dirty, isFalse);
            expect(t.takeException(), isNull);
          } finally {
            await page.close(t);
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite game draft commit binds original revision identity stamp and conflict receipt',
      (t) async {
        for (final change in [
          'revision',
          'identity stamp',
          'server conflict',
        ]) {
          final host = _Host(_Kind.gameId);
          final drafts = PrivacyPageDrafts();
          final page = _Mounted(host, suite, drafts);
          try {
            await page.mount(t);
            await _tap(t, 'game-id-profile');
            await _frames(t, count: 2);
            expect(drafts.value('game-id', -1), 7);
            expect(host.writes, isEmpty);
            if (change == 'server conflict') {
              host.reject = true;
            } else {
              host.snapshot = _gameSnapshot(
                15,
                revision: change == 'revision' ? 2 : 1,
                stamp: change == 'identity stamp' ? 'b' * 64 : 'a' * 64,
              );
              await page.refresh();
              await _frames(t);
            }
            final save = drafts.save();
            await _frames(t);
            expect(await save, isFalse);
            expect(drafts.dirty, isTrue);
            expect(drafts.failed, isTrue);
            expect(page.mask, 15);
            expect(host.writes.length, change == 'server conflict' ? 1 : 0);
            if (change == 'server conflict') {
              expect(host.writes.single.payload['expectedRevision'], 1);
              expect(host.writes.single.payload['identityStamp'], 'a' * 64);
              expect(host.writes.single.payload['locations'], 7);
              expect(host.reads, hasLength(2));
            }
            expect(t.takeException(), isNull);
          } finally {
            await page.close(t);
          }
        }
      },
      timeout: _timeout,
    );

    for (final kind in _Kind.values) {
      testWidgets(
        '$suite $kind periodic read preserves editable draft and save supersedes its late snapshot',
        (t) async {
          final host = _Host(kind);
          final drafts = PrivacyPageDrafts();
          final page = _Mounted(host, suite, drafts);
          final key = kind == _Kind.friends
              ? 'friend-sharing-ship'
              : 'game-id-friends';
          try {
            await page.mount(t);
            await _tap(t, key);
            await _frames(t, count: 2);
            expect(drafts.dirty, isTrue);
            host.readGate = Completer<void>();
            await t.pump(const Duration(seconds: 15));
            await _frames(t, count: 2);
            expect(host.reads, hasLength(2));
            expect(page.busy, isFalse);
            expect(page.canEdit, isTrue);
            expect(_switch(t, key).onChanged, isNotNull);
            expect(host.writes, isEmpty);
            final save = drafts.save();
            await _frames(t);
            expect(await save, isTrue);
            expect(host.writes, hasLength(1));
            final expected = kind == _Kind.friends ? 8 : 11;
            expect(page.mask, expected);
            host.finishRead();
            await _frames(t);
            expect(page.mask, expected);
            expect(drafts.dirty, isFalse);
            expect(host.writes, hasLength(1));
            expect(host.reads, hasLength(2));
            expect(t.takeException(), isNull);
          } finally {
            await page.close(t);
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind pending receipt respects account invalidation and page disposal owner barriers',
        (t) async {
          for (final retirement in ['account', 'page']) {
            final host = _Host(kind);
            final page = _Mounted(host, suite, null);
            final key = kind == _Kind.friends
                ? 'friend-sharing-ship'
                : 'game-id-friends';
            try {
              await page.mount(t);
              final before = page.snapshot;
              host.writeGate = Completer<void>();
              await _tap(t, key);
              await _frames(t, count: 2);
              expect(host.writes, hasLength(1));
              expect(page.busy, isTrue);
              if (retirement == 'account') {
                host.subject = 'synthetic-next-owner';
                host.snapshot = kind == _Kind.friends
                    ? _friendSnapshot(55, revision: 33)
                    : _gameSnapshot(0, revision: 33);
                await host.changeAccount();
                await _frames(t);
                expect(page.snapshot?['revision'], 33);
                expect(page.mask, kind == _Kind.friends ? 55 : 0);
              } else {
                await page.unmount(t);
              }
              host.finishWrite();
              await _frames(t);
              if (retirement == 'account') {
                expect(page.snapshot?['revision'], 33);
                expect(page.mask, kind == _Kind.friends ? 55 : 0);
              } else {
                expect(page.snapshot, same(before));
              }
              expect(host.writes, hasLength(1));
              expect(t.takeException(), isNull);
            } finally {
              await page.close(t);
            }
          }
        },
        timeout: _timeout,
      );
    }
  }
}
