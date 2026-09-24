import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

final class AccountSafetyRecord {
  const AccountSafetyRecord({
    required this.id,
    required this.type,
    required this.text,
    required this.createdAt,
    this.status,
    this.outcome,
    this.expiresAt,
    this.sanctionId,
  });
  final String id, type, text;
  final DateTime createdAt;
  final String? status, outcome;
  final String? sanctionId;
  final DateTime? expiresAt;
}

final class AccountSafetySnapshot {
  const AccountSafetySnapshot(
    this.sanctions,
    this.appeals,
    this.restrictions,
    this.updatedAt,
  );
  final List<AccountSafetyRecord> sanctions, appeals;
  final List<String> restrictions;
  final DateTime updatedAt;

  factory AccountSafetySnapshot.parse(Map<String, Object?> body) {
    if (body['schemaVersion'] != 1) throw const FormatException();
    String text(Map<String, Object?> map, String key, [int max = 4000]) {
      final value = map[key];
      if (value is! String || value.length > max) throw const FormatException();
      return value;
    }

    DateTime date(Map<String, Object?> map, String key) {
      final value = DateTime.tryParse(text(map, key, 64));
      if (value == null) throw const FormatException();
      return value;
    }

    List<AccountSafetyRecord> records(String key, bool appeal) {
      final value = body[key];
      if (value is! List || value.length > 2000) throw const FormatException();
      final ids = <String>{};
      return List.unmodifiable(
        value.map((entry) {
          if (entry is! Map<String, Object?>) throw const FormatException();
          final id = text(entry, appeal ? 'appealId' : 'sanctionId', 256);
          if (id.isEmpty || !ids.add(id)) throw const FormatException();
          return AccountSafetyRecord(
            id: id,
            sanctionId: appeal ? text(entry, 'sanctionId', 256) : id,
            type: text(entry, appeal ? 'sanctionType' : 'type', 128),
            text: text(entry, appeal ? 'details' : 'summary'),
            createdAt: date(entry, appeal ? 'createdAt' : 'issuedAt'),
            status: appeal ? text(entry, 'status', 128) : null,
            outcome: entry['outcomeSummary'] == null
                ? null
                : text(entry, 'outcomeSummary'),
            expiresAt: entry['expiresAt'] == null
                ? null
                : date(entry, 'expiresAt'),
          );
        }),
      );
    }

    final restrictions = body['restrictions'];
    if (restrictions is! List ||
        restrictions.length > 32 ||
        restrictions.any((value) => value is! String || value.length > 128)) {
      throw const FormatException();
    }
    return AccountSafetySnapshot(
      records('sanctions', false),
      records('appeals', true),
      List.unmodifiable(restrictions.cast<String>()),
      date(body, 'updatedAt'),
    );
  }
}

enum AccountSafetyFailure {
  signedOut,
  forbidden,
  unavailable,
  invalid,
  connection,
}

final class AccountSafetyException implements Exception {
  const AccountSafetyException(this.failure);
  final AccountSafetyFailure failure;
}

abstract interface class AccountSafetyPort {
  Stream<void> get invalidations;
  Future<AccountSafetySnapshot> read();
  bool get canSubmit;
  Future<AccountAppealOutcome> submit(
    String sanctionId,
    String details,
    String requestId,
  );
  void dispose();
}

enum AccountAppealOutcome {
  submitted,
  alreadySubmitted,
  rejected,
  unknown,
  sessionChanged,
}

/// Lifetime is the visible account-safety dialog, never an independent login.
final class AccountSafetyController extends ChangeNotifier {
  AccountSafetyController(
    this._port, {
    Duration refreshInterval = const Duration(seconds: 30),
  }) {
    _subscription = _port.invalidations.listen((_) {
      identityRevision++;
      appealOutcomes.clear();
      submitting = false;
      _epoch++;
      snapshot = null;
      busy = false;
      failure = null;
      unawaited(refresh());
    });
    _timer = Timer.periodic(refreshInterval, (_) => unawaited(refresh()));
    unawaited(refresh());
  }
  final AccountSafetyPort _port;
  int identityRevision = 0;
  bool submitting = false;
  final appealOutcomes = <String, AccountAppealOutcome>{};
  bool canAppeal(String id) =>
      _port.canSubmit &&
      !submitting &&
      !busy &&
      failure == null &&
      snapshot?.sanctions.any((s) => s.id == id) == true &&
      snapshot?.appeals.any((a) => a.sanctionId == id) == false &&
      (appealOutcomes[id] == null ||
          appealOutcomes[id] == AccountAppealOutcome.rejected);

  Future<void> submit(String id, String details, int expectedIdentity) async {
    if (_closed ||
        expectedIdentity != identityRevision ||
        !canAppeal(id) ||
        details.trim().isEmpty ||
        details.trim().length > 2000) {
      return;
    }
    submitting = true;
    notifyListeners();
    final requestId = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    AccountAppealOutcome outcome;
    try {
      outcome = await _port.submit(id, details.trim(), requestId);
    } catch (_) {
      outcome = AccountAppealOutcome.unknown;
    }
    if (_closed || expectedIdentity != identityRevision) return;
    submitting = false;
    appealOutcomes[id] = outcome;
    notifyListeners();
    await refresh();
  }

  late final StreamSubscription<void> _subscription;
  late final Timer _timer;
  AccountSafetySnapshot? snapshot;
  AccountSafetyFailure? failure;
  bool busy = false, _closed = false;
  int _epoch = 0;

  Future<void> refresh() async {
    if (_closed || busy || submitting) return;
    final epoch = ++_epoch;
    busy = true;
    notifyListeners();
    try {
      final result = await _port.read();
      if (_closed || epoch != _epoch) return;
      snapshot = result;
      failure = null;
    } catch (error) {
      if (_closed || epoch != _epoch) return;
      failure = error is AccountSafetyException
          ? error.failure
          : AccountSafetyFailure.connection;
      if (failure == AccountSafetyFailure.signedOut ||
          failure == AccountSafetyFailure.forbidden) {
        snapshot = null;
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
    _port.dispose();
    super.dispose();
  }
}
