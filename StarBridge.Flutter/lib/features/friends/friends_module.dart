import 'dart:async';

import 'package:flutter/foundation.dart';

enum FriendsSection { friends, incoming, outgoing, blocked }

enum FriendsReadState { idle, loading, ready, signedOut, unavailable }

List<String> friendActionsFor(String relation) => switch (relation) {
  'none' => const ['send', 'block'],
  'friend' => const ['remove', 'block'],
  'incoming' => const ['accept', 'reject', 'block'],
  'outgoing' => const ['cancel', 'block'],
  'blocked' => const ['unblock'],
  _ => const [],
};

final class FriendRow {
  const FriendRow(
    this.callsign,
    this.gameId,
    this.relationship,
    this.updatedAt, {
    this.avatar,
    this.targetRef,
    this.chatTargetRef,
    this.conversationKey,
    this.actions = const [],
    this.shared = const {},
  });
  final String callsign, gameId, relationship;
  final DateTime updatedAt;
  final String? avatar;
  final String? targetRef;
  final String? chatTargetRef;
  final String? conversationKey;
  final List<String> actions;
  final Map<String, Object?> shared;
  String get name => callsign.isEmpty
      ? gameId
      : gameId.isEmpty
      ? callsign
      : '$callsign ($gameId)';
}

final class FriendsSnapshot {
  FriendsSnapshot({
    required Map<FriendsSection, List<FriendRow>> groups,
    required List<FriendRow> results,
    this.query,
    this.refreshedAt,
  }) : groups = Map.unmodifiable(
         groups.map(
           (key, value) => MapEntry(key, List<FriendRow>.unmodifiable(value)),
         ),
       ),
       results = List.unmodifiable(results);
  final Map<FriendsSection, List<FriendRow>> groups;
  final List<FriendRow> results;
  final String? query;
  final DateTime? refreshedAt;
}

final class FriendsReadResult {
  const FriendsReadResult(
    this.state, {
    this.snapshot,
    this.failure = 'unavailable',
  });
  final FriendsReadState state;
  final FriendsSnapshot? snapshot;
  final String failure;
}

abstract interface class FriendsPort {
  Stream<void> get invalidations;
  Future<FriendsReadResult> read({String? query});
  void cancelPending();
  Future<void> close();
}

final class FriendCommandResult {
  const FriendCommandResult(this.status, {this.error, this.directory});
  final String status;
  final String? error;
  final FriendsSnapshot? directory;
}

abstract interface class FriendsCommandPort {
  bool get commandsAvailable;
  Future<FriendCommandResult> execute(String action, String targetRef);
}

final class UnavailableFriendsPort implements FriendsPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<FriendsReadResult> read({String? query}) async =>
      const FriendsReadResult(
        FriendsReadState.unavailable,
        failure: 'hostUnavailable',
      );
  @override
  void cancelPending() {}
  @override
  Future<void> close() async {}
}

/// The composition may retain this bounded snapshot between page visits.
/// Typing, account invalidation and disposal retire older results.
final class FriendsModule extends ChangeNotifier {
  FriendsModule(this._port, {DateTime Function()? now, this.isExample = false})
    : _now = now ?? DateTime.now {
    _subscription = _port.invalidations.listen((_) {
      if (_disposed) return;
      _epoch++;
      _port.cancelPending();
      snapshot = null;
      _lastSuccessfulRead = null;
      query = '';
      section = FriendsSection.friends;
      accountRevision++;
      busy = false;
      feedback = null;
      state = FriendsReadState.idle;
      notifyListeners();
      if (_started) unawaited(refresh());
    });
  }
  final FriendsPort _port;
  final bool isExample;
  bool _started = false;
  final DateTime Function() _now;
  DateTime? _lastSuccessfulRead;
  late final StreamSubscription<void> _subscription;
  bool _disposed = false;
  int _epoch = 0;
  int? _readingEpoch;
  int accountRevision = 0;
  bool busy = false;
  String? feedback;
  bool feedbackSuccess = false;
  FriendsSection section = FriendsSection.friends;
  FriendsReadState state = FriendsReadState.idle;
  FriendsSnapshot? snapshot;
  String query = '', failure = 'unavailable';
  bool get searching => query.trim().isNotEmpty;
  bool get validQuery =>
      query.trim().length >= 2 &&
      query.trim().length <= 128 &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(query);
  List<FriendRow> get rows => searching
      ? snapshot?.results ?? const []
      : snapshot?.groups[section] ?? const [];
  void select(FriendsSection value) {
    if (busy || _disposed) return;
    section = value;
    if (searching) {
      query = '';
      unawaited(refresh());
    } else {
      notifyListeners();
    }
  }

  void editQuery(String value) {
    if (busy || _disposed) return;
    _epoch++;
    _port.cancelPending();
    query = value;
    snapshot = null;
    _lastSuccessfulRead = null;
    state = FriendsReadState.idle;
    notifyListeners();
    if (!searching) unawaited(refresh());
  }

  Future<void> enter() async {
    // Returning to an unsubmitted search must not silently submit it.
    if (searching && state == FriendsReadState.idle) return;
    await refresh(silent: snapshot != null, reuseFresh: true);
  }

  Future<void> prefetch() async {
    // Hovering must not submit a search or replace a user's current results.
    if (searching) return;
    await refresh(silent: true, reuseFresh: true);
  }

  Future<void> refresh({bool silent = false, bool reuseFresh = false}) async {
    if (_disposed || busy || (searching && !validQuery)) return;
    _started = true;
    final age = _lastSuccessfulRead == null
        ? null
        : _now().difference(_lastSuccessfulRead!);
    if (reuseFresh &&
        state == FriendsReadState.ready &&
        snapshot != null &&
        snapshot!.query == (searching ? query.trim() : null) &&
        age != null &&
        !age.isNegative &&
        age < const Duration(seconds: 10)) {
      return;
    }
    // Periodic refresh must not retire a slow but still-current request.
    if ((silent || reuseFresh) && _readingEpoch == _epoch) return;
    final epoch = ++_epoch;
    _readingEpoch = epoch;
    final search = searching ? query.trim() : null;
    _port.cancelPending();
    if (!silent) {
      state = FriendsReadState.loading;
      snapshot = null;
    }
    notifyListeners();
    FriendsReadResult result;
    try {
      result = await _port.read(query: search);
    } catch (_) {
      result = const FriendsReadResult(FriendsReadState.unavailable);
    } finally {
      if (_readingEpoch == epoch) _readingEpoch = null;
    }
    if (_disposed || epoch != _epoch) return;
    _lastSuccessfulRead = null;
    if (result.state == FriendsReadState.ready &&
        (result.snapshot == null || result.snapshot!.query != search)) {
      state = FriendsReadState.unavailable;
      failure = 'invalidResponse';
      snapshot = null;
    } else {
      state = result.state;
      failure = result.failure;
      snapshot = result.state == FriendsReadState.ready
          ? result.snapshot
          : null;
      if (state == FriendsReadState.ready) feedback = null;
      if (state == FriendsReadState.ready) _lastSuccessfulRead = _now();
    }
    notifyListeners();
  }

  bool get commandsAvailable =>
      _port is FriendsCommandPort &&
      (_port as FriendsCommandPort).commandsAvailable;
  bool canExecute(FriendRow row, String action) =>
      !_disposed &&
      !busy &&
      commandsAvailable &&
      state == FriendsReadState.ready &&
      rows.contains(row) &&
      row.targetRef != null &&
      row.actions.contains(action);

  Future<void> execute(FriendRow row, String action) async {
    if (!canExecute(row, action)) return;
    final epoch = ++_epoch;
    _lastSuccessfulRead = null;
    busy = true;
    feedback = null;
    notifyListeners();
    FriendCommandResult result;
    try {
      result = await (_port as FriendsCommandPort).execute(
        action,
        row.targetRef!,
      );
    } catch (_) {
      result = const FriendCommandResult('unknown', error: 'outcomeUnknown');
    }
    if (_disposed || epoch != _epoch) return;
    busy = false;
    feedbackSuccess =
        result.status == 'accepted' &&
        result.directory != null &&
        result.directory!.query == null;
    if (feedbackSuccess) {
      snapshot = result.directory;
      query = '';
      section = switch (action) {
        'send' || 'cancel' => FriendsSection.outgoing,
        'accept' => FriendsSection.friends,
        'reject' => FriendsSection.incoming,
        'block' || 'unblock' => FriendsSection.blocked,
        _ => section,
      };
      state = FriendsReadState.ready;
      feedback = 'success.$action';
    } else {
      snapshot = null;
      state = FriendsReadState.unavailable;
      failure = 'refreshRequired';
      feedback = result.status == 'accepted'
          ? 'outcomeUnknown'
          : result.error ?? 'outcomeUnknown';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _port.cancelPending();
    unawaited(_subscription.cancel());
    unawaited(_port.close());
    super.dispose();
  }
}
