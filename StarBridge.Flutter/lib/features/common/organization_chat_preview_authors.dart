import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../shared/diagnostics/loading_read_scope.dart';
import '../communities/communities_module.dart' show CommunityFailure;
import '../communities/community_author_projection.dart';
import '../communities/community_author_projection_port.dart';
import '../communities/community_chat_author_window.dart';
import '../communities/community_chat_port.dart';

/// Author names for the upper screen's chat tile. An official author proof
/// lives seconds, so this renews it, only while the relay allows it (off unless
/// it says otherwise), the tile is on screen, the window in front and someone
/// active. One read costs at least a dozen partner requests, hence the slower
/// cadence, the bounded observation and the backoff.
///
/// Stopgap: replace with pushed author names and revocation once realtime push
/// is on (STARBRIDGE_REALTIME_FANOUT_ENABLED). The roster cannot stand in: its
/// member references and chat sender references are unrelated by design.
final class OrganizationChatPreviewAuthors extends ChangeNotifier {
  OrganizationChatPreviewAuthors(
    this.port, {
    DateTime Function()? now,
    Duration Function()? elapsed,
    this.interval = const Duration(seconds: 4),
    this.maximumBackoff = const Duration(seconds: 60),
    this.onAccessLost,
  }) : _now = now ?? DateTime.now,
       _elapsed = elapsed ?? (Stopwatch()..start()).elapsedGetter {
    _changes = port.previewAuthorChanges.listen((_) {
      _epoch++;
      _reading = false;
      _retire();
      _schedule(interval);
    });
  }

  final OrganizationChatPreviewAuthorPort port;
  final Duration interval, maximumBackoff;

  /// The chat read itself was refused: the owner clears content, not just names.
  final void Function(String code)? onAccessLost;
  final DateTime Function() _now;

  /// How long a name may show is counted on this monotonic clock, so setting
  /// the wall clock back cannot extend it.
  final Duration Function() _elapsed;
  final _clock = CommunityChatAuthorWindow();
  late final StreamSubscription<void> _changes;
  final _proofs = <int, _Proof>{};
  Timer? _next, _expiry;
  String? _target;
  bool _active = false, _reading = false, _closed = false;
  bool _refreshRequired = true;
  int _epoch = 0, _latest = 0, _failures = 0, _count = 3, _resizes = 0;

  set target(String? value) {
    if (value == _target) return;
    _target = value;
    _epoch++;
    _reading = false;
    _failures = 0;
    _retire();
    if (_active) _read();
  }

  /// How many messages the tile shows; only those are observed.
  set shownCount(int value) {
    final next = value.clamp(1, 8);
    if (next == _count) return;
    final grew = next > _count;
    _count = next;
    _resizes++;
    final before = _signature();
    _trim();
    if (grew) _refreshRequired = true;
    if (_signature() != before) notifyListeners();
  }

  void setActive(bool value) {
    if (_closed) return;
    if (value == _active) {
      // The relay's answer may have changed on a verified reopen.
      if (value && !_reading && _next == null) _read();
      return;
    }
    _active = value;
    _next?.cancel();
    _next = null;
    _epoch++;
    _reading = false;
    _failures = 0;
    if (!value) {
      _retire();
      return;
    }
    _read();
  }

  /// The message as the tile may show it now. An expired proof shows nothing;
  /// a hidden author stays hidden. Retained content never grants a name.
  CommunityChatMessage present(CommunityChatMessage message) {
    final proof = _proofs[message.sequence];
    if (proof == null ||
        proof.senderRef != message.senderRef ||
        proof.expired(_elapsed())) {
      return CommunityChatMessage.neutralAuthor(message);
    }
    // Admitted once on receipt; from then on only the monotonic period counts,
    // so what shows and what notifies are always the same state.
    return CommunityChatMessage.withAuthor(message, proof.identity);
  }

  void _schedule(Duration delay) {
    _next?.cancel();
    _next = null;
    if (_closed || !_active) return;
    _next = Timer(delay, () {
      _next = null;
      _read();
    });
  }

  void _read() {
    final target = _target;
    // With the relay's switch off nothing is read and no timer stays armed;
    // the next verified open asks again.
    if (_closed ||
        !_active ||
        _reading ||
        target == null ||
        !port.previewAuthorsAvailable) {
      return;
    }
    _reading = true;
    final epoch = _epoch;
    unawaited(
      backgroundLoadingRead(() async {
        try {
          final full = _refreshRequired || _proofs.isEmpty;
          final resizes = _resizes;
          final observed = full
              ? const <String>[]
              : [for (final proof in _proofs.values) proof.messageRef];
          final page = await port.renewPreviewAuthors(
            target,
            after: full ? 0 : _latest,
            limit: _count,
            observeMessageRefs: observed,
          );
          if (_closed || epoch != _epoch) return;
          if (page.targetRef != target) {
            throw const FormatException();
          }
          _apply(page, observed);
          // The tile resized while this was out, or messages arrived faster
          // than one read covers: the next read takes the newest window again.
          if (_resizes != resizes || page.latestSequence > _latest) {
            _refreshRequired = true;
          }
          _failures = 0;
          _reading = false;
          _schedule(interval);
        } on Object catch (error) {
          // No error mark on a preview. Fail closed and back off, so a struggling
          // or braked relay is not asked again every few seconds.
          if (_closed || epoch != _epoch) return;
          _refreshRequired = true;
          _retire();
          _reading = false;
          _failures++;
          _schedule(_backoff());
          if (error is CommunityFailure &&
              const {
                'identityUnavailable',
                'notAllowed',
                'notFound',
              }.contains(error.code)) {
            onAccessLost?.call(error.code);
          }
        }
      }),
    );
  }

  Duration _backoff() {
    final scaled = interval * math.pow(2, math.min(_failures, 10)).toInt();
    return scaled > maximumBackoff ? maximumBackoff : scaled;
  }

  /// Admits the observation now and fixes how long it may show from here.
  _Proof _proof(
    String messageRef,
    String senderRef,
    CommunityAuthorProjection identity,
  ) {
    final now = _clock.identityTime(_now());
    final admitted = identity.admit(now);
    return _Proof(
      messageRef,
      senderRef,
      admitted,
      admitted.visible
          ? _elapsed() + admitted.validUntil!.difference(now)
          : null,
    );
  }

  void _apply(CommunityChatPage page, List<String> observed) {
    final before = _signature();
    final updates = {
      for (final update in page.authorUpdates) update.messageRef: update,
    };
    for (final sequence in _proofs.keys.toList()) {
      final proof = _proofs[sequence]!;
      if (!observed.contains(proof.messageRef)) continue;
      final update = updates[proof.messageRef];
      final valid =
          update != null &&
          update.senderRef == proof.senderRef &&
          update.sequence == sequence;
      _proofs[sequence] = _proof(
        proof.messageRef,
        proof.senderRef,
        valid ? update.identity : const CommunityAuthorProjection.unavailable(),
      );
    }
    for (final message in page.messages) {
      _proofs[message.sequence] = _proof(
        message.messageRef,
        message.senderRef,
        message.authorIdentity ?? const CommunityAuthorProjection.unavailable(),
      );
      if (message.sequence > _latest) _latest = message.sequence;
    }
    _trim();
    _refreshRequired = page.authorRefreshRequired;
    _scheduleExpiry();
    // A renewal alone changes nothing on screen, so the page does not rebuild.
    if (_signature() != before) notifyListeners();
  }

  void _trim() {
    final sequences = _proofs.keys.toList()..sort();
    for (final old in sequences.take(math.max(0, sequences.length - _count))) {
      _proofs.remove(old);
    }
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    _expiry = null;
    final now = _elapsed();
    Duration? earliest;
    for (final proof in _proofs.values) {
      final expires = proof.expires;
      if (expires != null && (earliest == null || expires < earliest)) {
        earliest = expires;
      }
    }
    if (earliest == null) return;
    final wait = earliest - now;
    _expiry = Timer(wait.isNegative ? Duration.zero : wait, () {
      if (_closed) return;
      final at = _elapsed();
      final before = _signature();
      for (final entry in _proofs.entries.toList()) {
        if (entry.value.expired(at)) {
          _proofs[entry.key] = _Proof(
            entry.value.messageRef,
            entry.value.senderRef,
            const CommunityAuthorProjection.unavailable(),
            null,
          );
        }
      }
      if (_signature() != before) notifyListeners();
      _scheduleExpiry();
    });
  }

  String _signature() => [
    for (final entry in _proofs.entries)
      '${entry.key}:${entry.value.identity.state.name}:'
          '${entry.value.identity.callsign}',
  ].join('|');

  void _retire() {
    _expiry?.cancel();
    _expiry = null;
    _refreshRequired = true;
    _latest = 0;
    if (_proofs.isEmpty) return;
    _proofs.clear();
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _next?.cancel();
    _expiry?.cancel();
    unawaited(_changes.cancel());
    super.dispose();
  }
}

final class _Proof {
  const _Proof(this.messageRef, this.senderRef, this.identity, this.expires);
  final String messageRef, senderRef;
  final CommunityAuthorProjection identity;

  /// On the monotonic clock; null when there is no name to expire.
  final Duration? expires;
  bool expired(Duration at) => expires != null && at >= expires!;
}

extension on Stopwatch {
  Duration Function() get elapsedGetter =>
      () => elapsed;
}
