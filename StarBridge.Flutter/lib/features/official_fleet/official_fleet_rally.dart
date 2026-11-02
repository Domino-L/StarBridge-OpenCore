import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';

/// Main-fleet rally ("come now", user decision 2026-10-21): the owner asks the
/// members online right now to come. No time, place or sign-up — those belong
/// to 行动. Everyone sees counts only, never who answered.
enum OfficialFleetRallyAnswer { coming, cannot }

@immutable
final class OfficialFleetRally {
  const OfficialFleetRally({
    required this.rallyId,
    required this.text,
    required this.minutes,
    required this.startedAt,
    required this.expiresAt,
    required this.state,
    required this.coming,
    required this.cannot,
    required this.pending,
    this.answer,
    this.starterName,
    this.startedBySelf = false,
  });

  final String rallyId, text, state;
  final int minutes, coming, cannot, pending;
  final DateTime startedAt, expiresAt;
  final OfficialFleetRallyAnswer? answer;

  /// Who started it, when the relay names them (several leaders may rally).
  final String? starterName;
  final bool startedBySelf;

  bool activeAt(DateTime now) => state == 'active' && now.isBefore(expiresAt);
  int minutesLeft(DateTime now) =>
      math.max(0, (expiresAt.difference(now).inSeconds / 60).ceil());

  static OfficialFleetRally parse(Object? value) {
    final starter = value is Map ? value['starter'] : null;
    if (value is! Map ||
        value.length != (value.containsKey('starter') ? 11 : 10) ||
        (value.containsKey('starter') &&
            (starter is! Map ||
                starter.length != 2 ||
                !starter.containsKey('displayName') ||
                starter['isSelf'] is! bool ||
                (starter['displayName'] != null &&
                    (starter['displayName'] is! String ||
                        (starter['displayName'] as String).trim().isEmpty ||
                        (starter['displayName'] as String).length > 128)))) ||
        value['rallyId'] is! String ||
        value['text'] is! String ||
        value['minutes'] is! int ||
        value['startedAt'] is! String ||
        value['expiresAt'] is! String ||
        value['coming'] is! int ||
        value['cannot'] is! int ||
        value['pending'] is! int ||
        !const {'active', 'ended', 'expired'}.contains(value['state'])) {
      throw const FormatException('Invalid rally');
    }
    final answer = switch (value['response']) {
      null => null,
      'coming' => OfficialFleetRallyAnswer.coming,
      'cannot' => OfficialFleetRallyAnswer.cannot,
      _ => throw const FormatException('Invalid rally answer'),
    };
    final counts = [value['coming'], value['cannot'], value['pending']];
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(value['rallyId'] as String) ||
        !const {15, 30, 60}.contains(value['minutes']) ||
        counts.any((count) => (count as int) < 0)) {
      throw const FormatException('Invalid rally');
    }
    return OfficialFleetRally(
      rallyId: value['rallyId'] as String,
      text: value['text'] as String,
      minutes: value['minutes'] as int,
      startedAt: DateTime.parse(value['startedAt'] as String),
      expiresAt: DateTime.parse(value['expiresAt'] as String),
      state: value['state'] as String,
      coming: value['coming'] as int,
      cannot: value['cannot'] as int,
      pending: value['pending'] as int,
      answer: answer,
      starterName: starter is Map ? starter['displayName'] as String? : null,
      startedBySelf: starter is Map && starter['isSelf'] == true,
    );
  }
}

@immutable
final class OfficialFleetRallySnapshot {
  const OfficialFleetRallySnapshot({required this.onlineCount, this.rally});
  final int onlineCount;
  final OfficialFleetRally? rally;

  static OfficialFleetRallySnapshot parse(Map<String, Object?> row) {
    if (row['schemaVersion'] != 1 || row['onlineCount'] is! int) {
      throw const FormatException('Invalid rally state');
    }
    final rally = row['rally'];
    return OfficialFleetRallySnapshot(
      onlineCount: row['onlineCount'] as int,
      rally: rally == null ? null : OfficialFleetRally.parse(rally),
    );
  }
}

@immutable
final class OfficialFleetRallyEligibility {
  const OfficialFleetRallyEligibility({
    required this.canStart,
    required this.onlineCount,
    required this.remainingThisHour,
  });
  static const none = OfficialFleetRallyEligibility(
    canStart: false,
    onlineCount: 0,
    remainingThisHour: 0,
  );
  final bool canStart;
  final int onlineCount, remainingThisHour;

  static OfficialFleetRallyEligibility parse(Map<String, Object?> row) {
    if (row['schemaVersion'] != 1 ||
        row['canStart'] is! bool ||
        row['onlineCount'] is! int ||
        row['remainingThisHour'] is! int) {
      throw const FormatException('Invalid rally eligibility');
    }
    return OfficialFleetRallyEligibility(
      canStart: row['canStart'] as bool,
      onlineCount: row['onlineCount'] as int,
      remainingThisHour: row['remainingThisHour'] as int,
    );
  }
}

/// `conflict` (another rally is running or this one ended), `rateLimited`
/// (three per hour), `notAllowed`, `unavailable`.
final class OfficialFleetRallyFailure implements Exception {
  const OfficialFleetRallyFailure(this.code);
  final String code;
  @override
  String toString() => 'OfficialFleetRallyFailure($code)';
}

abstract interface class OfficialFleetRallyPort {
  bool get available;
  Future<OfficialFleetRallySnapshot> read(
    String sourceRef, {
    required bool online,
  });
  Future<OfficialFleetRallyEligibility> eligibility(String sourceRef);
  Future<OfficialFleetRallySnapshot> start(
    String sourceRef, {
    required String operationId,
    required String text,
    required int minutes,
  });
  Future<OfficialFleetRallySnapshot> respond(
    String sourceRef,
    String rallyId,
    OfficialFleetRallyAnswer answer,
  );
  Future<OfficialFleetRallySnapshot> end(String sourceRef, String rallyId);
}

final class UnavailableOfficialFleetRallyPort
    implements OfficialFleetRallyPort {
  const UnavailableOfficialFleetRallyPort();
  @override
  bool get available => false;
  Never _unavailable() => throw const OfficialFleetRallyFailure('unavailable');
  @override
  Future<OfficialFleetRallySnapshot> read(
    String sourceRef, {
    required bool online,
  }) async => _unavailable();
  @override
  Future<OfficialFleetRallyEligibility> eligibility(String sourceRef) async =>
      _unavailable();
  @override
  Future<OfficialFleetRallySnapshot> start(
    String sourceRef, {
    required String operationId,
    required String text,
    required int minutes,
  }) async => _unavailable();
  @override
  Future<OfficialFleetRallySnapshot> respond(
    String sourceRef,
    String rallyId,
    OfficialFleetRallyAnswer answer,
  ) async => _unavailable();
  @override
  Future<OfficialFleetRallySnapshot> end(
    String sourceRef,
    String rallyId,
  ) async => _unavailable();
}

final class BridgeOfficialFleetRallyPort implements OfficialFleetRallyPort {
  BridgeOfficialFleetRallyPort(this.session, {this.onlineTrafficAllowed});
  static const command = 'officialFleet.rally';

  /// Host can name who started a rally when asked.
  static const starterCapability = 'officialFleet.rallyStarter';
  final BridgeClientSession session;
  final bool Function()? onlineTrafficAllowed;

  @override
  bool get available =>
      session.hostCapabilities.contains(command) &&
      !session.connectionModeChanging &&
      onlineTrafficAllowed?.call() != false;

  Future<Map<String, Object?>> _send(Map<String, Object?> payload) async {
    if (!available) throw const OfficialFleetRallyFailure('unavailable');
    final generation = session.activeGeneration;
    try {
      final account = await session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
        timeout: const Duration(seconds: 15),
      );
      if (account.payload['state'] != 'signedIn' ||
          account.accountContext == null ||
          generation != session.activeGeneration) {
        throw const OfficialFleetRallyFailure('unavailable');
      }
      final reply = await session.request(
        command,
        payload: {
          'schemaVersion': 1,
          ...payload,
          if (session.hostCapabilities.contains(starterCapability))
            'include': const ['starter'],
        },
        accountContext: account.accountContext,
        timeout: const Duration(seconds: 15),
      );
      if (generation != session.activeGeneration || !available) {
        throw const OfficialFleetRallyFailure('unavailable');
      }
      final row = reply.payload;
      if (row['sourceRef'] != payload['sourceRef']) {
        throw const FormatException('Rally source changed');
      }
      return row;
    } on BridgeClientException catch (error) {
      throw OfficialFleetRallyFailure(switch (error.code) {
        'officialFleet.rallyConflict' => 'conflict',
        'officialFleet.rallyRateLimited' => 'rateLimited',
        'communities.notAllowed' => 'notAllowed',
        _ => 'unavailable',
      });
    } on FormatException {
      throw const OfficialFleetRallyFailure('unavailable');
    }
  }

  Future<OfficialFleetRallySnapshot> _state(
    Map<String, Object?> payload,
  ) async {
    final row = await _send(payload);
    try {
      return OfficialFleetRallySnapshot.parse(row);
    } on FormatException {
      throw const OfficialFleetRallyFailure('unavailable');
    }
  }

  @override
  Future<OfficialFleetRallySnapshot> read(
    String sourceRef, {
    required bool online,
  }) => _state({'action': 'read', 'sourceRef': sourceRef, 'online': online});

  @override
  Future<OfficialFleetRallyEligibility> eligibility(String sourceRef) async {
    final row = await _send({'action': 'eligibility', 'sourceRef': sourceRef});
    try {
      return OfficialFleetRallyEligibility.parse(row);
    } on FormatException {
      throw const OfficialFleetRallyFailure('unavailable');
    }
  }

  @override
  Future<OfficialFleetRallySnapshot> start(
    String sourceRef, {
    required String operationId,
    required String text,
    required int minutes,
  }) => _state({
    'action': 'start',
    'sourceRef': sourceRef,
    'operationId': operationId,
    'text': text,
    'minutes': minutes,
  });

  @override
  Future<OfficialFleetRallySnapshot> respond(
    String sourceRef,
    String rallyId,
    OfficialFleetRallyAnswer answer,
  ) => _state({
    'action': 'respond',
    'sourceRef': sourceRef,
    'rallyId': rallyId,
    'response': answer.name,
  });

  @override
  Future<OfficialFleetRallySnapshot> end(String sourceRef, String rallyId) =>
      _state({'action': 'end', 'sourceRef': sourceRef, 'rallyId': rallyId});
}

/// One per client run, owned by the official fleet module. It reads the rally
/// every [interval] while bound to a fleet (the same cadence as the fleet's
/// own refresh), so a rally reaches members within that time on any page.
class OfficialFleetRallyController extends ChangeNotifier {
  OfficialFleetRallyController(
    this.port, {
    bool Function()? countedOnline,
    DateTime Function()? now,
    this.interval = const Duration(seconds: 15),
    Stream<OfficialFleetRallyHotkey>? hotkeys,
  }) : _countedOnline = countedOnline ?? (() => true),
       _now = now ?? DateTime.now {
    _hotkeys = hotkeys?.listen(
      (key) => unawaited(respondFromHotkey(key.rallyId, key.answer)),
    );
  }
  StreamSubscription<OfficialFleetRallyHotkey>? _hotkeys;

  final OfficialFleetRallyPort port;
  final bool Function() _countedOnline;
  final DateTime Function() _now;
  final Duration interval;
  final _random = math.Random.secure();
  String? _source;
  String? _fleetName;
  Timer? _timer;
  int _epoch = 0;
  bool _reading = false, _disposed = false, _busy = false;
  OfficialFleetRallySnapshot? _snapshot;
  OfficialFleetRallyEligibility _eligibility =
      OfficialFleetRallyEligibility.none;
  bool _eligibilityDue = false, _eligibilityKnown = false;
  final Set<String> _dismissed = {}, _announced = {}, _quiet = {};

  String? get sourceRef => _source;
  String? get fleetName => _fleetName;
  bool get busy => _busy;
  OfficialFleetRallySnapshot? get snapshot => _snapshot;
  OfficialFleetRallyEligibility get eligibility => _eligibility;
  bool get canStart => port.available && _eligibility.canStart;
  DateTime now() => _now();

  /// The rally to show in the page strip while it runs or just closed.
  OfficialFleetRally? get current => _snapshot?.rally;

  /// An active rally this member has neither answered nor dismissed. The
  /// owner never gets their own rally as a prompt.
  OfficialFleetRally? get prompt {
    final rally = current;
    if (rally == null ||
        !rally.activeAt(_now()) ||
        rally.answer != null ||
        _eligibility.canStart ||
        _dismissed.contains(rally.rallyId)) {
      return null;
    }
    return rally;
  }

  /// The prompt that may alert (Windows notification, taskbar). A rally first
  /// read while this client was invisible or offline stays quiet even after it
  /// comes back online, the same rule as the Host's overlay alert and sound.
  OfficialFleetRally? get alertPrompt {
    final rally = prompt;
    if (rally == null || _quiet.contains(rally.rallyId)) return null;
    return rally;
  }

  /// Returns the alert prompt once per rally, for the desktop notification.
  OfficialFleetRally? takeAnnouncement() {
    final rally = alertPrompt;
    if (rally == null || !_announced.add(rally.rallyId)) return null;
    return rally;
  }

  void bind(String? sourceRef, {String? fleetName}) {
    if (_disposed) return;
    _fleetName = fleetName;
    if (sourceRef == _source) return;
    _epoch++;
    _source = sourceRef;
    _snapshot = null;
    _eligibility = OfficialFleetRallyEligibility.none;
    _eligibilityDue = _eligibilityKnown = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
    // No Host support means no rally at all, and no idle timer either.
    if (sourceRef == null || !port.available) return;
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
    unawaited(refresh(eligibility: true));
  }

  Future<void> refresh({bool eligibility = false}) async {
    final source = _source, epoch = _epoch;
    // A rights question asked during a read, or lost to a failed one, is
    // answered by the next read rather than dropped.
    _eligibilityDue |= eligibility;
    if (_disposed || source == null || _reading || !port.available) return;
    final askRights = _eligibilityDue;
    _eligibilityDue = false;
    _reading = true;
    var again = false, failedRights = false;
    try {
      final online = _countedOnline();
      final snapshot = await port.read(source, online: online);
      if (_disposed || epoch != _epoch) return;
      // Record a quiet (invisible/offline) sighting before anything else can
      // fail, so a later eligibility miss cannot make it alert after all.
      final rally = snapshot.rally;
      if (!online && rally != null) _quiet.add(rally.rallyId);
      OfficialFleetRallyEligibility? rights;
      try {
        if (askRights) rights = await port.eligibility(source);
      } on OfficialFleetRallyFailure {
        failedRights = true;
        // Rights never answered yet: an owner's own rally must not read as a
        // prompt. Once they were, a failed question leaves the board updating.
        if (!_eligibilityKnown) {
          _eligibilityDue = true;
          return;
        }
      }
      if (_disposed || epoch != _epoch) return;
      _snapshot = snapshot;
      if (rights != null) {
        _eligibility = rights;
        _eligibilityKnown = true;
      }
      notifyListeners();
      // Asked during this read: right now, not at the next tick.
      again = _eligibilityDue;
      _eligibilityDue |= failedRights;
    } on OfficialFleetRallyFailure {
      // A quiet miss: the next tick reads again; nothing is shown as failed.
      _eligibilityDue |= askRights;
    } finally {
      _reading = false;
    }
    if (again) unawaited(refresh());
  }

  Future<String?> start(String text, int minutes) => _write(
    (source) => port.start(
      source,
      operationId: _operationId(),
      text: text.trim(),
      minutes: minutes,
    ),
    eligibility: true,
  );

  Future<String?> respond(OfficialFleetRallyAnswer answer) {
    final rally = current;
    if (rally == null) return Future.value('conflict');
    _dismissed.add(rally.rallyId);
    return _write((source) => port.respond(source, rally.rallyId, answer));
  }

  /// A hotkey answer (Ctrl+Alt+Y / Ctrl+Alt+N) counts only for the rally this
  /// member is being asked about right now; a stale or foreign id is ignored.
  Future<String?> respondFromHotkey(
    String rallyId,
    OfficialFleetRallyAnswer answer,
  ) {
    final rally = prompt;
    if (_disposed || rally == null || rally.rallyId != rallyId) {
      return Future.value('conflict');
    }
    return respond(answer);
  }

  Future<String?> end() {
    final rally = current;
    if (rally == null) return Future.value('conflict');
    return _write(
      (source) => port.end(source, rally.rallyId),
      eligibility: true,
    );
  }

  void dismiss() {
    final rally = current;
    if (rally == null) return;
    _dismissed.add(rally.rallyId);
    notifyListeners();
  }

  /// Returns null on success, else a failure code for the caller to show.
  Future<String?> _write(
    Future<OfficialFleetRallySnapshot> Function(String source) action, {
    bool eligibility = false,
  }) async {
    final source = _source, epoch = _epoch;
    if (_disposed || source == null || _busy) return 'unavailable';
    _busy = true;
    notifyListeners();
    try {
      final snapshot = await action(source);
      if (_disposed || epoch != _epoch) return 'unavailable';
      _snapshot = snapshot;
      if (eligibility) {
        try {
          _eligibility = await port.eligibility(source);
        } on OfficialFleetRallyFailure {
          /* The rally itself was saved; rights refresh on the next open. */
        }
      }
      return null;
    } on OfficialFleetRallyFailure catch (failure) {
      if (failure.code == 'conflict') unawaited(refresh(eligibility: true));
      return failure.code;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  String _operationId() =>
      List.generate(32, (_) => '0123456789abcdef'[_random.nextInt(16)]).join();

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_hotkeys?.cancel());
    super.dispose();
  }
}

/// A rally answer the Host routed from a safe hotkey.
typedef OfficialFleetRallyHotkey = ({
  String rallyId,
  OfficialFleetRallyAnswer answer,
});

/// Host `officialFleet.rallyHotkey` events, validated; anything else dropped.
Stream<OfficialFleetRallyHotkey> officialFleetRallyHotkeys(
  BridgeClientSession session,
) => session.events
    .where((event) => event.name == 'officialFleet.rallyHotkey')
    .map((event) {
      final p = event.payload;
      final id = p['rallyId'], answer = p['answer'];
      if (p['schemaVersion'] != 1 ||
          id is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
        return null;
      }
      final value = switch (answer) {
        'coming' => OfficialFleetRallyAnswer.coming,
        'cannot' => OfficialFleetRallyAnswer.cannot,
        _ => null,
      };
      return value == null ? null : (rallyId: id, answer: value);
    })
    .where((key) => key != null)
    .cast<OfficialFleetRallyHotkey>();
