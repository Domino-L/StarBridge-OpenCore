import 'dart:async';
import 'dart:typed_data';

import 'community_image_decoder.dart';
import 'community_workspace_port.dart';
import 'community_own_avatar.dart';

/// Owned by one authorized organization workspace, not by an individual tab.
/// Reuse requires the same authorized opaque member reference and image version,
/// never a display name or a matching picture belonging to a different user.
class CommunityAvatarCache {
  final _entries = <(String, String), Future<Uint8List?>>{};
  final _byteSizes = <(String, String), int>{};
  int _retainedBytes = 0;
  static const _maximumRetainedBytes = 16 * 1024 * 1024;
  final _waiting = <Completer<void>>[];
  CommunityImageDecodeCache images = CommunityImageDecodeCache();
  int _generation = 0, _active = 0;
  bool _disposed = false;

  Future<Uint8List?> get(
    String identity,
    String? version,
    Future<Uint8List?> Function() read, {
    bool retry = false,
  }) {
    if (_disposed) return Future.error(StateError('Disposed avatar scope'));
    final key = (identity, version ?? '');
    if (retry) _remove(key);
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing;
      return existing;
    }
    if (_entries.length >= 96) _remove(_entries.keys.first);
    late final Future<Uint8List?> pending;
    pending = _read(read, _generation).then((bytes) {
      // A cleared, evicted or retried request must not charge a newer entry.
      if (identical(_entries[key], pending)) {
        final size = bytes?.lengthInBytes ?? 0;
        _byteSizes[key] = size;
        _retainedBytes += size;
        while (_retainedBytes > _maximumRetainedBytes && _entries.isNotEmpty) {
          _remove(_entries.keys.first);
        }
      }
      return bytes;
    });
    _entries[key] = pending;
    return pending;
  }

  void _remove((String, String) key) {
    _entries.remove(key);
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
    if (_active >= 3) {
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
    _retainedBytes = 0;
    images.dispose();
    images = CommunityImageDecodeCache();
  }

  /// Reference renewal may keep verified, versioned bytes, never an old
  /// request or a failed/unversioned entry tied to the previous access ref.
  void retainCompleted() {
    _generation++;
    for (final key in _entries.keys.toList()) {
      if (key.$2.isEmpty || (_byteSizes[key] ?? 0) == 0) _remove(key);
    }
  }

  void dispose() {
    clear();
    _disposed = true;
    images.dispose();
  }
}
