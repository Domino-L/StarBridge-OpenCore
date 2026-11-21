import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../account/account_models.dart';
import '../onboarding/connection_mode_port.dart';
import 'achievement_read_scope.dart';
import 'achievement_collection_port.dart';

final class SwiftEntry {
  const SwiftEntry(this.rank, this.handle, this.bestMs, this.achievedOn);
  final int rank, bestMs;
  final String handle;
  final DateTime achievedOn;
}

final class SwiftBoard {
  const SwiftBoard(this.entries, this.rank, this.bestMs, this.optedIn);
  final List<SwiftEntry> entries;
  final int? rank, bestMs;
  final bool optedIn;
  factory SwiftBoard.parse(Map<String, Object?> json) {
    final entries = json['entries'], me = json['me'];
    if (json['schemaVersion'] != 1 ||
        !_date(json['computedAt']) ||
        entries is! List ||
        entries.length > 100 ||
        me is! Map ||
        me['optedIn'] is! bool ||
        me['rank'] != null && (me['rank'] is! int || (me['rank'] as int) < 1) ||
        me['bestMs'] != null && !_ms(me['bestMs']) ||
        me['rank'] != null && (me['optedIn'] != true || me['bestMs'] == null)) {
      throw const FormatException('Invalid leaderboard');
    }
    final parsed = <SwiftEntry>[];
    for (final raw in entries) {
      if (raw is! Map ||
          raw['rank'] != parsed.length + 1 ||
          raw['handle'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,60}$').hasMatch(raw['handle'] as String) ||
          !_ms(raw['bestMs']) ||
          !_day(raw['achievedOn']) ||
          raw.containsKey('achievedAt')) {
        throw const FormatException('Invalid leaderboard entry');
      }
      final e = SwiftEntry(
        raw['rank'] as int,
        raw['handle'] as String,
        raw['bestMs'] as int,
        DateTime.parse('${raw['achievedOn']}T00:00:00Z'),
      );
      if (parsed.isNotEmpty &&
          (parsed.last.bestMs > e.bestMs ||
              parsed.last.bestMs == e.bestMs &&
                  parsed.last.achievedOn.isAfter(e.achievedOn))) {
        throw const FormatException('Invalid leaderboard order');
      }
      parsed.add(e);
    }
    return SwiftBoard(
      List.unmodifiable(parsed),
      me['rank'] as int?,
      me['bestMs'] as int?,
      me['optedIn'] as bool,
    );
  }
}

bool _day(Object? raw) {
  if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    return false;
  }
  final at = DateTime.tryParse('${raw}T00:00:00Z');
  return at != null &&
      at.toIso8601String().substring(0, 10) == raw &&
      at.isAfter(DateTime.utc(1970)) &&
      !at.isAfter(DateTime.now().toUtc());
}

bool _ms(Object? ms) => ms is int && ms >= 300000 && ms <= 5400000;
bool _date(Object? raw) {
  final d = raw is String ? DateTime.tryParse(raw) : null;
  return d != null &&
      d.isUtc &&
      d.isAfter(DateTime.utc(1970)) &&
      !d.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)));
}

final class SwiftConsent {
  const SwiftConsent(this.state);
  final String state;
  bool get optedIn => state == 'opted-in';
  factory SwiftConsent.parse(Map<String, Object?> json) {
    final state = json['state'];
    if (json['schemaVersion'] != 1 ||
        !const ['undecided', 'opted-in', 'withdrawn'].contains(state) ||
        json['optedIn'] != (state == 'opted-in') ||
        (state == 'undecided'
            ? json['decidedAt'] != null
            : !_date(json['decidedAt']))) {
      throw const FormatException('Invalid leaderboard consent');
    }
    return SwiftConsent(state as String);
  }
}

abstract interface class SwiftLeaderboardPort {
  Future<Map<String, Object?>> call(String action, {bool? optIn});
}

final class BridgeSwiftLeaderboard implements SwiftLeaderboardPort {
  BridgeSwiftLeaderboard(this.session, this.account, this.mode);
  final BridgeClientSession session;
  final ValueListenable<AccountProjection> account;
  final ConnectionModeControl? mode;
  @override
  Future<Map<String, Object?>> call(String action, {bool? optIn}) async {
    final scope = achievementReadScope(account.value, mode);
    final generation = account.value.generation;
    bool current() =>
        account.value.isSignedIn &&
        !account.value.hasDisplayHandoff &&
        (mode == null || !mode!.failed && mode!.allowsOnlineTraffic) &&
        achievementReadScope(account.value, mode) == scope &&
        session.activeGeneration == generation;
    if (!current()) throw StateError('Leaderboard account unavailable');
    final command = 'achievements.leaderboard.$action';
    if (!session.hostCapabilities.contains(command)) {
      return {'schemaVersion': 1, 'supported': false};
    }
    final owner = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    if (!current() ||
        owner.payload['state'] != 'signedIn' ||
        owner.accountContext == null ||
        owner.sessionGeneration != generation) {
      throw StateError('Leaderboard account changed');
    }
    final result = await session.request(
      command,
      accountContext: owner.accountContext,
      payload: {'schemaVersion': 1, 'optIn': ?optIn},
    );
    final a = owner.accountContext!, b = result.accountContext;
    if (!current() ||
        result.sessionGeneration != generation ||
        b == null ||
        b.environment != a.environment ||
        b.authority != a.authority ||
        b.subject != a.subject ||
        result.payload['schemaVersion'] != 1) {
      throw StateError('Leaderboard account changed');
    }
    return result.payload;
  }
}

final class SwiftLeaderboardController extends ChangeNotifier {
  SwiftLeaderboardController(this.port, {this.currentGeneration});
  factory SwiftLeaderboardController.connected(
    BridgeClientSession session,
    ValueListenable<AccountProjection> account,
    ConnectionModeControl? mode,
  ) {
    final c = SwiftLeaderboardController(
      BridgeSwiftLeaderboard(session, account, mode),
      currentGeneration: () => account.value.generation,
    );
    var scope = achievementReadScope(account.value, mode);
    void changed() {
      final next = achievementReadScope(account.value, mode);
      if (next == scope) return;
      scope = next;
      c.reset();
    }

    account.addListener(changed);
    mode?.addListener(changed);
    c._detach = () {
      account.removeListener(changed);
      mode?.removeListener(changed);
    };
    return c;
  }
  void watchAchievements(ValueListenable<AchievementCollection> source) {
    void changed() => unawaited(
      checkAward(
        earned:
            source.value.isReady &&
            source.value.generation ==
                (currentGeneration?.call() ?? source.value.generation) &&
            source.value.isEarned('contract-tsg-swift'),
      ),
    );
    source.addListener(changed);
    final previous = _detach;
    _detach = () {
      source.removeListener(changed);
      previous?.call();
    };
    changed();
  }

  VoidCallback? _detach;
  final SwiftLeaderboardPort port;
  final int Function()? currentGeneration;
  SwiftBoard? _board;
  DateTime? _boardExpiresAt;
  SwiftBoard? get board =>
      _boardExpiresAt != null && DateTime.now().isBefore(_boardExpiresAt!)
      ? _board
      : null;
  int? _bestMs;
  int? get bestMs => board?.bestMs ?? _bestMs;
  SwiftConsent? consent;
  bool? supported;
  bool busy = false, failed = false, rateLimited = false, awardPending = false;
  bool writeFailed = false;
  bool _asked = false, _disposed = false;
  int epoch = 0;
  DateTime? _loaded, _retryAt;
  Future<void>? _loading;
  Timer? _boardExpiry, _refresh;
  int _openPages = 0;

  void openPage() {
    _openPages++;
    _refresh ??= Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(load(includeBoard: true));
    });
  }

  void closePage() {
    if (_openPages > 0) _openPages--;
    if (_openPages == 0) {
      _refresh?.cancel();
      _refresh = null;
    }
  }

  void _clearBoard() {
    _boardExpiry?.cancel();
    _boardExpiry = null;
    _board = null;
    _boardExpiresAt = null;
  }

  void reset() {
    epoch++;
    _clearBoard();
    _bestMs = null;
    consent = null;
    supported = null;
    busy = false;
    failed = rateLimited = awardPending = _asked = writeFailed = false;
    _loaded = _retryAt = null;
    _loading = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> load({bool includeBoard = false}) async {
    if (_disposed || busy && _loading == null) return;
    if (_loading != null) {
      await _loading;
      if (includeBoard && supported != false && !failed) {
        await load(includeBoard: true);
      }
      return;
    }
    if (_retryAt != null && DateTime.now().isBefore(_retryAt!)) {
      failed = rateLimited = true;
      notifyListeners();
      return;
    }
    if (!includeBoard &&
        _loaded != null &&
        DateTime.now().difference(_loaded!) < const Duration(seconds: 60)) {
      return;
    }
    final operation = _load(includeBoard);
    _loading = operation;
    await operation;
    if (identical(_loading, operation)) _loading = null;
  }

  Future<void> _load(bool includeBoard) async {
    final version = epoch;
    busy = true;
    failed = rateLimited = writeFailed = false;
    notifyListeners();
    try {
      final c = await port.call('consent.read');
      if (_disposed || epoch != version) return;
      if (c['supported'] == false) {
        supported = false;
        _clearBoard();
        _loaded = DateTime.now();
        return;
      }
      consent = SwiftConsent.parse(c['consent'] as Map<String, Object?>);
      supported = true;
      if (includeBoard) {
        final b = await port.call('read');
        if (_disposed || epoch != version) return;
        if (b['supported'] == false) {
          supported = false;
          _clearBoard();
          return;
        }
        _board = SwiftBoard.parse(b['board'] as Map<String, Object?>);
        _boardExpiresAt = DateTime.now().add(const Duration(seconds: 60));
        _boardExpiry?.cancel();
        _boardExpiry = Timer(const Duration(seconds: 60), () {
          _clearBoard();
          if (!_disposed) notifyListeners();
        });
        _bestMs = board!.bestMs;
      }
      _loaded = DateTime.now();
    } catch (error) {
      if (!_disposed && epoch == version) _error(error);
    } finally {
      if (!_disposed && epoch == version) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void _error(Object error, {bool writing = false}) {
    writeFailed = writing;
    failed = true;
    rateLimited =
        error is BridgeClientException &&
        error.code == 'achievements.leaderboard.rate_limited';
    if (rateLimited) _retryAt = DateTime.now().add(const Duration(seconds: 60));
  }

  Future<bool> choose(bool optIn) async {
    if (_disposed || busy || supported != true) return false;
    final version = epoch;
    var saved = false;
    busy = true;
    failed = rateLimited = writeFailed = false;
    notifyListeners();
    try {
      final result = await port.call('consent.write', optIn: optIn);
      if (_disposed || epoch != version) return false;
      if (result['supported'] == false) {
        supported = false;
        return false;
      }
      final next = SwiftConsent.parse(
        result['consent'] as Map<String, Object?>,
      );
      if (next.optedIn != optIn || next.state == 'undecided') {
        throw const FormatException('Consent not confirmed');
      }
      consent = next;
      _asked = true;
      awardPending = false;
      _loaded = null;
      // Clear the old list immediately, including the withdrawing player's row.
      _clearBoard();
      _retryAt = null;
      saved = true;
      return true;
    } catch (error) {
      if (!_disposed && epoch == version) _error(error, writing: true);
      return false;
    } finally {
      if (!_disposed && epoch == version) {
        busy = false;
        notifyListeners();
        if (saved && _openPages > 0) unawaited(load(includeBoard: true));
      }
    }
  }

  bool claimPrompt() {
    if (_disposed ||
        busy ||
        failed ||
        supported != true ||
        consent?.state != 'undecided' ||
        _asked) {
      return false;
    }
    _asked = true;
    awardPending = false;
    return true;
  }

  Future<void> checkAward({required bool earned}) async {
    if (_disposed || _asked || !earned) return;
    final version = epoch;
    try {
      await load();
      if (!_disposed &&
          epoch == version &&
          !_asked &&
          consent?.state == 'undecided') {
        awardPending = true;
        notifyListeners();
      }
    } catch (_) {
      /* A failed collection read never invents an earned award. */
    }
  }

  @override
  void dispose() {
    _detach?.call();
    _refresh?.cancel();
    _boardExpiry?.cancel();
    _disposed = true;
    epoch++;
    notifyListeners();
    super.dispose();
  }
}
