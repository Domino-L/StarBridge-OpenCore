import 'dart:async';
import 'dart:typed_data';

import 'community_image_decoder.dart';
import 'community_workspace_port.dart';
import 'community_own_avatar.dart';

/// Owned by one authorized organization workspace, not by an individual tab.
/// Reuse requires the same authorized opaque member reference and image version,
/// never a display name or a matching picture belonging to a different user.
class CommunityAvatarCache {
  CommunityAvatarCache({this.now = DateTime.now})
    : images = CommunityImageDecodeCache(now: now, capacity: decodedFrames);
  final DateTime Function() now;
  final _entries = <(String, String), _CommunityAvatarRead>{};
  final _byteSizes = <(String, String), int>{};
  final _retryAt = <(String, String), DateTime>{};
  int _retainedBytes = 0;
  static const _maximumRetainedBytes = 16 * 1024 * 1024;
  static const _maximumEntries = 96, _maximumActive = 3;

  /// Decoded portraits (about 36 KB each at 96 px), so a large member list
  /// scrolled back shows already seen avatars in the same frame.
  static const decodedFrames = 256;
  final _waiting = <Completer<void>>[];
  CommunityImageDecodeCache images;
  int _generation = 0, _active = 0;
  bool _disposed = false;

  /// Downloadable decorations share the existing physical media budget without
  /// becoming avatar cache entries. Retiring a view cannot release active IO.
  Future<Uint8List?> readUncachedMedia(Future<Uint8List?> Function() read) =>
      _read(read, _generation);

  Future<Uint8List?> get(
    String identity,
    String? version,
    Future<Uint8List?> Function() read, {
    bool retry = false,
  }) {
    if (_disposed) return Future.error(StateError('Disposed avatar scope'));
    final key = (identity, version ?? '');
    final retryAt = _retryAt[key];
    if (retry || retryAt != null && !now().isBefore(retryAt)) _remove(key);
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing;
      return existing.future;
    }
    if (_entries.length >= _maximumEntries) _remove(_entries.keys.first);
    final entry = _CommunityAvatarRead();
    entry.future =
        _read(() async {
          if (entry.retired) return null;
          return await read();
        }, _generation).then(
          (bytes) {
            if (entry.retired) return null;
            // A cleared, evicted or retried request must not charge a newer entry.
            if (identical(_entries[key], entry)) {
              final size = bytes?.lengthInBytes ?? 0;
              _byteSizes[key] = size;
              _retainedBytes += size;
              while (_retainedBytes > _maximumRetainedBytes &&
                  _entries.isNotEmpty) {
                _remove(_entries.keys.first);
              }
            }
            return bytes;
          },
          onError: (Object error, StackTrace stack) {
            if (entry.retired) return null;
            if (identical(_entries[key], entry)) {
              _retryAt[key] = now().add(const Duration(seconds: 10));
            }
            Error.throwWithStackTrace(error, stack);
          },
        );
    _entries[key] = entry;
    return entry.future;
  }

  /// Explicit person retirement only. Ordinary eviction/retry keep their
  /// historical Future semantics and do not mark an entry retired.
  void retire(String identity, String? version) {
    final key = (identity, version ?? '');
    final entry = _entries[key];
    if (entry == null) return;
    entry.retired = true;
    _remove(key);
  }

  void _remove((String, String) key) {
    _entries.remove(key);
    _retryAt.remove(key);
    _retainedBytes -= _byteSizes.remove(key) ?? 0;
  }


  Future<Uint8List?> member(
    CommunityWorkspacePort port,
    String target,
    CommunityWorkspaceMember member, {
    bool retry = false,
  }) {
    final generation = _generation;
    return get(
      member.memberRef,
      member.avatarVersion,
      () async =>
          readOwnCommunityAvatar(
            port,
            isSelf: member.isSelf,
            version: member.avatarVersion,
          ) ??
          await assembleCommunityMedia(
            (offset, version) => port.readMedia(
              target,
              'avatar',
              memberRef: member.memberRef,
              offset: offset,
              version: version,
            ),
            'avatar',
            memberRef: member.memberRef,
            checkCurrent: () {
              if (_disposed || generation != _generation) {
                throw StateError('Expired avatar scope');
              }
            },
          ),
      retry: retry,
    );
  }

  Future<Uint8List?> _read(
    Future<Uint8List?> Function() read,
    int generation,
  ) async {
    void current() {
      if (_disposed || generation != _generation) {
        throw StateError('Expired avatar scope');
      }
    }

    current();
    if (_active >= _maximumActive) {
      if (_waiting.length >= _maximumEntries - _maximumActive) {
        throw StateError('Avatar read queue is full');
      }
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      current();
      final value = await read();
      current();
      return value;
    } finally {
      if (_waiting.isEmpty) {
        _active--;
      } else {
        _waiting.removeAt(0).complete();
      }
    }
  }

  void clear() {
    _generation++;
    _entries.clear();
    _byteSizes.clear();
    _retryAt.clear();
    _retainedBytes = 0;
    images.dispose();
    images = CommunityImageDecodeCache(now: now, capacity: decodedFrames);
  }

  /// Reference renewal may keep verified, versioned bytes, never an old
  /// request or a failed/unversioned entry tied to the previous access ref.
  void retainCompleted() {
    _generation++;
    for (final key in _entries.keys.toList()) {
      if (key.$2.isEmpty || (_byteSizes[key] ?? 0) == 0) _remove(key);
    }
  }

  /// Reference renewal may keep verified, versioned bytes, never an old
  /// request or a failed/unversioned entry tied to the previous access ref.

  void dispose() {
    clear();
    _disposed = true;
    images.dispose();
  }
}

final class _CommunityAvatarRead {
  late final Future<Uint8List?> future;
  bool retired = false;
}
