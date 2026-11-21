import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../common/callsign_rules.dart';

class GameIdVisibilityController extends ChangeNotifier {
  GameIdVisibilityController(this.session) {
    _events = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _epoch++;
        _owner = null;
        snapshot = null;
        busy = false;
        _refreshing = false;
        notifyListeners();
        unawaited(refresh());
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    unawaited(refresh());
  }
  final BridgeClientSession session;
  late final StreamSubscription _events;
  late final Timer _timer;
  bool busy = false, _closed = false;
  bool _refreshing = false;
  int _epoch = 0;
  String? _owner, error;
  Map<String, Object?>? snapshot;
  int get locations => snapshot?['locations'] as int? ?? 0;
  bool get canEdit =>
      !busy && error == null && snapshot?['canConfigure'] == true;

  /// SCM accounts (11-15 decision 甲): one callsign, Relay first, Hong Kong kept
  /// in step. Legacy accounts keep the five-field snapshot without these.
  bool get hasCallsign => snapshot?.containsKey('callsign') == true;

  /// Decision 乙: hiding needs an independent callsign. Without one an SCM account
  /// may still turn places back to "show" (never hide more).
  bool get needsCallsignToHide =>
      hasCallsign && snapshot?['canConfigure'] == false;
  bool canChange(int next) =>
      canEdit ||
      (needsCallsignToHide &&
          !busy &&
          error == null &&
          (next & locations) == locations);
  String? get callsign => snapshot?['callsign'] as String?;

  /// synced | pending | restorePending | unknown
  String get mirror => snapshot?['mirror'] as String? ?? 'synced';
  String? callsignError;

  /// Which action the mirror state follows: 'callsign', 'settings' or 'found'
  /// (seen on a read, not after a save here). Wording only.
  String lastSave = 'found';

  static const mirrorStates = {'synced', 'pending', 'restorePending', 'unknown'};

  static bool validCallsign(String value) => CallsignRules.valid(value);

  static Map<String, Object?> validate(Map<String, Object?> value) {
    final revision = value['revision'],
        locations = value['locations'],
        stamp = value['identityStamp'];
    final callsign = value['callsign'];
    const legacyKeys = {
      'schemaVersion',
      'revision',
      'locations',
      'canConfigure',
      'identityStamp',
    };
    final scm =
        value.length == 7 &&
        value.keys.toSet().containsAll({...legacyKeys, 'callsign', 'mirror'});
    if ((!scm &&
            (value.length != 5 || !value.keys.toSet().containsAll(legacyKeys))) ||
        (scm &&
            ((callsign != null &&
                    (callsign is! String ||
                        callsign.isEmpty ||
                        callsign != callsign.trim() ||
                        !CallsignRules.valid(callsign))) ||
                !mirrorStates.contains(value['mirror']))) ||
        value['schemaVersion'] != 1 ||
        revision is! int ||
        revision < 0 ||
        locations is! int ||
        locations < 0 ||
        locations > 15 ||
        value['canConfigure'] is! bool ||
        stamp is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(stamp) ||
        // Legacy accounts: without an independent callsign everything shows. SCM
        // accounts may keep an explicit earlier hide without one (decision 乙).
        (!scm &&
            value['canConfigure'] == false &&
            locations != 0 &&
            locations != 15)) {
      throw const FormatException();
    }
    return Map.unmodifiable(value);
  }

  Future<Map<String, Object?>> _request(
    String name,
    Map<String, Object?> payload,
    int epoch,
  ) async {
    if (!session.hostCapabilities.contains('gameIdVisibility.settings')) {
      throw const BridgeClientException('host.capability_missing');
    }
    final account = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    if (_closed || epoch != _epoch || !hasRelayAccount(account)) {
      throw const BridgeClientException('gameId.account_changed');
    }
    final owner =
        '${account.sessionGeneration}:${jsonEncode(account.accountContext?.toJson())}';
    if ((_owner != null && _owner != owner) ||
        (name.endsWith('.save') && _owner == null)) {
      snapshot = null;
      _owner = null;
      throw const BridgeClientException('gameId.account_changed');
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
      throw const BridgeClientException('gameId.account_changed');
    }
    _owner = owner;
    return validate(response.payload);
  }

  DateTime? _lastAutoRetry;
  Duration _autoRetryDelay = const Duration(minutes: 2);

  Future<void> refresh() async {
    if (_closed || busy || _refreshing) return;
    // Out of step with Hong Kong: retry on its own while the card is open, never on
    // every poll. The wait doubles after each attempt (2, 4, 8 ... up to 30 minutes)
    // and resets once both sides agree. The Host retries only the pending half.
    final outOfStep =
        hasCallsign && (mirror == 'pending' || mirror == 'restorePending');
    if (!outOfStep) {
      _lastAutoRetry = null;
      _autoRetryDelay = const Duration(minutes: 2);
    } else if (_lastAutoRetry == null ||
        DateTime.now().difference(_lastAutoRetry!) >= _autoRetryDelay) {
      if (_lastAutoRetry != null) {
        final doubled = _autoRetryDelay * 2;
        _autoRetryDelay = doubled > const Duration(minutes: 30)
            ? const Duration(minutes: 30)
            : doubled;
      }
      _lastAutoRetry = DateTime.now();
      await retrySync(automatic: true);
      return;
    }
    final epoch = _epoch;
    _refreshing = true;
    busy = snapshot == null;
    if (busy) notifyListeners();
    try {
      final value = await _request('gameIdVisibility.read', const {
        'schemaVersion': 1,
      }, epoch);
      if (!_closed && epoch == _epoch) {
        snapshot = value;
        error = null;
      }
    } catch (_) {
      if (!_closed && epoch == _epoch) error = 'unavailable';
    } finally {
      if (!_closed && epoch == _epoch) {
        busy = false;
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> change(int bit, bool enabled) async {
    if (!const {1, 2, 4, 8}.contains(bit)) return;
    final next = enabled ? locations | bit : locations & ~bit;
    if (!canChange(next)) return;
    await saveLocations(next);
  }

  Future<void> saveLocations(int next) async {
    if (next < 0 || next > 15 || !canChange(next)) return;
    // A save supersedes older background reads, including their errors.
    final epoch = ++_epoch, before = snapshot!;
    lastSave = 'settings';
    _refreshing = false;
    busy = true;
    notifyListeners();
    var failed = false;
    try {
      final value = await _request('gameIdVisibility.save', {
        'schemaVersion': 1,
        'expectedRevision': before['revision'],
        'identityStamp': before['identityStamp'],
        'locations': next,
      }, epoch);
      if (value['locations'] != next ||
          value['revision'] != (before['revision'] as int) + 1 ||
          value['identityStamp'] != before['identityStamp']) {
        throw const FormatException();
      }
      if (!_closed && epoch == _epoch) {
        snapshot = value;
        error = null;
      }
    } catch (_) {
      failed = true;
      if (!_closed && epoch == _epoch) error = 'unconfirmed';
    } finally {
      if (!_closed && epoch == _epoch) {
        busy = false;
        notifyListeners();
        if (failed) unawaited(refresh());
      }
    }
  }

  /// Saves the one callsign (null or blank clears it). Returns true when the Relay
  /// saved it; [mirror] then tells whether Hong Kong is in step.
  Future<bool> saveCallsign(String? value) async {
    final text = value?.trim() ?? '';
    if (!hasCallsign || busy || snapshot == null) return false;
    if (!validCallsign(text)) {
      callsignError = 'invalid';
      notifyListeners();
      return false;
    }
    final epoch = ++_epoch, before = snapshot!;
    _refreshing = false;
    busy = true;
    callsignError = null;
    lastSave = 'callsign';
    notifyListeners();
    var saved = false;
    try {
      final next = await _request('gameIdVisibility.saveCallsign', {
        'schemaVersion': 1,
        'expectedRevision': before['revision'],
        'identityStamp': before['identityStamp'],
        'callsign': text.isEmpty ? null : text,
      }, epoch);
      if (next['revision'] != (before['revision'] as int) + 1 ||
          next['callsign'] != (text.isEmpty ? null : text)) {
        throw const FormatException();
      }
      if (!_closed && epoch == _epoch) {
        snapshot = next;
        error = null;
        saved = true;
      }
    } on BridgeClientException catch (e) {
      if (!_closed && epoch == _epoch) {
        callsignError = switch (e.code) {
          'callsign.invalid' => 'invalid',
          'gameId.conflict' => 'conflict',
          'callsign.hidden_requires_callsign' => 'hiddenRequiresCallsign',
          _ => 'unavailable',
        };
      }
    } catch (_) {
      if (!_closed && epoch == _epoch) callsignError = 'unavailable';
    } finally {
      if (!_closed && epoch == _epoch) {
        busy = false;
        notifyListeners();
        if (!saved) unawaited(refresh());
      }
    }
    return saved;
  }

  /// Pushes the out-of-step half to Hong Kong again. [automatic] is the card's own
  /// timer; the Host then honours its restore cooldown (a tap always tries).
  Future<void> retrySync({bool automatic = false}) async {
    if (!hasCallsign || busy || snapshot == null) return;
    final epoch = ++_epoch;
    _refreshing = false;
    busy = true;
    notifyListeners();
    try {
      final next = await _request('gameIdVisibility.retrySync', {
        'schemaVersion': 1,
        if (automatic) 'automatic': true,
      }, epoch);
      if (!_closed && epoch == _epoch) {
        snapshot = next;
        error = null;
      }
    } catch (_) {
      // Keep the last known state; the next poll reads it again.
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
    unawaited(_events.cancel());
    super.dispose();
  }
}
