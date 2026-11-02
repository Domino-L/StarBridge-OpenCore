import 'dart:convert';

import 'bridge_envelope.dart';
import 'bridge_request_operation.dart';
import 'bridge_shared_account_read.dart';

typedef _BeginRead = BridgeRequestOperation Function(
  String name,
  Map<String, Object?> payload,
  BridgeAccountContext owner,
  BridgeDisplayProgress? progress,
);

/// Only unfinished, identical friend reads. Each consumer keeps its own
/// deadline, cancellation and optional display. No completed response is kept.
final class SharedFriendsReads {
  SharedFriendsReads(this._begin, this._pending);
  final _BeginRead _begin;
  final bool Function(String id) _pending;
  final _reads = <String, SharedAccountRead>{};
  int _revision = 0;
  (String, int)? _socialCursor;

  BridgeRequestOperation? begin(
    String name,
    Map<String, Object?> payload,
    BridgeAccountContext? owner,
    Duration timeout,
    BridgeDisplayProgress? progress,
  ) {
    if (owner == null || !_eligible(name, payload, progress)) return null;
    final fields = payload.keys.toList()..sort();
    final key = jsonEncode([
      name,
      owner.environment,
      owner.authority,
      owner.subject,
      {for (final field in fields) field: payload[field]},
    ]);
    var shared = _reads[key];
    if (shared != null &&
        (shared.settled || !_pending(shared.operation.correlationId!))) {
      _reads.remove(key);
      shared.clearDisplay();
      shared = null;
    }
    BridgeEnvelope? early;
    if (shared == null) {
      if (_reads.length >= 8) return null;
      final revision = _revision;
      SharedAccountRead? admitted;
      final wantsDisplay = payload['cachedDisplayProgress'] == true;
      final operation = _begin(
        name,
        payload,
        owner,
        wantsDisplay
            ? BridgeDisplayProgress('friends.readDisplay', (frame) {
                if (admitted == null) {
                  early = frame;
                } else {
                  admitted.publishDisplay(frame);
                }
              })
            : null,
      );
      late final SharedAccountRead created;
      created = SharedAccountRead(
        operation,
        () {
          if (identical(_reads[key], created)) _reads.remove(key);
        },
        wantsDisplay,
        requestName: name,
        displayCorrelationKey: 'requestCorrelationId',
      );
      admitted = shared = created;
      if (revision == _revision && _pending(operation.correlationId!)) {
        _reads[key] = created;
      }
    }
    final operation = shared.subscribe(
      timeout,
      progress == null
          ? null
          : (frame) {
              if (frame == null) return;
              try {
                progress.accept(frame);
              } on Object {
                // One optional display cannot interrupt another consumer's transport.
              }
            },
      null,
    );
    if (early != null && _reads[key] == shared) shared.publishDisplay(early!);
    return operation;
  }

  void retire() {
    _revision++;
    final old = _reads.values.toList();
    _reads.clear();
    for (final read in old) {
      read.clearDisplay();
    }
  }

  void completed(String name, BridgeEnvelope response) {
    final keys = _reads.entries
        .where((e) => e.value.operation.correlationId == response.correlationId)
        .map((e) => e.key)
        .toList();
    for (final key in keys) {
      _reads.remove(key)?.clearDisplay();
    }
    if (boundary(name)) retire();
    final body = response.payload;
    if (name == 'social.wait' &&
        response.status == 'ok' &&
        body['schemaVersion'] == 1 &&
        body['instance'] is String &&
        RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(body['instance']! as String) &&
        body['version'] is int &&
        (body['version']! as int) >= 0) {
      final cursor = (body['instance']! as String, body['version']! as int);
      if (_socialCursor != cursor) {
        _socialCursor = cursor;
        retire();
      }
    }
  }

  void event(String name) {
    if (const {
      'account.changed',
      'bootstrap.invalidated',
      'account.presentationChanged',
      'account.avatarChanged',
      'friendSharing.changed',
      'friends.changed',
    }.contains(name)) {
      retire();
    }
  }

  bool boundary(String name) =>
      name == 'friends.execute' ||
      name == 'directMessages.send' ||
      name == 'friendRequests.privacyWrite' ||
      name == 'friendSharing.save' ||
      (name.startsWith('account.') &&
          name != 'account.getCurrent' &&
          name != 'account.offlineData.read' &&
          name != 'account.scmRouteRead' &&
          name != 'account.scmRouteSave');

  bool _eligible(
    String name,
    Map<String, Object?> p,
    BridgeDisplayProgress? progress,
  ) {
    if (p['schemaVersion'] is! int || p['schemaVersion'] != 1) return false;
    if (name == 'friends.readPage') {
      return progress == null &&
          p.length >= 3 &&
          p.length <= 4 &&
          p.keys.every(
            const {
              'schemaVersion',
              'snapshotId',
              'offset',
              'displayRequestId',
            }.contains,
          ) &&
          p['snapshotId'] is String &&
          RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(p['snapshotId']! as String) &&
          p['offset'] is int &&
          (p['offset']! as int) >= 0 &&
          (!p.containsKey('displayRequestId') ||
              p['displayRequestId'] is String);
    }
    if (name != 'friends.read' ||
        p.length > 4 ||
        !p.keys.every(
          const {
            'schemaVersion',
            'query',
            'pagedResponse',
            'cachedDisplayProgress',
          }.contains,
        )) {
      return false;
    }
    for (final flag in ['pagedResponse', 'cachedDisplayProgress']) {
      if (p.containsKey(flag) && p[flag] is! bool) return false;
    }
    if (p.containsKey('query')) {
      final query = p['query'];
      if (query is! String ||
          query.trim().length < 2 ||
          query.trim().length > 128 ||
          RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(query) ||
          p['cachedDisplayProgress'] == true) {
        return false;
      }
    }
    return progress == null ||
        (progress.eventName == 'friends.readDisplay' &&
            p['cachedDisplayProgress'] == true);
  }
}
