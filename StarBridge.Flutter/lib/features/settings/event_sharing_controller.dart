import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'community_sharing.dart';
import 'event_scope_editor.dart';

final class EventSharingController extends ChangeNotifier {
  EventSharingController(this.session) {
    _subscription = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _epoch++;
        snapshot = null;
        targets = null;
        _ownerKey = null;
        error = null;
        busy = false;
        notifyListeners();
        unawaited(refresh());
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    unawaited(refresh());
  }
  final BridgeClientSession session;
  late final StreamSubscription _subscription;
  late final Timer _timer;
  int _epoch = 0;
  bool _closed = false, busy = false;
  String? error;
  String? _ownerKey;
  String? get accountKey => _ownerKey;
  String state = 'inactive';
  Map<String, Object?>? snapshot;
  CommunitySharingTargets? targets;
  bool get canEdit =>
      !busy && snapshot != null && targets != null && error == null;
  EventSharingChoice choice(String? code) {
    final settings = snapshot?['settings'] as Map?;
    if (settings == null) return EventSharingChoice.unconfirmed;
    if (code == null) {
      return EventSharingChoice.fromJson((settings['room'] as Map).cast());
    }
    final target = targets!.communities.singleWhere((t) => t.code == code);
    for (final row in settings['communities'] as List) {
      if ((row['code'] as String).toLowerCase() == code.toLowerCase() &&
          row['joinedAt'] == target.joinedAt) {
        return EventSharingChoice.fromJson((row['choice'] as Map).cast());
      }
    }
    return EventSharingChoice.unconfirmed;
  }

  Future<Map<String, Object?>> _request(
    String name,
    Map<String, Object?> payload,
    int epoch,
  ) async {
    if (!session.hostCapabilities.contains('eventSharing.settings')) {
      throw const BridgeClientException('events.unavailable');
    }
    final account = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    if (_closed || epoch != _epoch || !hasRelayAccount(account)) {
      throw const BridgeClientException('events.account_changed');
    }
    final ownerKey =
        '${account.sessionGeneration}:${jsonEncode(account.accountContext?.toJson())}';
    if (_ownerKey != null && _ownerKey != ownerKey) {
      snapshot = null;
      targets = null;
      _ownerKey = null;
      throw const BridgeClientException('events.account_changed');
    }
    if (name == 'eventSharing.save' && _ownerKey == null) {
      throw const BridgeClientException('events.account_changed');
    }
    final response = await session.request(
      name,
      payload: payload,
      accountContext: account.accountContext,
    );
    if (_closed ||
        epoch != _epoch ||
        response.sessionGeneration != account.sessionGeneration ||
        jsonEncode(response.accountContext?.toJson()) !=
            jsonEncode(account.accountContext?.toJson())) {
      throw const BridgeClientException('events.account_changed');
    }
    _ownerKey = ownerKey;
    return response.payload;
  }

  static Map<String, Object?> validate(Map<String, Object?> payload) {
    if (payload.length != 2 ||
        !const {
          'active',
          'inactive',
          'unconfirmed',
        }.contains(payload['state'])) {
      throw const FormatException();
    }
    final value = (payload['snapshot'] as Map).cast<String, Object?>();
    if (value.length != 6 ||
        value['schemaVersion'] != 1 ||
        value['revision'] is! int ||
        (value['revision'] as int) < 0 ||
        value['publicationEnabled'] is! bool) {
      throw const FormatException();
    }
    if (value['revision'] == 0) {
      if (value['settings'] != null ||
          value['operationId'] != null ||
          value['appliedAt'] != null ||
          value['publicationEnabled'] != false) {
        throw const FormatException();
      }
    } else {
      if (value['operationId'] is! String ||
          !RegExp(r'^[0-9a-fA-F]{32}$')
              .hasMatch(value['operationId'] as String) ||
          value['appliedAt'] is! String ||
          DateTime.tryParse(value['appliedAt'] as String) == null) {
        throw const FormatException();
      }
      final settings = value['settings'] as Map;
      if (settings.length != 2) throw const FormatException();
      EventSharingChoice.fromJson((settings['room'] as Map).cast());
      final rows = settings['communities'] as List;
      final targets = <CommunitySharingTarget>[];
      for (final raw in rows) {
        final row = raw as Map;
        if (row.length != 3) throw const FormatException();
        targets.add(
          CommunitySharingTarget(
            code: row['code'] as String,
            name: row['code'] as String,
            joinedAt: row['joinedAt'] as String,
          ),
        );
        EventSharingChoice.fromJson((row['choice'] as Map).cast());
      }
      CommunitySharingTargets(communities: targets);
    }
    return value;
  }

  Future<void> refresh() async {
    if (_closed || busy) return;
    final epoch = _epoch;
    busy = true;
    notifyListeners();
    try {
      final result = await _request('eventSharing.read', const {
        'schemaVersion': 1,
      }, epoch);
      final settings = validate(result);
      final directory = CommunitySharingTargets.fromJson(
        await _request('privacy.communityTargets', const {
          'schemaVersion': 1,
        }, epoch),
      );
      if (_closed || epoch != _epoch) return;
      snapshot = settings;
      targets = directory;
      state = result['state'] as String;
      error = null;
    } catch (e) {
      if (!_closed && epoch == _epoch) {
        error = e is BridgeClientException ? e.code : 'events.response_invalid';
      }
    } finally {
      if (!_closed && epoch == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> change(String? code, EventSharingChoice next) async {
    await saveChoices({code: next});
  }

  Future<void> saveChoices(Map<String?, EventSharingChoice> choices) async {
    if (!canEdit) return;
    final epoch = _epoch;
    final room = choices[null] ?? choice(null);
    final rows = [
      for (final target in targets!.communities)
        {
          'code': target.code,
          'joinedAt': target.joinedAt,
          'choice': (choices[target.code] ?? choice(target.code)).toJson(),
        },
    ];
    final settings = {'room': room.toJson(), 'communities': rows};
    final enabled =
        room.effectiveTypes != 0 ||
        rows.any(
          (r) =>
              EventSharingChoice.fromJson((r['choice'] as Map).cast())
                  .effectiveTypes !=
              0,
        );
    final revision = snapshot!['revision'] as int;
    final random = Random.secure();
    final operation = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    busy = true;
    notifyListeners();
    try {
      final result = await _request('eventSharing.save', {
        'schemaVersion': 1,
        'expectedRevision': revision,
        'operationId': operation,
        'publicationEnabled': enabled,
        'settings': settings,
      }, epoch);
      final value = validate(result);
      if (value['revision'] != revision + 1 ||
          value['operationId'] != operation ||
          value['publicationEnabled'] != enabled ||
          jsonEncode(value['settings']) != jsonEncode(settings)) {
        throw const FormatException();
      }
      snapshot = value;
      state = result['state'] as String;
      error = null;
    } catch (e) {
      if (!_closed && epoch == _epoch) {
        error = e is BridgeClientException
            ? e.code
            : 'events.write_unconfirmed';
      }
    } finally {
      if (!_closed && epoch == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    _timer.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
