import 'package:flutter/foundation.dart';

import 'community_author_projection.dart';
import 'community_chat_port.dart';

/// Names and avatars this viewer already saw in this chat. In memory only, one
/// per chat model, so never across viewers.
///
/// A former name/held avatar ends at the original proof's validUntil + 10s.
/// Neither reads of the same proof nor presentation renew that deadline.
final class CommunityChatSeenAuthors extends ChangeNotifier {
  CommunityChatSeenAuthors({
    Duration Function()? elapsed,
    DateTime Function()? now,
  }) : _elapsed = elapsed ?? _clock,
       _now = now ?? DateTime.now;

  static final _stopwatch = Stopwatch()..start();
  static Duration _clock() => _stopwatch.elapsed;
  static const _maximum = 500;

  final Duration Function() _elapsed;
  final DateTime Function() _now;
  DateTime? _timeFloor;
  Duration? _timeElapsed;
  DateTime _time([DateTime? raw]) {
    var at = (raw ?? _now()).toUtc();
    final elapsed = _elapsed();
    if (_timeFloor != null) {
      final passed = elapsed - _timeElapsed!;
      final floor = _timeFloor!.add(passed.isNegative ? Duration.zero : passed);
      if (floor.isAfter(at)) at = floor;
    }
    _timeElapsed = elapsed;
    return _timeFloor = at;
  }

  final _people =
      <String, ({CommunityAuthorProjection identity, Duration until})>{};
  final _avatars = <String, ({String version, Uint8List bytes})>{};
  // Bounded observation fences survive expiry and successful newer answers.
  // Avatar-only narrowing must not withdraw the author's name.
  final _avatarWithdrawn = <String, DateTime>{};
  // Hidden fences both request dispatch and the answer's own observation time.
  final _retired = <String, DateTime>{};
  final _hiddenGeneration = <String, int>{};
  int _generation = 0, _requestFloor = 0;
  int get readGeneration => _generation;
  bool _withdrawn = false;

  List<CommunityChatMessage> admitAnswers(
    List<CommunityChatMessage> messages,
    int requestGeneration,
  ) => messages.map((message) {
    final identity = message.authorIdentity;
    final hidden = _hiddenGeneration[message.senderRef] ?? 0;
    final retired = _retired[message.senderRef];
    return identity?.visible == true &&
            (requestGeneration < _requestFloor ||
                requestGeneration < hidden ||
                retired != null && !identity!.observedAt!.isAfter(retired))
        ? CommunityChatMessage.neutralAuthor(message)
        : message;
  }).toList();

  void hide(String sender) {
    forget(sender);
    final at = _time(), retired = _retired[sender];
    if (_retired.length >= _maximum && retired == null) {
      _retired.remove(_retired.keys.first);
    }
    _retired[sender] = retired != null && retired.isAfter(at) ? retired : at;
    if (_hiddenGeneration.length >= _maximum &&
        !_hiddenGeneration.containsKey(sender)) {
      _hiddenGeneration.clear();
      _requestFloor = ++_generation;
    }
    _hiddenGeneration[sender] = ++_generation;
  }

  bool canNarrowAvatar(String sender, CommunityAuthorProjection observed) {
    if (!observed.admit(_time()).visible || observed.hasAvatar) return false;
    final retired = _retired[sender], latest = _people[sender]?.identity;
    final withdrawn = _avatarWithdrawn[sender];
    return (retired == null || observed.observedAt!.isAfter(retired)) &&
        (withdrawn == null || !observed.observedAt!.isBefore(withdrawn)) &&
        (latest == null || !observed.observedAt!.isBefore(latest.observedAt!));
  }

  /// Drops whoever passed the limit. True when something shown must redraw.
  bool sweep({DateTime? at}) {
    final now = _time(at), elapsed = _elapsed();
    _people.keys
        .where((sender) => !_current(_people[sender]!, now, elapsed))
        .toList()
        .forEach(forget);
    final withdrawn = _withdrawn;
    _withdrawn = false;
    return withdrawn;
  }

  static DateTime deadline(CommunityAuthorProjection identity) =>
      identity.validUntil!.add(CommunityAuthorProjection.clockGrace);

  bool _current(
    ({CommunityAuthorProjection identity, Duration until}) held,
    DateTime now,
    Duration elapsed,
  ) => elapsed < held.until && now.isBefore(deadline(held.identity));

  Duration? get nextRetirement {
    Duration? earliest;
    final now = _time(), elapsed = _elapsed();
    for (final held in _people.values) {
      final wall = deadline(held.identity).difference(now);
      final monotonic = held.until - elapsed;
      final left = wall < monotonic ? wall : monotonic;
      final delay = left.isNegative ? Duration.zero : left;
      if (earliest == null || delay < earliest) earliest = delay;
    }
    return earliest;
  }

  /// The last confirmed answer for [sender], while it may still be shown.
  CommunityAuthorProjection? _seen(String sender, {DateTime? at}) {
    final held = _people[sender];
    if (held == null) return null;
    if (_current(held, _time(at), _elapsed())) return held.identity;
    forget(sender);
    return null;
  }

  /// The avatar kept for [sender]; with [version], only that exact avatar.
  Uint8List? avatarOf(String sender, {String? version}) {
    final identity = _seen(sender);
    if (identity == null || _avatarIsWithdrawn(sender, identity)) {
      return null;
    }
    final held = _avatars[sender];
    return held == null || version != null && held.version != version
        ? null
        : held.bytes;
  }

  /// Grace only holds existing bytes; it never authorizes another avatar read.
  CommunityAuthorProjection? avatarWanted(String sender) {
    final identity = _seen(sender);
    return identity == null ||
            _avatarIsWithdrawn(sender, identity) ||
            !_time().isBefore(identity.validUntil!) ||
            !identity.hasAvatar ||
            _avatars[sender]?.version == identity.avatarVersion
        ? null
        : identity;
  }

  void rememberAvatar(String sender, String version, Uint8List bytes) {
    final identity = _seen(sender);
    if (identity != null &&
        !_avatarIsWithdrawn(sender, identity) &&
        identity.avatarVersion == version) {
      _avatars[sender] = (version: version, bytes: bytes);
    }
  }

  /// A read returned this avatar with its own confirming answer.
  void confirmAvatar(String sender, String version, Uint8List bytes) {
    final identity = _seen(sender);
    if (identity == null ||
        _avatarIsWithdrawn(sender, identity) ||
        identity.avatarVersion != version) {
      return;
    }
    rememberAvatar(sender, version, bytes);
    notifyListeners();
  }

  void clear() {
    _withdrawn = _withdrawn || _people.isNotEmpty;
    _people.clear();
    _avatars.clear();
    _avatarWithdrawn.clear();
    _retired.clear();
    _hiddenGeneration.clear();
  }

  void withdrawAvatar(String sender, {DateTime? observedAt}) {
    _avatars.remove(sender);
    final at = observedAt ?? _people[sender]?.identity.observedAt;
    if (at == null) return;
    final previous = _avatarWithdrawn[sender];
    if (_avatarWithdrawn.length >= _maximum && previous == null) {
      _avatarWithdrawn.remove(_avatarWithdrawn.keys.first);
    }
    _avatarWithdrawn[sender] = previous != null && previous.isAfter(at)
        ? previous
        : at;
  }

  bool _avatarIsWithdrawn(String sender, CommunityAuthorProjection identity) {
    final at = _avatarWithdrawn[sender];
    return at != null && !identity.observedAt!.isAfter(at);
  }

  /// [then] redraws at once, for an answer that is not part of a page read.
  void forget(String sender, {void Function()? then}) {
    final removed = _people.remove(sender);
    if (removed != null) {
      if (_retired.length >= _maximum && !_retired.containsKey(sender)) {
        _retired.remove(_retired.keys.first);
      }
      final previous = _retired[sender],
          observed = removed.identity.observedAt!;
      _retired[sender] = previous != null && previous.isAfter(observed)
          ? previous
          : observed;
    }
    _withdrawn = removed != null || _withdrawn;
    _avatars.remove(sender);
    then?.call();
  }

  /// A read answered about [asked]. [updates] count too: a message pushed out
  /// of the history meanwhile still answers for its author.
  void answer(
    Iterable<CommunityChatMessage> messages,
    List<String> asked,
    Iterable<CommunityChatAuthorUpdate> updates,
  ) {
    for (final message in messages) {
      if (asked.contains(message.messageRef)) {
        _answer(message.senderRef, message.authorIdentity);
      }
    }
    // A denial applies to the sender, including unasked current-page rows.
    for (final message in messages) {
      if (message.authorIdentity?.state == CommunityAuthorState.hidden) {
        hide(message.senderRef);
      }
    }
    for (final update in updates) {
      if (asked.contains(update.messageRef) &&
          update.found &&
          !messages.any(
            (row) =>
                row.messageRef == update.messageRef &&
                (row.senderRef != update.senderRef ||
                    row.sequence != update.sequence),
          ) &&
          update.identity.state == CommunityAuthorState.hidden) {
        hide(update.senderRef);
      }
    }
  }

  void _answer(String sender, CommunityAuthorProjection? identity) {
    if (identity?.state == CommunityAuthorState.hidden) return hide(sender);
    // Unavailable is neither a denial nor a new observation.
    if (identity?.visible != true) return;
    final now = _time();
    if (!identity!.admit(now).visible || !now.isBefore(deadline(identity))) {
      return;
    }
    final retired = _retired[sender];
    if (retired != null && !identity.observedAt!.isAfter(retired)) return;
    final previous = _people[sender];
    if (previous != null &&
        !identity.observedAt!.isAfter(previous.identity.observedAt!)) {
      // Same/older observations cannot refresh the monotonic budget. A changed
      // or avatar-free answer may still narrow what was previously held.
      if (identity.observedAt == previous.identity.observedAt &&
          !identity.sameIdentityAs(previous.identity)) {
        withdrawAvatar(sender);
      }
      return;
    }
    if (_people.length >= _maximum && !_people.containsKey(sender)) clear();
    _people[sender] = (
      identity: identity,
      until: _elapsed() + deadline(identity).difference(now),
    );
    if (!identity.hasAvatar) {
      withdrawAvatar(sender, observedAt: identity.observedAt);
    }
    if (_avatars[sender]?.version != identity.avatarVersion) {
      _avatars.remove(sender);
    }
  }

  bool allowsProof(String sender, CommunityAuthorProjection identity) {
    if (!identity.visible) return false;
    if (identity.hasAvatar && _avatarIsWithdrawn(sender, identity)) {
      return false;
    }
    final retired = _retired[sender], latest = _people[sender]?.identity;
    if (retired != null && !identity.observedAt!.isAfter(retired)) return false;
    return latest == null ||
        !latest.observedAt!.isAfter(identity.observedAt!) ||
        latest.sameIdentityAs(identity);
  }

  /// [verified]: a read answered for this message. [allowed]: someone is
  /// reading in front; idle or behind another window shows no former name.
  CommunityChatMessage present(
    CommunityChatMessage message, {
    required bool verified,
    required bool allowed,
    required DateTime now,
  }) {
    now = _time(now);
    final seen = allowed ? _seen(message.senderRef, at: now) : null;
    final proof = message.authorIdentity;
    final live =
        allowed &&
            verified &&
            proof?.visible == true &&
            allowsProof(message.senderRef, proof!) &&
            now.toUtc().isBefore(deadline(proof))
        ? proof.admit(now)
        : null;
    if (live?.visible == true) {
      return CommunityChatMessage.withAuthor(message, live!);
    }
    return CommunityChatMessage.withAuthor(
      message,
      seen == null
          ? const CommunityAuthorProjection.unavailable()
          : CommunityAuthorProjection.lastSeen(seen.callsign),
    );
  }

  bool retains(String sender) => _seen(sender) != null;
}
