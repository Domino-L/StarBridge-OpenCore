import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../common/user_input_idle_watcher.dart';
import 'community_activity_port.dart';
import 'community_author_projection_port.dart';
import 'community_chat_controller.dart';
import 'community_chat_seen_authors.dart';

/// When the main fleet chat reads, apart from reads a push already triggers.
///
/// Names are confirmed about once a minute while someone is looking, without
/// the channel read; between reads the chat shows what it last saw, up to five
/// minutes (user 2026-10-31). An author not seen yet is read at once by the
/// chat itself, not on this pace. New messages and the unread count come
/// from the push; a slow reconciliation covers a missed event, and a push that
/// is not healthy falls back to the old fast read so nothing arrives later.
/// Names and messages keep separate failure counts: names failing must never
/// hold back the messages' fallback.
final class CommunityChatReadSchedule {
  CommunityChatReadSchedule({
    required this.canRead,
    required this.pushHealthy,
    required this.renewalAvailable,
    required this.userActive,
    required this.read,
    this.renewalPace = renewalInterval,
    bool Function()? catchUpDue,
    DateTime Function()? now,
  }) : _catchUpDue = catchUpDue ?? _never,
       _now = now ?? _elapsed {
    _lastContent = _lastRenewal = _now();
    _arm(_nextDelay());
  }

  static const renewalInterval = Duration(seconds: 60);
  static const _backoffBase = Duration(seconds: 4);
  static const fallbackInterval = Duration(seconds: 3);
  static const idleFallbackInterval = Duration(seconds: 15);
  static const reconcileInterval = Duration(seconds: 30);
  static const maximumBackoff = Duration(seconds: 60);

  /// On screen and the window in front, as the panel judges it.
  final bool Function() canRead;
  final Duration renewalPace;
  final bool Function() pushHealthy, renewalAvailable, userActive;

  /// Null when it did not run. The result says which read really happened.
  final Future<ChatReadResult?> Function({required bool renewal}) read;
  final bool Function() _catchUpDue;
  final DateTime Function() _now;
  static bool _never() => false;

  /// Reads are paced by elapsed time, not the wall clock: setting the clock back
  /// must not delay a read, because last-seen names stay only until one ends.
  static final _stopwatch = Stopwatch()..start();
  static DateTime _elapsed() =>
      DateTime.fromMicrosecondsSinceEpoch(_stopwatch.elapsedMicroseconds);

  Timer? _timer;
  bool _closed = false, _running = false;
  int _contentFailures = 0, _renewalFailures = 0;
  late DateTime _lastContent, _lastRenewal;

  /// A full read succeeded, whoever asked for it: a push, a manual refresh. Any
  /// backoff is over, so a read still owed need not wait for it.
  void noteContentRead() {
    _contentFailures = 0;
    _contentDone();
  }

  /// A full read carries fresh names, so the renewal clock restarts too. Not
  /// while renewals are failing: full reads say nothing about the lighter read,
  /// which must still get its slow retry, or it would never recover.
  void _contentDone() {
    _lastContent = _now();
    if (_renewalFailures == 0) _lastRenewal = _lastContent;
  }

  /// Input came back or the context changed: reconsider right away.
  void poke() {
    if (!_closed && !_running) _arm(Duration.zero);
  }

  Duration _paced(Duration base, int failures) {
    if (failures == 0) return base;
    final scaled =
        _backoffBase * math.pow(2, math.min(failures, 10)).toInt();
    final capped = scaled > maximumBackoff ? maximumBackoff : scaled;
    return capped > base ? capped : base;
  }

  /// Nobody looking with a healthy push: the push alone brings messages.
  DateTime? _nextContent() {
    // Owed now, by anyone looking or not; failures still back it off.
    if (_catchUpDue()) {
      return _lastContent.add(_paced(Duration.zero, _contentFailures));
    }
    final healthy = pushHealthy();
    final gap = userActive()
        ? (healthy ? reconcileInterval : fallbackInterval)
        : (healthy ? null : idleFallbackInterval);
    return gap == null
        ? null
        : _lastContent.add(_paced(gap, _contentFailures));
  }

  /// No names to keep alive for someone who is not there.
  DateTime? _nextRenewal() => userActive() && renewalAvailable()
      ? _lastRenewal.add(_paced(renewalPace, _renewalFailures))
      : null;

  Duration _nextDelay() {
    final now = _now();
    final content = _nextContent(), renewal = _nextRenewal();
    final next = content == null
        ? renewal
        : renewal == null || content.isBefore(renewal)
        ? content
        : renewal;
    if (next == null) return fallbackInterval;
    final wait = next.difference(now);
    if (wait.isNegative) return Duration.zero;
    // Waking costs no read, and a push turning unhealthy is noticed in time.
    return wait > fallbackInterval ? fallbackInterval : wait;
  }

  void _arm(Duration delay) {
    _timer?.cancel();
    if (_closed) return;
    _timer = Timer(delay, _tick);
  }

  Future<void> _tick() async {
    if (_closed || _running) return;
    final now = _now();
    final content = _nextContent(), renewal = _nextRenewal();
    final full = content != null && !content.isAfter(now);
    final names = !full && renewal != null && !renewal.isAfter(now);
    if (!full && !names) return _arm(_nextDelay());
    // Hidden or behind another window: look again without counting an attempt,
    // so coming back reads as soon as a read is due.
    if (!canRead()) return _arm(fallbackInterval);
    _running = true;
    ChatReadResult? result;
    try {
      result = await read(renewal: names);
    } finally {
      _running = false;
    }
    if (_closed) return;
    if (result == null) return _arm(fallbackInterval);
    if (!result.renewal) {
      _contentFailures = result.ok ? 0 : _contentFailures + 1;
      _contentDone();
    }
    // Due as a renewal, whatever read it became: the next one would become the
    // same read, so it keeps this pace too and cannot outrun the backoff.
    if (names) {
      _renewalFailures = result.ok ? 0 : _renewalFailures + 1;
      _lastRenewal = _now();
    }
    _arm(_nextDelay());
  }

  void dispose() {
    _closed = true;
    _timer?.cancel();
  }
}

/// Runs the panel's background reads: the schedule above for the main fleet
/// chat, the plain fixed poll for every other chat.
final class CommunityChatReadDriver {
  CommunityChatReadDriver({
    required Object Function() port,
    required CommunityChatController Function() model,
    required bool Function() canRead,
    required void Function() onInputChanged,
  }) {
    if (port() is! CommunityChatAuthorRenewalPort) {
      _poll = Timer.periodic(const Duration(seconds: 3), (_) {
        final current = model();
        if (canRead() &&
            !current.invalidated &&
            current.error != 'refreshRequired') {
          unawaited(current.refresh(silent: true));
        }
      });
      return;
    }
    _idle = UserInputIdleWatcher(
      onChanged: () {
        onInputChanged();
        _schedule?.poke();
      },
    );
    _seenSweep = Timer.periodic(CommunityChatSeenAuthors.sweepEvery, (_) {
      if (model().seenAuthors.sweep()) onInputChanged();
    });
    _schedule = CommunityChatReadSchedule(
      canRead: canRead,
      pushHealthy: () {
        final source = port();
        if (source is! CommunityActivityPort || !source.activityHealthy) {
          return false;
        }
        // Names on, but a Host without the lighter read: keep the old pace.
        final authors = port();
        return model().renewalSupported ||
            authors is! CommunityAuthorProjectionPort ||
            !authors.authorIdentitiesAvailable;
      },
      renewalAvailable: () => model().authorRenewalAvailable,
      catchUpDue: () => model().catchUp.due,
      userActive: () => userActive,
      read: ({required renewal}) async {
        final current = model();
        if (current.invalidated || current.error == 'refreshRequired') {
          return null;
        }
        return current.refresh(silent: true, renewal: renewal);
      },
    );
  }

  Timer? _poll, _seenSweep;
  UserInputIdleWatcher? _idle;
  CommunityChatReadSchedule? _schedule;
  bool get userActive => _idle?.active ?? true;

  /// The window is in front. Being idle is a separate question: a pushed
  /// message still arrives while nobody touches the client.
  bool get inFront {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// What the chat treats as "someone reading in front": it decides names and
  /// read receipts, while [inFront] alone decides whether reads may run.
  bool get readingInFront => inFront && userActive;

  void syncContext(CommunityChatController current, {required bool visible}) {
    current
      ..catchUp.onDue = _schedule?.poke
      ..catchUp.onFullRead = _schedule?.noteContentRead
      ..setReadingContext(visible: visible, foreground: readingInFront);
  }

  Future<void> pushedRead(CommunityChatController current) async {
    await current.refresh(silent: true);
  }

  void dispose() {
    _poll?.cancel();
    _seenSweep?.cancel();
    _idle?.dispose();
    _schedule?.dispose();
  }
}
