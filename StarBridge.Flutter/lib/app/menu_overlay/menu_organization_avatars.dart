import 'dart:convert';
import 'dart:ui' as ui;

import '../../features/communities/community_avatar_cache.dart';
import '../../features/communities/community_workspace_port.dart';
import '../../features/communities/community_image_decoder.dart';

/// Small inline thumbnails only; URLs, disk paths and member refs never cross
/// into the menu renderer. Clear on organization/account changes.
final class MenuOrganizationAvatars {
  final _cache = CommunityAvatarCache();
  final _encoded = <(String, String), Future<String?>>{};
  final _logos = <String, Future<String?>>{};
  Future<String?> logo(String? source) {
    if (source == null ||
        source.length > 699120 ||
        !RegExp(r'^data:image/(png|jpeg|bmp|gif|webp);base64,')
            .hasMatch(source)) {
      return Future.value(null);
    }
    if (_logos.length >= 32) _logos.remove(_logos.keys.first);
    return _logos
        .putIfAbsent(source, () async {
          try {
            final image = await decodeCommunityImage(
              base64Decode(source.substring(source.indexOf(',') + 1)),
              64,
            );
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (bytes == null || bytes.lengthInBytes > 20000) return null;
              return 'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes))}';
            } finally {
              image.dispose();
            }
          } on Object {
            return null;
          }
        })
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
  }

  Future<String?> read(
    CommunityWorkspacePort port,
    String target,
    CommunityWorkspaceMember member,
  ) {
    if (!member.hasAvatar) return Future.value(null);
    final key = (member.memberRef, member.avatarVersion ?? '');
    if (_encoded.length >= 96) _encoded.remove(_encoded.keys.first);
    final pending = _encoded.putIfAbsent(key, () async {
      try {
        final bytes = await _cache.member(port, target, member, retry: true);
        if (bytes == null) return null;
        final image = await _cache.images.decode(bytes, 64);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null || data.lengthInBytes > 20000) return null;
          return 'data:image/png;base64,${base64Encode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))}';
        } finally {
          image.dispose();
        }
      } on Object {
        return null;
      }
    });
    return pending
        .then((value) {
          if (value == null && identical(_encoded[key], pending)) {
            _encoded.remove(key);
          }
          return value;
        })
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
  }

  void clear() {
    _cache.clear();
    _encoded.clear();
    _logos.clear();
  }

  void dispose() {
    _cache.dispose();
    _encoded.clear();
    _logos.clear();
  }
}
