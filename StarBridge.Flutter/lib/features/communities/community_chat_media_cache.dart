import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'community_chat_port.dart';
import 'community_author_projection.dart';
import 'community_author_projection_port.dart';
import 'community_image_decoder.dart';
import 'community_avatar_cache.dart';
import 'communities_port.dart';
import 'community_own_avatar.dart';
import 'community_preset_port.dart';
import '../overlay_settings/overlay_preset_inspection_port.dart';
import '../overlay_settings/overlay_preset_transfer.dart';

typedef _CommunityMediaKey = ({
  String reference,
  String? version,
  String sender,
  Object? observation,
  _CommunityPersonPublication person,
});

final class _CommunityPersonPublication {
  _CommunityPersonPublication([this.authority]);
  final CommunityChatMessage? authority;
  CommunityAuthorProjection? observation;
  bool retired = false;
}

class CommunityChatMedia {
  const CommunityChatMedia(
    this.avatar,
    this.attachment, {
    this.preview,
    this.authorCurrent,
  });
  final Uint8List? avatar;
  final Map<String, Object?>? attachment;
  final OverlayPresetTransfer? preview;
  final bool Function()? authorCurrent;
}

/// One authorized conversation owns its original bounded media Futures.
class CommunityChatMediaCache {
  CommunityChatMediaCache(
    this.port,
    this.targetRef, {
    CommunityAvatarCache? avatars,
    DateTime Function()? now,
    this.authorIsCurrent,
    this.narrowAuthor,
    this.onAuthorTimingChanged,
    this.onAvatarConfirmed,
    this.onAccessLost,
  }) : avatars = avatars ?? CommunityAvatarCache(),
       _identityNow = now,
       _ownsAvatars = avatars == null {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityChatPort port;
  final String targetRef;
  final CommunityAvatarCache avatars;
  final bool _ownsAvatars;
  final DateTime Function()? _identityNow;
  final bool Function(CommunityChatMessage)? authorIsCurrent;
  final void Function(CommunityChatMessage, CommunityAuthorProjection)?
  narrowAuthor;
  final void Function()? onAuthorTimingChanged;
  final void Function(String sender, String version, Uint8List bytes)?
  onAvatarConfirmed;

  /// A read was refused: the chat's own read decides what that means.
  final void Function()? onAccessLost;
  final _seenAvatarReads = <String, DateTime>{};
  DateTime get _now => _identityNow?.call() ?? avatars.now();
  CommunityImageDecodeCache get images => avatars.images;
  late final StreamSubscription<void> _subscription;
  final _details = <_CommunityMediaKey, Future<CommunityChatMedia>>{};
  final _ready = <_CommunityMediaKey, CommunityChatMedia>{};
  final _retryAt = <_CommunityMediaKey, DateTime>{};
  final _publications = <_CommunityMediaKey, Object>{};
  static const _maximumRetained = 32, _maximumActive = 3, _maximumWork = 96;
  final _ordinaryPerson = _CommunityPersonPublication();
  bool get _official => port is CommunityAuthorProjectionPort;
  Object? _observation(CommunityChatMessage message) => !_official
      ? null
      : (
          message.authorIdentity?.version,
          message.authorIdentity?.avatarVersion,
          message.authorIdentity?.observedAt,
          message.authorIdentity?.validUntil,
        );
  String _avatarKey(CommunityChatMessage message) => !_official
      ? message.senderRef
      : '${message.senderRef}:chat:${message.messageRef}:${_observation(message)}';
  Iterable<_CommunityMediaKey> get _keys => {
    ..._details.keys,
    ..._ready.keys,
    ..._publications.keys,
  };
  _CommunityMediaKey? _reference(
    CommunityChatMessage message, {
    bool create = true,
  }) {
    final observation = _observation(message);
    final existing = _keys
        .where(
          (key) =>
              key.sender == message.senderRef &&
              key.version == message.avatarVersion &&
              key.observation == observation &&
              (!_official || key.reference == message.messageRef) &&
              !key.person.retired,
        )
        .firstOrNull;
    final person = _official ? existing?.person : _ordinaryPerson;
    if (person == null && !create) return null;
    return (
      reference: message.messageRef,
      version: message.avatarVersion,
      sender: message.senderRef,
      observation: observation,
      person: person ?? _CommunityPersonPublication(message),
    );
  }

  bool _pageCurrent(_CommunityMediaKey key) {
    if (_invalidated || key.person.retired) return false;
    if (!_official) return true;
    final message = key.person.authority;
    return message != null &&
        authorIsCurrent?.call(message) == true &&
        message.authorIdentity?.admit(_now).visible == true;
  }

  bool _personCurrent(_CommunityMediaKey key) =>
      _pageCurrent(key) &&
      (!_official || key.person.observation?.admit(_now).hasAvatar == true);
  CommunityChatMedia _admitted(
    _CommunityMediaKey key,
    CommunityChatMedia value,
  ) => CommunityChatMedia(
    _personCurrent(key) ? value.avatar : null,
    value.attachment,
    preview: value.preview,
    authorCurrent: () => _personCurrent(key),
  );
  CommunityChatMedia? peek(CommunityChatMessage message) {
    if (_invalidated) return null;
    final key = _reference(message, create: false);
    final value = key == null ? null : _ready[key];
    if (key != null && value != null) return _admitted(key, value);
    if (!_official) return null;
    final content = _ready.entries
        .where(
          (entry) =>
              entry.key.reference == message.messageRef &&
              entry.key.sender == message.senderRef,
        )
        .lastOrNull
        ?.value;
    return content == null
        ? null
        : CommunityChatMedia(
            null,
            content.attachment,
            preview: content.preview,
            authorCurrent: () => false,
          );
  }

  /// These facts exist only in the original bounded pending/ready entries.
  DateTime? get nextAuthorDeadline {
    DateTime? earliest;
    for (final key in _keys) {
      if (!_pageCurrent(key)) continue;
      final deadline = key.person.observation?.validUntil;
      if (deadline != null &&
          deadline.isAfter(_now) &&
          (earliest == null || deadline.isBefore(earliest))) {
        earliest = deadline;
      }
    }
    return earliest;
  }

  List<CommunityChatMessage> retireExpiredAuthors(DateTime at) {
    final expired = <String, CommunityChatMessage>{};
    for (final key in _keys) {
      final message = key.person.authority;
      if (key.person.retired || message == null) continue;
      if (message.authorIdentity?.validUntil?.isAfter(at) == false ||
          key.person.observation?.validUntil?.isAfter(at) == false) {
        expired[message.messageRef] = message;
      }
    }
    retireAuthors(expired.values);
    return expired.values.toList();
  }

  void retireAuthors(Iterable<CommunityChatMessage> messages) {
    if (_invalidated || !_official) return;
    final authorities = messages.toList();
    final people = authorities
        .map(
          (message) => (
            message.messageRef,
            message.senderRef,
            message.avatarVersion,
            _observation(message),
          ),
        )
        .toSet();
    for (final message in authorities) {
      avatars.retire(_avatarKey(message), message.avatarVersion);
    }
    for (final key in _keys) {
      if (people.contains((
        key.reference,
        key.sender,
        key.version,
        key.observation,
      ))) {
        key.person.retired = true;
      }
    }
    for (final key in _ready.keys.toList()) {
      if (key.person.retired) _ready[key] = _admitted(key, _ready[key]!);
    }
  }

  /// Reads the avatar of someone shown by their last-seen name, at most once a
  /// minute per person. The server still answers for who may see it; a hidden
  /// answer withdraws them, any other failure just waits for the next try.
  void readSeenAvatar(
    CommunityChatMessage message,
    CommunityAuthorProjection expected,
  ) {
    final sender = message.senderRef, at = avatars.now();
    final last = _seenAvatarReads[sender];
    if (_invalidated ||
        !_official ||
        port is! CommunityChatAuthorDetailPort ||
        last != null && at.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    // A full table waits; clearing it would let everyone be read again at once.
    _seenAvatarReads.removeWhere(
      (_, read) => at.difference(read) >= const Duration(minutes: 1),
    );
    if (_seenAvatarReads.length >= _maximumRetained) return;
    _seenAvatarReads[sender] = at;
    unawaited(
      assembleCommunityChatDetail(
        port,
        targetRef,
        message.messageRef,
        senderRef: sender,
        checkCurrent: _current,
        identity: CommunityChatDetailIdentity(
          expected: expected,
          now: () => _now,
          current: () => !_invalidated,
          avatarConfirmed: (version, bytes) =>
              onAvatarConfirmed?.call(sender, version, bytes),
          narrow: (observed) {
            if (observed.state == CommunityAuthorState.hidden) {
              narrowAuthor?.call(message, observed);
            }
          },
          read: (offset, version, identityVersion) =>
              (port as CommunityChatAuthorDetailPort).readChatAuthorDetail(
                targetRef,
                message.messageRef,
                offset,
                version,
                expectedAuthorIdentityVersion: identityVersion,
              ),
        ),
      ).then<void>(
        (_) {},
        onError: (Object error) {
          // A refusal may mean lost access or just a missing message. The next
          // chat read tells them apart and clears everything if access is gone.
          if (error is CommunityFailure &&
              const {'notAllowed', 'identityUnavailable'}.contains(error.code)) {
            onAccessLost?.call();
          }
        },
      ),
    );
  }

  final _queue = <Completer<void>>[];
  int _active = 0;
  bool _invalidated = false;
  void _current() {
    if (_invalidated) throw StateError('Invalidated conversation media');
  }

  Future<CommunityChatMedia> load(
    CommunityChatMessage message, {
    bool retry = false,
    bool avatarOnly = false,
  }) async {
    _current();
    final reference = _reference(message)!;
    if (retry) _forget(reference);
    if (!_publications.containsKey(reference) &&
        _publications.length >= _maximumWork) {
      throw StateError('Conversation media work is full');
    }
    final publication = Object();
    _publications[reference] = publication;
    Future<Uint8List?> avatar() {
      final Object source = port;
      final current = !_official && source is CommunityOwnAvatarSource
          ? source.ownAvatarImageData
          : null;
      if (message.isSelf && current != null && current.length <= 700000) {
        final version = sha256.convert(utf8.encode(current)).toString();
        return avatars.get(
          '${message.senderRef}:current-account',
          version,
          () async =>
              readOwnCommunityAvatar(source, isSelf: true, version: version),
          retry: retry,
        );
      }
      if (!message.hasAvatar) return Future<Uint8List?>.value(null);
      return avatars.get(
        _avatarKey(message),
        message.avatarVersion,
        () async =>
            (!_official
                ? readOwnCommunityAvatar(
                    port,
                    isSelf: message.isSelf,
                    version: message.avatarVersion,
                  )
                : null) ??
            (await _detail(message)).avatar,
        retry: retry,
      );
    }

    try {
      if (avatarOnly || !message.hasAttachment) {
        final bytes = message.hasAvatar || message.isSelf
            ? await avatar()
            : null;
        _current();
        final result = _admitted(reference, CommunityChatMedia(bytes, null));
        // Kept for peek, so a tile mounted again shows it without a read.
        if (!avatarOnly && identical(_publications[reference], publication)) {
          _ready[reference] = result;
        }
        return result;
      }
      final pending = _detail(message);
      final avatarRead = message.hasAvatar || message.isSelf
          ? avatar()
          : Future<Uint8List?>.value(null);
      avatarRead.ignore();
      final detail = await pending;
      _current();
      final bytes = await avatarRead;
      _current();
      final result = _admitted(
        reference,
        CommunityChatMedia(bytes, detail.attachment, preview: detail.preview),
      );
      if (identical(_details[reference], pending) &&
          identical(_publications[reference], publication)) {
        _ready[reference] = result;
      }
      return result;
    } finally {
      if (identical(_publications[reference], publication)) {
        _publications.remove(reference);
      }
    }
  }

  void _forget(_CommunityMediaKey reference) {
    _details.remove(reference);
    _ready.remove(reference);
    _retryAt.remove(reference);
    _publications.remove(reference);
  }

  Future<CommunityChatMedia> _detail(CommunityChatMessage message) {
    final reference = _reference(message)!;
    final retryAt = _retryAt[reference];
    if (retryAt != null && !avatars.now().isBefore(retryAt)) _forget(reference);
    if (!_details.containsKey(reference) &&
        _details.length >= _maximumRetained) {
      _forget(_details.keys.first);
    }
    return _details.putIfAbsent(reference, () {
      late final Future<CommunityChatMedia> pending;
      pending = _read(message, reference).then(
        (value) {
          _current();
          final result = _admitted(reference, value);
          if (identical(_details[reference], pending)) {
            _ready[reference] = result;
          }
          return result;
        },
        onError: (Object error, StackTrace stack) {
          if (!_invalidated && identical(_details[reference], pending)) {
            _retryAt[reference] = avatars.now().add(
              const Duration(seconds: 10),
            );
          }
          Error.throwWithStackTrace(error, stack);
        },
      );
      return pending;
    });
  }

  Future<CommunityChatMedia> _read(
    CommunityChatMessage message,
    _CommunityMediaKey key,
  ) async {
    _current();
    if (_active >= _maximumActive) {
      if (_queue.length >= _maximumWork - _maximumActive) {
        throw StateError('Conversation media queue is full');
      }
      final ready = Completer<void>();
      _queue.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      _current();
      CommunityChatDetailIdentity? identity;
      if (_official) {
        identity = CommunityChatDetailIdentity(
          expected:
              message.authorIdentity ??
              const CommunityAuthorProjection.unavailable(),
          now: () => _now,
          current: () => _pageCurrent(key),
          avatarConfirmed: (version, bytes) =>
              onAvatarConfirmed?.call(message.senderRef, version, bytes),
          narrow: (observed) {
            // A retired proof does not stop an answer of hidden from counting.
            if (observed.state == CommunityAuthorState.hidden) {
              narrowAuthor?.call(message, observed);
            }
            if (key.person.retired) return;
            key.person.observation = observed;
            if (!observed.visible) {
              key.person.retired = true;
              avatars.retire(_avatarKey(message), message.avatarVersion);
              narrowAuthor?.call(message, observed);
            }
            onAuthorTimingChanged?.call();
          },
          read: (offset, version, expected) =>
              port is CommunityChatAuthorDetailPort
              ? (port as CommunityChatAuthorDetailPort).readChatAuthorDetail(
                  targetRef,
                  message.messageRef,
                  offset,
                  version,
                  expectedAuthorIdentityVersion: expected,
                )
              : port.readChatDetail(
                  targetRef,
                  message.messageRef,
                  offset,
                  version,
                ),
        );
      }
      final detail = await assembleCommunityChatDetail(
        port,
        targetRef,
        message.messageRef,
        checkCurrent: _current,
        identity: identity,
        senderRef: message.senderRef,
      );
      _current();
      OverlayPresetTransfer? preview;
      final Object source = port;
      if (detail.attachment != null &&
          source is CommunityPresetPort &&
          source.communityPresetsAvailable &&
          source is OverlayPresetInspectionPort) {
        try {
          final catalog = await source.readCommunityPresets();
          _current();
          preview = await (source as OverlayPresetInspectionPort).inspectPreset(
            detail.attachment!['overlayPresetPackage'] as String,
            catalog.revision,
          );
        } catch (_) {
          // A local thumbnail failure never removes an authorized attachment.
        }
        _current();
      }
      return _admitted(
        key,
        CommunityChatMedia(
          detail.avatar == null
              ? null
              : base64Decode(detail.avatar!.split(',').last),
          detail.attachment,
          preview: preview,
        ),
      );
    } finally {
      if (_queue.isNotEmpty) {
        _queue.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }

  void invalidate({bool clearShared = true}) {
    _invalidated = true;
    _details.clear();
    _ready.clear();
    _retryAt.clear();
    _publications.clear();
    if (clearShared) avatars.clear();
  }

  void dispose() {
    invalidate(clearShared: _ownsAvatars);
    if (_ownsAvatars) avatars.dispose();
    unawaited(_subscription.cancel());
  }
}
