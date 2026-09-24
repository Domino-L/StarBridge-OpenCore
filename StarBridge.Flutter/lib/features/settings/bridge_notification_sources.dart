import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'notification_settings_models.dart';

final _deliveryEpochs = Expando<ValueNotifier<int>>();
ValueNotifier<int> notificationSourceDeliveryEpoch(
  BridgeClientSession session,
) => _deliveryEpochs[session] ??= ValueNotifier(0);

class NotificationSourcesValue {
  NotificationSourcesValue(this.revision, List<NotificationSourceRule> sources)
    : sources = List.unmodifiable(sources);
  final int revision;
  final List<NotificationSourceRule> sources;
  Map<String, NotificationSourceMode> get modes => {
    for (final source in sources) source.sourceRef: source.mode,
  };
}

abstract interface class NotificationSourcesPort {
  Stream<void> get invalidations;
  Future<NotificationSourcesValue> read();
  Future<NotificationSourcesValue> save(
    NotificationSourcesValue original,
    Map<String, NotificationSourceMode> modes,
  );
  void dispose();
}

/// The Host owns membership, identities and storage; Flutter only holds an
/// expiring editor lease. Uncertain saves reuse their operation identifier.
class BridgeNotificationSources implements NotificationSourcesPort {
  BridgeNotificationSources(this.session) {
    _events = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _epoch++;
        _owner = null;
        _value = null;
        _pending.clear();
        _invalidations.add(null);
      }
    });
  }
  final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> _events;
  final _invalidations = StreamController<void>.broadcast();
  final _pending = <String, String>{};
  final _random = Random.secure();
  BridgeAccountContext? _owner;
  NotificationSourcesValue? _value;
  int _epoch = 0;
  int? _generation;
  bool _closed = false;
  @override
  Stream<void> get invalidations => _invalidations.stream;
  void _check(int epoch, int generation) {
    if (_closed || epoch != _epoch || generation != session.activeGeneration) {
      throw const BridgeClientException('notificationPolicies.account_changed');
    }
  }

  @override
  Future<NotificationSourcesValue> read() async {
    final epoch = _epoch;
    final account = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    _check(epoch, account.sessionGeneration);
    if (!hasRelayAccount(account)) {
      throw const BridgeClientException('account.signed_out');
    }
    final response = await session.request(
      'notificationPolicies.read',
      accountContext: account.accountContext,
      payload: const {'schemaVersion': 1},
    );
    _check(epoch, account.sessionGeneration);
    final value = parse(response.payload);
    _owner = account.accountContext;
    _generation = account.sessionGeneration;
    _pending.clear();
    _value = value;
    return value;
  }

  @override
  Future<NotificationSourcesValue> save(
    NotificationSourcesValue original,
    Map<String, NotificationSourceMode> modes,
  ) async {
    if (!identical(original, _value) ||
        _owner == null ||
        _generation == null ||
        modes.length != original.sources.length ||
        original.sources.any((s) => !modes.containsKey(s.sourceRef))) {
      throw const BridgeClientException('notificationPolicies.stale_editor');
    }
    final epoch = _epoch, generation = _generation!;
    _check(epoch, generation);
    final keys = modes.keys.toList()..sort();
    final rules = [
      for (final key in keys) {'sourceRef': key, 'mode': modes[key]!.name},
    ];
    final signature = jsonEncode(rules);
    final operation = _pending.putIfAbsent(
      signature,
      () => List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
    );
    notificationSourceDeliveryEpoch(session).value++;
    final response = await session.request(
      'notificationPolicies.save',
      accountContext: _owner,
      payload: {
        'schemaVersion': 1,
        'expectedRevision': original.revision,
        'operationId': operation,
        'rules': rules,
      },
    );
    _check(epoch, generation);
    final next = parse(response.payload);
    if (next.revision != original.revision + 1 ||
        response.payload['operationId'] != operation ||
        keys.any((key) => next.modes[key] != modes[key])) {
      throw const BridgeFormatException('Invalid source rule receipt.');
    }
    _value = next;
    _pending.clear();
    return next;
  }

  static NotificationSourcesValue parse(Map<String, Object?> body) {
    NotificationSourceMode mode(Object? value) =>
        NotificationSourceMode.values.firstWhere(
          (m) => m.name == value,
          orElse: () =>
              throw const BridgeFormatException('Invalid source mode.'),
        );
    final revision = body['revision'], raw = body['sources'];
    if (body['schemaVersion'] != 1 ||
        revision is! int ||
        revision < 0 ||
        raw is! List ||
        raw.length > 64) {
      throw const BridgeFormatException('Invalid source rules.');
    }
    final sources = <NotificationSourceRule>[
      for (final entry in [
        ('room', NotificationSourceKind.room, 'roomMode'),
        ('friends', NotificationSourceKind.friends, 'friendMode'),
        (
          'directMessages',
          NotificationSourceKind.directMessages,
          'directMessageMode',
        ),
      ])
        NotificationSourceRule(
          sourceRef: entry.$1,
          kind: entry.$2,
          displayName: '',
          contextLabel: '',
          mode: mode(body[entry.$3]),
        ),
    ];
    final seen = <String>{};
    for (final row in raw) {
      if (row is! Map ||
          row['sourceRef'] is! String ||
          !RegExp(r'^organization:[a-f0-9]{64}$')
              .hasMatch(row['sourceRef'] as String) ||
          !seen.add(row['sourceRef'] as String) ||
          row['kind'] != 'community' ||
          row['displayName'] is! String ||
          (row['displayName'] as String).trim().isEmpty ||
          (row['logoImageData'] != null && row['logoImageData'] is! String)) {
        throw const BridgeFormatException('Invalid organization source.');
      }
      sources.add(
        NotificationSourceRule(
          sourceRef: row['sourceRef'] as String,
          kind: NotificationSourceKind.community,
          displayName: row['displayName'] as String,
          contextLabel: '',
          mode: mode(row['mode']),
          logoImageData: row['logoImageData'] as String?,
        ),
      );
    }
    return NotificationSourcesValue(revision, sources);
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    _owner = null;
    _value = null;
    _pending.clear();
    _events.cancel();
    _invalidations.close();
  }
}
