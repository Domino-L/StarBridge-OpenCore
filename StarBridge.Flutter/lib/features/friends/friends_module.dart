import 'dart:async';

import 'package:flutter/foundation.dart';

import '../direct_messages/direct_messages_module.dart';

enum FriendsSection { friends, incoming, outgoing, blocked }

enum FriendsReadState { idle, loading, ready, signedOut, unavailable }

String? friendSharedConversationPresence(FriendRow row) =>
    row.relationship == 'friend'
    ? switch (row.shared['presence']) {
        'AppOnline' => 'online',
        'InGame' => 'inGame',
        'Away' => 'away',
        'Offline' => 'offline',
        _ => null,
      }
    : null;

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
    this.sharedLabels = const {},
  });
  final String callsign, gameId, relationship;
  final DateTime updatedAt;
  final String? avatar;
  final String? targetRef;
  final String? chatTargetRef;
  final String? conversationKey;
  final List<String> actions;
  final Map<String, Object?> shared;
  final Map<String, Map<String, String>> sharedLabels;
  String get name => callsign.isEmpty
      ? gameId
      : gameId.isEmpty
      ? callsign
      : '$callsign ($gameId)';

  /// Relay cannot deliver a request to this search result: it stays readable,
  /// with no command offered.
  bool get notAddableHere =>
      relationship == 'none' && targetRef != null && !actions.contains('send');
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
    this.transientFailure = false,
  });
  final FriendsReadState state;
  final FriendsSnapshot? snapshot;
  final String failure;
  final bool transientFailure;
}

abstract interface class FriendsPort {
  Stream<void> get invalidations;
  Future<FriendsReadResult> read({String? query});
  void cancelPending();
  Future<void> close();
}

abstract interface class FriendsActivityPort {
  Stream<void> get changes;
}

final class FriendsCachedDisplay {
  const FriendsCachedDisplay(this.snapshot, this.cachedAtUtc);
  final FriendsSnapshot snapshot;
  final DateTime cachedAtUtc;
}

abstract interface class FriendsCachedDisplayPort {
  Stream<FriendsCachedDisplay?> get cachedDisplays;
}

final class FriendCommandResult {
  const FriendCommandResult(
    this.status, {
    this.error,
    this.directory,
    this.directoryUnavailable = false,
  });
  final String status;
  final String? error;
  final FriendsSnapshot? directory;
  final bool directoryUnavailable;
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
  DirectMessagesModule? _chat;
  Conversation? requestedConversation;
  void requestConversation(Conversation conversation) {
    if (_disposed) return;
    requestedConversation = conversation;
    notifyListeners();
  }

  final incomingAttention = ValueNotifier<int>(0);
  @override
  void notifyListeners() {
    if (state == FriendsReadState.ready &&
        !displayOnly &&
        !refreshFailed &&
        snapshot?.query == null &&
        snapshot != null) {
      incomingAttention.value =
          snapshot!.groups[FriendsSection.incoming]?.length ?? 0;
    } else if (state == FriendsReadState.signedOut ||
        failure == 'forbidden' && !searching ||
        failure == 'identityUnavailable' ||
        failure == 'notAllowed') {
      incomingAttention.value = 0;
    }
    super.notifyListeners();
  }

  String? Function()? detachedVisibleConversation;
  String? get visibleConversationKey =>
      detachedVisibleConversation?.call() ??
      (_chat?.isViewportCurrent?.call() == true
          ? _chat?.selected?.conversationKey
          : null);
  DirectMessagesModule chat(DirectMessagesPort Function() create) =>
      _chat ??= DirectMessagesModule(create());
  FriendsModule(this._port, {DateTime Function()? now, this.isExample = false})
    : _now = now ?? DateTime.now {
    _subscription = _port.invalidations.listen((_) {
      if (_disposed) return;
      _epoch++;
      _port.cancelPending();
      snapshot = null;
      displayOnly = false;
      _lastSuccessfulRead = null;
      _readTask = null;
      _readingEpoch = null;
      refreshFailed = false;
      _resetViewport();
      query = '';
      section = FriendsSection.friends;
      accountRevision++;
      incomingAttention.value = 0;
      requestedConversation = null;
      busy = false;
      feedback = null;
      state = FriendsReadState.idle;
      notifyListeners();
      if (_started) unawaited(refresh());
    });
    if (_port is FriendsActivityPort) {
      _contentSubscription = changes.listen((_) {
        if (_disposed) return;
        _contentRevision++;
        _stale = true;
      });
    }
    if (_port is FriendsCachedDisplayPort) {
      _cachedSubscription = (_port as FriendsCachedDisplayPort).cachedDisplays
          .listen((cached) {
            if (_disposed || !_started || searching) return;
            if (cached == null) {
              if (!displayOnly) return;
              snapshot = null;
              displayOnly = false;
              _lastSuccessfulRead = null;
              state = reading
                  ? FriendsReadState.loading
                  : FriendsReadState.unavailable;
              incomingAttention.value = 0;
              notifyListeners();
            } else if (reading && (snapshot == null || displayOnly)) {
              snapshot = _displayOnly(cached.snapshot, keepConversation: false);
              displayOnly = true;
              _lastSuccessfulRead = cached.cachedAtUtc;
              state = FriendsReadState.ready;
              incomingAttention.value = 0;
              notifyListeners();
            }
          });
    }
  }
  final FriendsPort _port;
  Stream<void> get changes => _port is FriendsActivityPort
      ? (_port as FriendsActivityPort).changes
      : const Stream.empty();
  final bool isExample;
  bool _started = false;
  final DateTime Function() _now;
  DateTime? _lastSuccessfulRead;
  late final StreamSubscription<void> _subscription;
  StreamSubscription<void>? _contentSubscription;
  StreamSubscription<FriendsCachedDisplay?>? _cachedSubscription;
  int _contentRevision = 0;
  bool _stale = true;
  bool _disposed = false;
  int _epoch = 0;
  int? _readingEpoch;
  Future<void>? _readTask;
  bool refreshFailed = false;
  bool displayOnly = false;
  double _scrollOffset = 0;
  int _viewEpoch = 0;
  double get scrollOffset => _scrollOffset;
  int get viewEpoch => _viewEpoch;
  void rememberScroll(double offset, {required int expectedEpoch}) {
    if (!_disposed &&
        expectedEpoch == _viewEpoch &&
        offset.isFinite &&
        offset >= 0) {
      _scrollOffset = offset;
    }
  }

  void _resetViewport() {
    _scrollOffset = 0;
    _viewEpoch++;
  }

  DateTime? get lastSuccessfulReadUtc => _lastSuccessfulRead?.toUtc();
  int accountRevision = 0;
  bool busy = false;
  String? feedback;
  bool feedbackSuccess = false;
  FriendsSection section = FriendsSection.friends;
  FriendsReadState state = FriendsReadState.idle;
  FriendsSnapshot? snapshot;
  String query = '', failure = 'unavailable';
  bool get searching => query.trim().isNotEmpty;
  bool get reading => _readingEpoch != null;
  bool get validQuery =>
      query.trim().length >= 2 &&
      query.trim().length <= 128 &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(query);
  List<FriendRow> get rows => searching
      ? [...matchedFriends, ...?snapshot?.results]
      : snapshot?.groups[section] ?? const [];
  List<FriendRow> get matchedFriends => searching
      ? snapshot?.groups[FriendsSection.friends] ?? const []
      : const [];
  void select(FriendsSection value) {
    if (busy || _disposed) return;
    if (section != value || searching) _resetViewport();
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
    _resetViewport();
    _epoch++;
    _port.cancelPending();
    query = value;
    snapshot = null;
    displayOnly = false;
    _lastSuccessfulRead = null;
    _readingEpoch = null;
    _readTask = null;
    refreshFailed = false;
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

  Future<void> refresh({bool silent = false, bool reuseFresh = false}) {
    if (_disposed || busy || (searching && !validQuery)) return Future.value();
    _started = true;
    if (_readingEpoch == _epoch && _readTask != null) {
      return silent || reuseFresh ? Future.value() : _readTask!;
    }
    final age = _lastSuccessfulRead == null
        ? null
        : _now().difference(_lastSuccessfulRead!);
    if (reuseFresh &&
        !_stale &&
        !refreshFailed &&
        !displayOnly &&
        state == FriendsReadState.ready &&
        snapshot != null &&
        snapshot!.query == (searching ? query.trim() : null) &&
        age != null &&
        !age.isNegative &&
        age < const Duration(seconds: 10)) {
      return Future.value();
    }
    final epoch = ++_epoch;
    _readingEpoch = epoch;
    final search = searching ? query.trim() : null;
    _port.cancelPending();
    final previous = snapshot?.query == search ? snapshot : null;
    refreshFailed = false;
    if (previous == null) {
      state = FriendsReadState.loading;
      snapshot = null;
    }
    // Retain same-query rows during both explicit and background refreshes.
    // The separate reading flag disables commands while their references renew.
    final task = _read(epoch, search, previous, _contentRevision);
    _readTask = task;
    unawaited(
      task.whenComplete(() {
        if (identical(_readTask, task)) _readTask = null;
      }),
    );
    return task;
  }

  Future<void> _read(
    int epoch,
    String? search,
    FriendsSnapshot? previous,
    int contentRevision,
  ) async {
    notifyListeners();
    FriendsReadResult result;
    try {
      result = await _port.read(query: search);
    } on TimeoutException {
      result = const FriendsReadResult(
        FriendsReadState.unavailable,
        transientFailure: true,
      );
    } catch (_) {
      result = const FriendsReadResult(FriendsReadState.unavailable);
    } finally {
      if (_readingEpoch == epoch) _readingEpoch = null;
    }
    if (_disposed || epoch != _epoch) return;
    final retained =
        previous ??
        (displayOnly && snapshot?.query == search ? snapshot : null);
    if (result.state == FriendsReadState.unavailable &&
        result.transientFailure &&
        retained != null) {
      state = FriendsReadState.ready;
      snapshot = _displayOnly(retained, keepConversation: !displayOnly);
      refreshFailed = true;
      failure = result.failure;
      notifyListeners();
      return;
    }
    _lastSuccessfulRead = null;
    displayOnly = false;
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
      if (state == FriendsReadState.ready) {
        _lastSuccessfulRead = _now();
        _stale = contentRevision != _contentRevision;
      }
    }
    notifyListeners();
  }

  bool get commandsAvailable =>
      _port is FriendsCommandPort &&
      (_port as FriendsCommandPort).commandsAvailable;
  bool canExecute(FriendRow row, String action) =>
      !_disposed &&
      !busy &&
      !reading &&
      !refreshFailed &&
      !displayOnly &&
      commandsAvailable &&
      state == FriendsReadState.ready &&
      rows.contains(row) &&
      row.targetRef != null &&
      row.actions.contains(action);

  Future<void> execute(FriendRow row, String action) async {
    if (!canExecute(row, action)) return;
    final epoch = ++_epoch;
    final previous = snapshot;
    final previousReadAt = _lastSuccessfulRead;
    final contentRevision = _contentRevision;
    _lastSuccessfulRead = null;
    _stale = true;
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
    if (result.status == 'cancelled') {
      snapshot = null;
      incomingAttention.value = 0;
      displayOnly = false;
      _lastSuccessfulRead = null;
      state = FriendsReadState.idle;
      refreshFailed = false;
      feedback = null;
      feedbackSuccess = false;
      notifyListeners();
      return;
    }
    final completeDirectory =
        result.directory != null &&
        result.directory!.query == null &&
        !result.directoryUnavailable;
    feedbackSuccess =
        result.status == 'accepted' &&
        (completeDirectory ||
            result.directoryUnavailable && result.directory == null);
    if (feedbackSuccess && completeDirectory) {
      snapshot = result.directory;
      final wasSearching = searching;
      final previousSection = section;
      query = '';
      section = switch (action) {
        'send' || 'cancel' => FriendsSection.outgoing,
        'accept' => FriendsSection.friends,
        'reject' => FriendsSection.incoming,
        'block' || 'unblock' => FriendsSection.blocked,
        _ => section,
      };
      if (wasSearching || previousSection != section) _resetViewport();
      state = FriendsReadState.ready;
      refreshFailed = false;
      _lastSuccessfulRead = _now();
      _stale = contentRevision != _contentRevision;
      feedback = 'success.$action';
    } else if (feedbackSuccess) {
      // The operation succeeded; only the new directory is unavailable.
      // Preserve presentation, never old command/chat authorization references.
      snapshot = previous == null
          ? null
          : _displayOnly(previous, keepConversation: false);
      incomingAttention.value = 0;
      _lastSuccessfulRead = previousReadAt;
      state = snapshot == null
          ? FriendsReadState.unavailable
          : FriendsReadState.ready;
      refreshFailed = true;
      failure = 'refreshRequired';
      feedback = 'success.$action';
    } else if (result.status == 'rejected' &&
        const {
          'busy',
          'rateLimited',
          'cooldown',
          'tooManyPending',
          'rejected',
        }.contains(result.error) &&
        previous != null) {
      // A definite no-write response keeps presentation, never spent targets.
      snapshot = _displayOnly(previous, keepConversation: false);
      _lastSuccessfulRead = previousReadAt;
      state = FriendsReadState.ready;
      refreshFailed = true;
      failure = 'refreshRequired';
      feedback = result.error;
    } else {
      snapshot = null;
      incomingAttention.value = 0;
      state = FriendsReadState.unavailable;
      failure = 'refreshRequired';
      feedback = result.status == 'accepted'
          ? 'outcomeUnknown'
          : result.error ?? 'outcomeUnknown';
    }
    notifyListeners();
  }

  FriendsSnapshot _displayOnly(
    FriendsSnapshot previous, {
    bool keepConversation = true,
  }) {
    FriendRow row(FriendRow value) => FriendRow(
      value.callsign,
      value.gameId,
      value.relationship,
      value.updatedAt,
      avatar: value.avatar,
      conversationKey: keepConversation ? value.conversationKey : null,
    );
    return FriendsSnapshot(
      groups: {
        for (final entry in previous.groups.entries)
          entry.key: entry.value.map(row).toList(),
      },
      results: previous.results.map(row).toList(),
      query: previous.query,
      refreshedAt: previous.refreshedAt,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    incomingAttention.dispose();
    _chat?.dispose();
    _epoch++;
    _port.cancelPending();
    unawaited(_subscription.cancel());
    unawaited(_contentSubscription?.cancel());
    unawaited(_cachedSubscription?.cancel());
    unawaited(_port.close());
    super.dispose();
  }
}
