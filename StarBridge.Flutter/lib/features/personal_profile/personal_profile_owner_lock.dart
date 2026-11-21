import 'dart:async';
import 'dart:convert';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'personal_profile_models.dart';
import 'personal_profile_presentation.dart';

/// Both entry points use the same bridge session. A weak key ties coordination
/// to that session, and observing a different owner or generation retires it.
final class PersonalProfileOwnerLocks {
  static final _sessions = Expando<PersonalProfileOwnerLocks>();

  static PersonalProfileOwnerLocks of(BridgeClientSession session) =>
      _sessions[session] ??= PersonalProfileOwnerLocks();

  final _saves =
      StreamController<(PersonalProfileOwnerLock, Object)>.broadcast();
  Stream<(PersonalProfileOwnerLock, Object)> get saves => _saves.stream;

  void notifySave(PersonalProfileOwnerLock lock, Object source) {
    if (isCurrent(lock)) _saves.add((lock, source));
  }

  PersonalProfileOwnerLock? _lock;

  PersonalProfileOwnerLock forOwner(
    BridgeAccountContext owner,
    int generation,
  ) {
    final current = _lock;
    if (current != null &&
        current.generation == generation &&
        (
              current.owner.environment,
              current.owner.authority,
              current.owner.subject,
            ) ==
            (owner.environment, owner.authority, owner.subject)) {
      return current;
    }
    return _lock = PersonalProfileOwnerLock(owner, generation);
  }

  bool isCurrent(PersonalProfileOwnerLock lock) => identical(_lock, lock);
}

final class PersonalProfileOwnerLock {
  PersonalProfileOwnerLock(this.owner, this.generation);

  final BridgeAccountContext owner;
  final int generation;
  int _stamp = 0;
  PersonalProfileOwnerOperation? _tail;
  (int, String?)? _importVersion;
  final _rejectedTogether = <String, String>{};
  final _deferred = <String, String>{};
  PersonalProfileSnapshot? _confirmation;

  /// A read that overlapped a writer may have captured old local content.
  int? get importStamp => _tail == null ? _stamp : null;

  PersonalProfileOwnerOperation? tryImport(int? observedStamp) =>
      observedStamp != null && observedStamp == importStamp ? _begin() : null;

  PersonalProfileOwnerOperation beginSave() => _begin();

  PersonalProfileOwnerOperation _begin() {
    final previous = _tail?.done;
    _stamp++;
    return _tail = PersonalProfileOwnerOperation(this, previous);
  }

  Map<String, Map<String, Object?>> importEdits(
    PersonalProfilePresentation page,
    Map<String, Map<String, Object?>> edits,
  ) {
    if (_importVersion case (final revision, _) when revision > page.revision) {
      return const {};
    }
    final version = (page.revision, page.sourceVersion);
    if (_importVersion != version) {
      _importVersion = version;
      _rejectedTogether.clear();
      _deferred.clear();
    }
    final candidates = edits.entries.where(
      (entry) => _deferred[entry.key] != jsonEncode(entry.value),
    );
    final changed = Map.fromEntries(
      candidates.where(
        (entry) => _rejectedTogether[entry.key] != jsonEncode(entry.value),
      ),
    );
    if (changed.isNotEmpty || candidates.isEmpty) return changed;
    // A definite batch rejection allows one group to be isolated on a
    // subsequent read. An uncertain write never reaches this branch.
    return Map.fromEntries(candidates.take(1));
  }

  void defer(
    Map<String, Map<String, Object?>> edits, {
    required bool uncertain,
  }) {
    final target = uncertain || edits.length == 1
        ? _deferred
        : _rejectedTogether;
    target.addAll(
      edits.map((group, fields) => MapEntry(group, jsonEncode(fields))),
    );
  }

  void confirm(PersonalProfileSnapshot after) {
    _confirmation = after;
  }

  PersonalProfileSnapshot? confirmationNewerThan(
    PersonalProfilePresentation observed,
  ) {
    final confirmed = _confirmation;
    return confirmed != null &&
            confirmed.presentation!.revision > observed.revision
        ? confirmed
        : null;
  }
}

final class PersonalProfileOwnerOperation {
  PersonalProfileOwnerOperation(this._owner, this.previous);

  final PersonalProfileOwnerLock _owner;
  final Future<void>? previous;
  final _finished = Completer<void>();

  Future<void> get done => _finished.future;

  void finish() {
    if (identical(_owner._tail, this)) _owner._tail = null;
    _finished.complete();
  }
}
