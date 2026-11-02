
import 'package:flutter/foundation.dart';

import 'community_author_projection.dart';
import 'community_chat_port.dart';

/// Names and avatars this viewer already saw in this chat. In memory only, one
/// per chat model, so never across viewers.
///
/// Proofs live seconds and a read takes seconds, so what is shown does not wait
/// for a live proof (user 2026-10-31: a hidden name may stay up to five minutes).
/// A read answering hidden withdraws that author at once. A temporary failure
/// or unavailable answer keeps them, at most [maximumAge] after the last read
/// that confirmed them. This shows only what was seen and grants nothing: who
/// may see a person is still decided by the first full read.
final class CommunityChatSeenAuthors extends ChangeNotifier {
  CommunityChatSeenAuthors({Duration Function()? elapsed})
    : _elapsed = elapsed ?? _clock;

  static final _stopwatch = Stopwatch()..start();
  static Duration _clock() => _stopwatch.elapsed;
  /// How often the chat calls [sweep]. The limit counts it, so nothing is on
  /// screen past five minutes even with nothing else redrawing.
  static const sweepEvery = Duration(seconds: 5);
  static const maximumAge = Duration(minutes: 4, seconds: 55);
  static const _maximum = 500;

  final Duration Function() _elapsed;
  final _people = <String, ({CommunityAuthorProjection identity, Duration at})>{};
  final _avatars = <String, ({String version, Uint8List bytes})>{};
  bool _withdrawn = false;

  /// Drops whoever passed the limit. True when something shown must redraw.
  bool sweep() {
    final now = _elapsed();
    _people.keys
        .where((sender) => now - _people[sender]!.at > maximumAge)
        .toList()
        .forEach(forget);
    final withdrawn = _withdrawn;
    _withdrawn = false;
    return withdrawn;
  }

  /// The last confirmed answer for [sender], while it may still be shown.
  CommunityAuthorProjection? _seen(String sender) {
    final held = _people[sender];
    if (held == null) return null;
    if (_elapsed() - held.at <= maximumAge) return held.identity;
    forget(sender);
    return null;
  }

  /// The avatar kept for [sender]; with [version], only that exact avatar.
  Uint8List? avatarOf(String sender, {String? version}) {
    if (_seen(sender) == null) return null;
    final held = _avatars[sender];
    return held == null || version != null && held.version != version
        ? null
        : held.bytes;
  }

  /// The confirmed answer to read this person's avatar with, when it has one
  /// that is not held yet.
  CommunityAuthorProjection? avatarWanted(String sender) {
    final identity = _seen(sender);
    return identity == null ||
            !identity.hasAvatar ||
            _avatars[sender]?.version == identity.avatarVersion
        ? null
        : identity;
  }

  void rememberAvatar(String sender, String version, Uint8List bytes) {
    if (_people.containsKey(sender)) {
      _avatars[sender] = (version: version, bytes: bytes);
    }
  }

  /// A read returned this avatar with its own confirming answer.
  void confirmAvatar(String sender, String version, Uint8List bytes) {
    if (!_people.containsKey(sender) ||
        _people[sender]!.identity.avatarVersion != version) {
      return;
    }
    rememberAvatar(sender, version, bytes);
    notifyListeners();
  }

  void clear() {
    _withdrawn = _withdrawn || _people.isNotEmpty;
    _people.clear();
    _avatars.clear();
  }

  /// [then] redraws at once, for an answer that is not part of a page read.
  void forget(String sender, {void Function()? then}) {
    _withdrawn = _people.remove(sender) != null || _withdrawn;
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
    for (final update in updates) {
      if (asked.contains(update.messageRef) &&
          update.found &&
          update.identity.state == CommunityAuthorState.hidden) {
        forget(update.senderRef);
      }
    }
  }

  void _answer(String sender, CommunityAuthorProjection? identity) {
    if (identity?.state == CommunityAuthorState.hidden) return forget(sender);
    // Unavailable says nothing about this person; only the age limit applies.
    if (identity?.visible != true) return;
    if (_people.length >= _maximum && !_people.containsKey(sender)) clear();
    _people[sender] = (identity: identity!, at: _elapsed());
    if (_avatars[sender]?.version != identity.avatarVersion) {
      _avatars.remove(sender);
    }
  }

  /// [verified]: a read answered for this message. [allowed]: someone is
  /// reading in front; idle or behind another window shows no former name.
  CommunityChatMessage present(
    CommunityChatMessage message, {
    required bool verified,
    required bool allowed,
    required DateTime now,
  }) {
    final live = verified ? message.authorIdentity?.admit(now) : null;
    if (live?.visible == true) {
      return CommunityChatMessage.withAuthor(message, live!);
    }
    final seen = allowed ? _seen(message.senderRef) : null;
    return CommunityChatMessage.withAuthor(
      message,
      seen == null
          ? const CommunityAuthorProjection.unavailable()
          : CommunityAuthorProjection.lastSeen(seen.callsign),
    );
  }
}
