import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/event_scope_editor.dart';
import 'package:starbridge_flutter/features/settings/event_sharing_controller.dart';
import 'package:starbridge_flutter/features/settings/event_sharing_page.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart' as fixture;

const _timeout = Timeout(Duration(seconds: 45));
const _baselineTag = 'batch3dv-preexisting';
const _joined = '2026-09-01T00:00:00.1234567+00:00';
const _rejoined = '2026-10-16T00:00:00.1234567+00:00';

Map<String, Object?> _absent() => {
  'schemaVersion': 1,
  'revision': 0,
  'operationId': null,
  'appliedAt': null,
  'publicationEnabled': false,
  'settings': null,
};

Map<String, Object?> _saved({int revision = 1, bool off = false}) => {
  'schemaVersion': 1,
  'revision': revision,
  'operationId': '0' * 32,
  'appliedAt': '2026-10-16T00:00:00Z',
  'publicationEnabled': !off,
  'settings': {
    'room': {'enabled': !off, 'selectedTypes': 47},
    'communities': [
      {
        'code': 'A',
        'joinedAt': _joined,
        'choice': {'enabled': !off, 'selectedTypes': 32},
      },
      {
        'code': 'B',
        'joinedAt': _joined,
        'choice': {'enabled': false, 'selectedTypes': 8},
      },
    ],
  },
};

Future<void> _frames(WidgetTester t, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _microtasks() async {
  for (var i = 0; i < 60; i++) {
    await Future<void>.value();
  }
}

/// Owns only the synthetic transport, never an extra EventSharingController.
/// Every test reaches the single controller created by the production page.
class _Host {
  _Host() {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 4)
      ..acceptHostCapabilities(const ['eventSharing.settings']);
    subscription = connection.incoming.listen((request) {
      if (request.messageType == 'request') unawaited(_reply(request));
    });
  }
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  Map<String, Object?> snapshot = _absent();
  final reads = <BridgeEnvelope>[];
  final directories = <BridgeEnvelope>[];
  final writes = <BridgeEnvelope>[];
  final codes = ['A', 'B'];
  String joinedAt = _joined;
  String subject = 'synthetic-event-owner';
  String state = 'inactive';
  bool reject = false;
  bool loseReceipt = false;
  bool rejectRead = false;
  bool closed = false;
  int sequence = 0;
  Completer<void>? readGate;
  Completer<void>? writeGate;

  BridgeAccountContext get account => BridgeAccountContext(
    environment: 'test',
    authority: 'scm',
    subject: subject,
  );

  Future<void> _reply(BridgeEnvelope request) async {
    final context = request.accountContext ?? account;
    final reading = request.name == 'eventSharing.read';
    final writing = request.name == 'eventSharing.save';
    final directory = request.name == 'privacy.communityTargets';
    final before = Map<String, Object?>.of(snapshot);
    if (reading) reads.add(request);
    if (directory) directories.add(request);
    if (writing) {
      writes.add(request);
      if (!reject) {
        snapshot = {
          'schemaVersion': 1,
          'revision': (request.payload['expectedRevision'] as int) + 1,
          'operationId': request.payload['operationId'],
          'appliedAt': '2026-10-16T00:00:00Z',
          'publicationEnabled': request.payload['publicationEnabled'],
          'settings': request.payload['settings'],
        };
      }
    }
    final savedReply = Map<String, Object?>.of(snapshot);
    final replyState = state;
    final pause = reading
        ? readGate
        : writing
        ? writeGate
        : null;
    final failed = writing && (reject || loseReceipt) || reading && rejectRead;
    if (pause != null) await pause.future;
    if (closed) return;
    final body = request.name == 'account.getCurrent'
        ? <String, Object?>{'schemaVersion': 1, 'state': 'signedIn'}
        : directory
        ? <String, Object?>{
            'schemaVersion': 2,
            'primaryFleetCode': null,
            'communities': [
              for (final code in codes)
                {
                  'code': code,
                  'name': 'Organization $code',
                  'joinedAt': joinedAt,
                },
            ],
          }
        : <String, Object?>{
            'snapshot': reading ? before : savedReply,
            'state': replyState,
          };
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
                code: reading
                    ? 'events.read_unconfirmed'
                    : 'events.write_unconfirmed',
                message: 'synthetic response loss',
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

  Future<void> accountChanged() => connection.send(
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
  Future<void> close() async {
    closed = true;
    finishRead();
    finishWrite();
    await subscription.cancel();
    await session.close();
    await connection.close();
  }
}

class _Mounted {
  _Mounted(this.host, this.suite, this.drafts);
  final _Host host;
  final InteractionSuite suite;
  final PrivacyPageDrafts? drafts;
  late EventSharingController controller;
  bool unmounted = false;

  Widget app() {
    Widget page = EventSharingPage(session: host.session);
    if (drafts != null) page = PrivacyDraftScope(drafts: drafts!, child: page);
    return fixture.scopedApp(page, suite);
  }

  Future<void> mount(WidgetTester t, {bool settle = true}) async {
    fixture.size(t, const Size(1200, 1000));
    await t.pumpWidget(app());
    // Retrieve the page's actual controller after only two first mount frames.
    // In race tests the Bridge read gate is still closed through these frames.
    await t.pump();
    await t.pump();
    controller =
        (t.state(find.byType(EventSharingPage)) as dynamic).controller
            as EventSharingController;
    if (settle) await _frames(t);
  }

  Future<void> unmount(WidgetTester t) async {
    if (unmounted) return;
    unmounted = true;
    await t.pumpWidget(const SizedBox.shrink());
    await _frames(t, count: 2);
  }

  Future<void> close(WidgetTester t) async {
    await unmount(t);
    host.finishRead();
    host.finishWrite();
    await _frames(t, count: 2);
    await t.runAsync(host.close);
    drafts?.dispose();
  }
}

EventScopeEditor _scope(WidgetTester t, String scope) =>
    t.widget<EventScopeEditor>(
      find.byWidgetPredicate(
        (w) => w is EventScopeEditor && w.scopeKey == scope,
      ),
    );

Future<void> _tap(WidgetTester t, String key) async {
  final target = find.byKey(Key(key));
  await t.ensureVisible(target);
  await t.pump();
  await t.tap(target);
  await t.pump();
}

void main() {
  setUpAll(fixture.loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final directoryChange in ['new target', 'removed target']) {
      testWidgets(
        '$suite adjacent event review $directoryChange followed by a fresh edit saves the canonical current scopes once',
        (t) async {
          final host = _Host()..snapshot = _saved();
          final drafts = PrivacyPageDrafts();
          final page = _Mounted(host, suite, drafts);
          try {
            await page.mount(t);
            await _tap(t, 'privacy-scope-event-room-field-ship');
            expect(_scope(t, 'event-room').choice.selectedTypes, 43);
            expect(drafts.dirty, isTrue);
            if (directoryChange == 'new target') {
              host.codes.add('C');
            } else {
              host.codes.remove('B');
            }
            await page.controller.refresh();
            await _frames(t);
            expect(host.writes, isEmpty);
            expect(_scope(t, 'event-room').choice.selectedTypes, 43);
            expect(
              _scope(t, 'event-A').choice,
              const EventSharingChoice(enabled: true, selectedTypes: 32),
            );
            if (directoryChange == 'new target') {
              expect(
                _scope(t, 'event-C').choice,
                EventSharingChoice.unconfirmed,
              );
            } else {
              expect(
                find.byWidgetPredicate(
                  (w) => w is EventScopeEditor && w.scopeKey == 'event-B',
                ),
                findsNothing,
              );
            }

            // This deliberate new edit captures the fresh directory lease.
            // It must preserve earlier room edits, use the conservative saved
            // fallback for a new scope, and ignore a removed obsolete scope.
            await _tap(t, 'privacy-scope-event-room-field-location');
            expect(_scope(t, 'event-room').choice.selectedTypes, 35);
            expect(host.writes, isEmpty);
            final save = drafts.save();
            await _frames(t);
            expect(await save, isTrue);
            expect(host.writes, hasLength(1));
            expect(host.writes.single.payload['expectedRevision'], 1);
            final settings = host.writes.single.payload['settings'] as Map;
            expect(settings['room'], {'enabled': true, 'selectedTypes': 35});
            final rows = settings['communities'] as List;
            expect(
              rows.map((row) => (row as Map)['code']),
              directoryChange == 'new target' ? ['A', 'B', 'C'] : ['A'],
            );
            expect((rows.first as Map)['choice'], {
              'enabled': true,
              'selectedTypes': 32,
            });
            if (directoryChange == 'new target') {
              expect((rows.last as Map)['choice'], {
                'enabled': false,
                'selectedTypes': 47,
              });
              expect(
                page.controller.choice('C'),
                EventSharingChoice.unconfirmed,
              );
            }
            expect(
              page.controller.choice(null),
              const EventSharingChoice(enabled: true, selectedTypes: 35),
            );
            expect(drafts.dirty, isFalse);
            expect(drafts.failed, isFalse);
            expect(t.takeException(), isNull);
          } finally {
            await page.close(t);
          }
        },
        timeout: _timeout,
        tags: ['batch3dv-adjacent-review'],
      );
    }

    for (final discardWhileBusy in [false, true]) {
      testWidgets(
        '$suite adjacent event review first-use temporary busy discard=$discardWhileBusy retains the correct staging lease',
        (t) async {
          final host = _Host()..readGate = Completer<void>();
          final drafts = PrivacyPageDrafts();
          final page = _Mounted(host, suite, drafts);
          try {
            await page.mount(t, settle: false);
            expect(host.reads, hasLength(1));
            host.finishRead();
            await _microtasks();
            expect(page.controller.canEdit, isTrue);
            expect(page.controller.snapshot?['revision'], 0);
            expect(drafts.dirty, isFalse);

            // The first default callback is queued, but no frame has run.
            // An ordinary same-owner refresh now makes the owner temporarily
            // busy while preserving revision, directory and editor identity.
            host.readGate = Completer<void>();
            final refresh = page.controller.refresh();
            await _microtasks();
            expect(host.reads, hasLength(2));
            expect(page.controller.busy, isTrue);
            expect(page.controller.error, isNull);
            expect(page.controller.targets!.communities, hasLength(2));
            if (discardWhileBusy) {
              drafts.discard();
            }
            await t.pump();
            expect(drafts.dirty, isFalse);
            expect(host.writes, isEmpty);

            host.finishRead();
            await refresh;
            await t.pump();
            await _frames(t, count: 2);
            expect(page.controller.canEdit, isTrue);
            expect(page.controller.snapshot?['revision'], 0);
            expect(host.reads, hasLength(2));
            expect(host.directories, hasLength(2));
            expect(host.writes, isEmpty);
            expect(drafts.dirty, !discardWhileBusy);
            if (!discardWhileBusy) {
              for (final scope in ['event-room', 'event-A', 'event-B']) {
                expect(
                  _scope(t, scope).choice,
                  const EventSharingChoice(enabled: true, selectedTypes: 47),
                );
              }
              final save = drafts.save();
              await _frames(t);
              expect(await save, isTrue);
              expect(host.writes, hasLength(1));
              expect(host.writes.single.payload['expectedRevision'], 0);
              expect(drafts.dirty, isFalse);
            }
            expect(t.takeException(), isNull);
          } finally {
            await page.close(t);
          }
        },
        timeout: _timeout,
        tags: ['batch3dv-adjacent-review'],
      );
    }
    testWidgets(
      '$suite edited event draft confirms exact readback without a duplicate mutation',
      (t) async {
        for (final absent in [true, false]) {
          final host = _Host()..snapshot = absent ? _absent() : _saved();
          final drafts = PrivacyPageDrafts();
          final page = _Mounted(host, suite, drafts);
          try {
            await page.mount(t);
            await _tap(t, 'privacy-scope-event-room-field-ship');
            expect(_scope(t, 'event-room').choice.selectedTypes, 43);
            host.loseReceipt = true;
            final first = drafts.save();
            await _frames(t);
            expect(await first, isFalse);
            expect(drafts.dirty, isTrue);
            expect(host.writes, hasLength(1));
            expect(page.controller.error, 'events.write_unconfirmed');
            await page.controller.refresh();
            await _frames(t);
            expect(page.controller.error, isNull);
            expect(page.controller.choice(null).selectedTypes, 43);
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
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite edited event draft cannot save old choices into new owner with matching revision and membership',
      (t) async {
        final host = _Host()..snapshot = _saved();
        final drafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t);
          await _tap(t, 'privacy-scope-event-room-field-ship');
          final originalOwner = page.controller.accountKey;
          host.subject = 'new-owner-same-revision-and-membership';
          host.snapshot = _saved(off: true);
          await host.accountChanged();
          await _frames(t);
          expect(page.controller.accountKey, isNot(originalOwner));
          expect(page.controller.snapshot?['revision'], 1);
          expect(page.controller.canEdit, isTrue);
          expect(drafts.dirty, isTrue);
          final save = drafts.save();
          await _frames(t);
          expect(await save, isFalse);
          expect(host.writes, isEmpty);
          expect(drafts.dirty, isTrue);
          expect(drafts.failed, isTrue);
          expect(page.controller.choice(null).enabled, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          await page.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite edited event draft pending old receipt cannot become success after new account read',
      (t) async {
        final host = _Host()..snapshot = _saved();
        final drafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t);
          await _tap(t, 'privacy-scope-event-room-field-ship');
          host.writeGate = Completer<void>();
          final save = drafts.save();
          await _frames(t, count: 2);
          expect(host.writes, hasLength(1));
          expect(page.controller.busy, isTrue);
          host.subject = 'new-owner-before-old-receipt';
          host.snapshot = _saved(revision: 31, off: true);
          await host.accountChanged();
          await _frames(t);
          expect(page.controller.snapshot?['revision'], 31);
          expect(page.controller.error, isNull);
          host.finishWrite();
          await _frames(t);
          expect(await save, isFalse);
          expect(drafts.dirty, isTrue);
          expect(drafts.failed, isTrue);
          expect(host.writes, hasLength(1));
          expect(
            host.writes.single.accountContext?.subject,
            'synthetic-event-owner',
          );
          expect(page.controller.snapshot?['revision'], 31);
          expect(page.controller.choice(null).enabled, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          await page.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite absent event settings stage all types and save all scopes exactly once',
      (t) async {
        final host = _Host();
        final drafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t);
          expect(host.reads, hasLength(1));
          expect(host.directories, hasLength(1));
          expect(host.writes, isEmpty);
          expect(drafts.dirty, isTrue);
          for (final code in ['event-room', 'event-A', 'event-B']) {
            expect(
              _scope(t, code).choice,
              const EventSharingChoice(enabled: true, selectedTypes: 47),
            );
          }
          await _tap(t, 'privacy-scope-event-room-field-ship');
          expect(host.writes, isEmpty);
          final save = drafts.save();
          await _frames(t);
          expect(await save, isTrue);
          expect(host.writes, hasLength(1));
          expect(host.writes.single.payload['expectedRevision'], 0);
          final settings = host.writes.single.payload['settings'] as Map;
          expect(settings['room'], {'enabled': true, 'selectedTypes': 43});
          for (final row in settings['communities'] as List) {
            expect(row['choice'], {'enabled': true, 'selectedTypes': 47});
            expect(row['joinedAt'], _joined);
          }
          expect(drafts.dirty, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          await page.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite explicitly saved event OFF is not absent and never stages default ON',
      (t) async {
        final host = _Host()..snapshot = _saved(off: true);
        final drafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t);
          expect(drafts.dirty, isFalse);
          expect(_scope(t, 'event-room').choice.enabled, isFalse);
          expect(_scope(t, 'event-room').choice.selectedTypes, 47);
          expect(_scope(t, 'event-A').choice.selectedTypes, 32);
          expect(_scope(t, 'event-B').choice.selectedTypes, 8);
          expect(await drafts.save(), isTrue);
          await _frames(t);
          expect(host.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await page.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite disabling an event audience retains its selected types and independent other scopes',
      (t) async {
        final host = _Host()..snapshot = _saved();
        final drafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t);
          await _tap(t, 'privacy-scope-event-room-audience-events-enabled');
          expect(_scope(t, 'event-room').choice.enabled, isFalse);
          expect(_scope(t, 'event-room').choice.selectedTypes, 47);
          expect(host.writes, isEmpty);
          final save = drafts.save();
          await _frames(t);
          expect(await save, isTrue);
          expect(
            page.controller.choice(null),
            const EventSharingChoice(enabled: false, selectedTypes: 47),
          );
          expect(
            page.controller.choice('A'),
            const EventSharingChoice(enabled: true, selectedTypes: 32),
          );
          expect(
            page.controller.choice('B'),
            const EventSharingChoice(enabled: false, selectedTypes: 8),
          );
          expect(host.writes.single.payload['publicationEnabled'], isTrue);
          await _tap(t, 'privacy-scope-event-room-audience-events-enabled');
          expect(_scope(t, 'event-room').choice.selectedTypes, 47);
          expect(_scope(t, 'event-room').choice.enabled, isTrue);
          expect(host.writes, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          await page.close(t);
        }
      },
      timeout: _timeout,
    );

    for (final barrier in ['revision', 'membership stamp']) {
      testWidgets(
        '$suite event draft commit rejects changed $barrier without issuing a mutation',
        (t) async {
          final host = _Host()..snapshot = _saved();
          final drafts = PrivacyPageDrafts();
          final page = _Mounted(host, suite, drafts);
          try {
            await page.mount(t);
            await _tap(t, 'privacy-scope-event-room-field-ship');
            if (barrier == 'revision') {
              host.snapshot = _saved(revision: 2);
            } else {
              host.joinedAt = _rejoined;
            }
            await page.controller.refresh();
            await _frames(t);
            expect(
              page.controller.targets!.communities.first.joinedAt,
              barrier == 'revision' ? _joined : _rejoined,
            );
            final save = drafts.save();
            await _frames(t);
            expect(await save, isFalse);
            expect(host.writes, isEmpty);
            expect(drafts.dirty, isTrue);
            expect(drafts.failed, isTrue);
            expect(t.takeException(), isNull);
          } finally {
            await page.close(t);
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite rejected event save preserves draft and unconfirmed error with no automatic replay',
      (t) async {
        final host = _Host()
          ..snapshot = _saved()
          ..reject = true;
        final drafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t);
          final before = page.controller.snapshot;
          await _tap(t, 'privacy-scope-event-room-field-ship');
          final save = drafts.save();
          await _frames(t);
          expect(await save, isFalse);
          expect(page.controller.snapshot, same(before));
          expect(page.controller.error, 'events.write_unconfirmed');
          expect(page.controller.canEdit, isFalse);
          expect(drafts.dirty, isTrue);
          expect(drafts.failed, isTrue);
          expect(host.writes, hasLength(1));
          expect(host.reads, hasLength(1));
          expect(await drafts.save(), isFalse);
          expect(host.writes, hasLength(1));
          await page.controller.refresh();
          await _frames(t);
          expect(page.controller.canEdit, isTrue);
          expect(drafts.dirty, isTrue);
          host.reject = false;
          final retry = drafts.save();
          await _frames(t);
          expect(await retry, isTrue);
          expect(host.writes, hasLength(2));
          expect(host.reads, hasLength(2));
          expect(t.takeException(), isNull);
        } finally {
          await page.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite original event refresh remains busy and preserves pending draft until target read completes',
      (t) async {
        final host = _Host()..snapshot = _saved();
        final drafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t);
          await _tap(t, 'privacy-scope-event-room-field-ship');
          host.readGate = Completer<void>();
          final refresh = page.controller.refresh();
          await _frames(t, count: 2);
          expect(page.controller.busy, isTrue);
          expect(page.controller.canEdit, isFalse);
          expect(_scope(t, 'event-room').canEdit, isFalse);
          expect(_scope(t, 'event-room').choice.selectedTypes, 43);
          expect(drafts.dirty, isTrue);
          expect(host.writes, isEmpty);
          host.finishRead();
          await refresh;
          await _frames(t);
          expect(page.controller.canEdit, isTrue);
          expect(_scope(t, 'event-room').choice.selectedTypes, 43);
          expect(host.reads, hasLength(2));
          expect(host.directories, hasLength(2));
          expect(host.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await page.close(t);
        }
      },
      timeout: _timeout,
    );

    for (final retirement in ['account', 'page']) {
      testWidgets(
        '$suite event pending response cannot cross $retirement retirement',
        (t) async {
          final host = _Host()..snapshot = _saved();
          final page = _Mounted(host, suite, null);
          try {
            await page.mount(t);
            final before = page.controller.snapshot;
            host.writeGate = Completer<void>();
            await _tap(t, 'privacy-scope-event-room-field-ship');
            await _frames(t, count: 2);
            expect(host.writes, hasLength(1));
            expect(page.controller.busy, isTrue);
            if (retirement == 'account') {
              host.subject = 'synthetic-next-event-owner';
              host.snapshot = _saved(revision: 31, off: true);
              await host.accountChanged();
              await _frames(t);
              expect(page.controller.snapshot?['revision'], 31);
            } else {
              await page.unmount(t);
            }
            host.finishWrite();
            await _frames(t);
            if (retirement == 'account') {
              expect(page.controller.snapshot?['revision'], 31);
              expect(page.controller.choice(null).enabled, isFalse);
            } else {
              expect(page.controller.snapshot, same(before));
            }
            expect(host.writes, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            await page.close(t);
          }
        },
        timeout: _timeout,
      );
    }

    for (final barrier in ['draft epoch discard', 'saved OFF revision']) {
      testWidgets(
        '$suite baseline first-use late callback respects $barrier',
        (t) async {
          final host = _Host()..readGate = Completer<void>();
          final drafts = PrivacyPageDrafts();
          final page = _Mounted(host, suite, drafts);
          try {
            await page.mount(t, settle: false);
            expect(host.reads, hasLength(1));
            host.finishRead();
            await _microtasks();
            expect(page.controller.canEdit, isTrue);
            expect(page.controller.snapshot?['revision'], 0);
            expect(drafts.dirty, isFalse);
            if (barrier == 'draft epoch discard') {
              drafts.discard();
            } else {
              host.snapshot = _saved(off: true);
              await page.controller.refresh();
              expect(page.controller.snapshot?['revision'], 1);
            }
            await t.pump();
            await _frames(t, count: 2);
            expect(
              drafts.dirty,
              isFalse,
              reason: 'A queued default must not override an explicit discard or a newer saved OFF.',
            );
            expect(host.writes, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await page.close(t);
          }
        },
        timeout: _timeout,
        tags: [_baselineTag],
      );
    }

    testWidgets(
      '$suite baseline first-use confirmed readback clears draft without another mutation',
      (t) async {
        final host = _Host()..loseReceipt = true;
        final drafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t);
          final first = drafts.save();
          await _frames(t);
          expect(await first, isFalse);
          expect(drafts.dirty, isTrue);
          expect(host.writes, hasLength(1));
          expect(host.snapshot['revision'], 1);
          await page.controller.refresh();
          await _frames(t);
          expect(page.controller.snapshot?['revision'], 1);
          expect(page.controller.error, isNull);
          host.loseReceipt = false;
          final retry = drafts.save();
          await _frames(t);
          expect(
            await retry,
            isTrue,
            reason: 'The authoritative same-owner readback already confirms these exact choices.',
          );
          expect(drafts.dirty, isFalse);
          expect(host.writes, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          await page.close(t);
        }
      },
      timeout: _timeout,
      tags: [_baselineTag],
    );

    for (final mismatch in [
      'room settings',
      'organization settings',
      'exact membership timestamp',
      'read remains unconfirmed',
      'different account',
      'publication status unconfirmed',
      'publication enabled contradiction',
    ]) {
      testWidgets(
        '$suite first-use readback guard rejects $mismatch without clearing draft or replay',
        (t) async {
          final host = _Host()..loseReceipt = true;
          final drafts = PrivacyPageDrafts();
          final page = _Mounted(host, suite, drafts);
          try {
            await page.mount(t);
            final first = drafts.save();
            await _frames(t);
            expect(await first, isFalse);
            expect(host.writes, hasLength(1));
            expect(host.snapshot['revision'], 1);
            host.loseReceipt = false;
            if (mismatch == 'room settings') {
              final settings = (host.snapshot['settings'] as Map)
                  .cast<String, Object?>();
              host.snapshot = {
                ...host.snapshot,
                'settings': {
                  ...settings,
                  'room': {'enabled': true, 'selectedTypes': 43},
                },
              };
            } else if (mismatch == 'organization settings') {
              final settings = (host.snapshot['settings'] as Map)
                  .cast<String, Object?>();
              final rows = [
                for (final raw in settings['communities'] as List)
                  Map<String, Object?>.from(raw as Map),
              ];
              rows.first['choice'] = {'enabled': true, 'selectedTypes': 1};
              host.snapshot = {
                ...host.snapshot,
                'settings': {...settings, 'communities': rows},
              };
            } else if (mismatch == 'exact membership timestamp') {
              host.joinedAt = _rejoined;
            } else if (mismatch == 'read remains unconfirmed') {
              host.rejectRead = true;
            } else if (mismatch == 'publication status unconfirmed') {
              host.state = 'unconfirmed';
            } else if (mismatch == 'publication enabled contradiction') {
              host.snapshot = {...host.snapshot, 'publicationEnabled': false};
            } else {
              host.subject = 'different-readback-owner';
            }
            if (mismatch == 'different account') {
              await host.accountChanged();
              await _frames(t);
            } else {
              await page.controller.refresh();
              await _frames(t);
            }
            if (mismatch == 'read remains unconfirmed') {
              expect(page.controller.error, 'events.read_unconfirmed');
            } else {
              expect(page.controller.error, isNull);
              expect(page.controller.snapshot?['revision'], 1);
            }
            final retry = drafts.save();
            await _frames(t);
            expect(await retry, isFalse);
            expect(drafts.dirty, isTrue);
            expect(drafts.failed, isTrue);
            expect(host.writes, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            await page.close(t);
          }
        },
        timeout: _timeout,
        tags: [_baselineTag],
      );
    }

    testWidgets(
      '$suite baseline dirty event draft tolerates newly joined target while guarding stale save',
      (t) async {
        final host = _Host()..snapshot = _saved();
        final drafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t);
          await _tap(t, 'privacy-scope-event-room-field-ship');
          host.codes.add('C');
          await page.controller.refresh();
          await t.pump();
          expect(
            t.takeException(),
            isNull,
            reason: 'A newer directory must not dereference a missing old draft map entry.',
          );
          expect(page.controller.targets!.communities, hasLength(3));
          expect(_scope(t, 'event-C').choice, EventSharingChoice.unconfirmed);
          expect(_scope(t, 'event-room').choice.selectedTypes, 43);
          expect(
            _scope(t, 'event-A').choice,
            const EventSharingChoice(enabled: true, selectedTypes: 32),
          );
          expect(host.writes, isEmpty);
          final save = drafts.save();
          await _frames(t);
          expect(await save, isFalse);
          expect(host.writes, isEmpty);
          expect(drafts.dirty, isTrue);
        } finally {
          await page.close(t);
        }
      },
      timeout: _timeout,
      tags: ['batch3dv-new-target'],
    );

    testWidgets(
      '$suite first-use postframe membership replacement retires queued old defaults',
      (t) async {
        final host = _Host()..readGate = Completer<void>();
        final drafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t, settle: false);
          host.finishRead();
          await _microtasks();
          expect(page.controller.canEdit, isTrue);
          expect(drafts.dirty, isFalse);
          host.joinedAt = _rejoined;
          await page.controller.refresh();
          expect(
            page.controller.targets!.communities.first.joinedAt,
            _rejoined,
          );
          await t.pump();
          await _frames(t, count: 2);
          expect(drafts.dirty, isFalse);
          expect(host.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await page.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite first-use postframe draft scope replacement never writes the retired notifier',
      (t) async {
        final host = _Host()..readGate = Completer<void>();
        final drafts = PrivacyPageDrafts();
        final nextDrafts = PrivacyPageDrafts();
        final page = _Mounted(host, suite, drafts);
        try {
          await page.mount(t, settle: false);
          final element = t.element(find.byType(EventSharingPage));
          host.finishRead();
          await _microtasks();
          expect(page.controller.canEdit, isTrue);
          expect(drafts.dirty, isFalse);
          await t.pumpWidget(
            fixture.scopedApp(
              PrivacyDraftScope(
                drafts: nextDrafts,
                child: EventSharingPage(session: host.session),
              ),
              suite,
            ),
          );
          await _frames(t, count: 2);
          expect(t.element(find.byType(EventSharingPage)), same(element));
          expect(drafts.dirty, isFalse);
          expect(nextDrafts.dirty, isFalse);
          expect(host.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await page.close(t);
          nextDrafts.dispose();
        }
      },
      timeout: _timeout,
    );
  }
}
