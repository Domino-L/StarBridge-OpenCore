import 'dart:convert';
import 'dart:ui' as ui;

import '../../features/communities/community_avatar_cache.dart';
import '../../features/communities/community_workspace_port.dart';
import '../../features/communities/community_image_decoder.dart';

/// Small inline thumbnails only; URLs, disk paths and member refs never cross
/// into the menu renderer. Clear on organization/account changes.
final class MenuOrganizationAvatars {
  MenuOrganizationAvatars({
    this.onChanged,
    this.decoder = decodeCommunityImage,
  });
  final void Function()? onChanged;
  final CommunityImageDecoder decoder;
  final _cache = CommunityAvatarCache();
  final _encoded = <(String, String, String), Future<String?>>{};
  final _ready = <(String, String, String), String>{};
  var _bindings = Expando<(String, String, String)>();
  int _epoch = 0;
  final _logos = <String, Future<String?>>{};

  /// Primary-engine-only association. No member reference is serialized into
  /// the presentation or used to guess which visible row owns a late image.
  Map<String, Object?> bind(
    Map<String, Object?> row,
    String target,
    CommunityWorkspaceMember member,
  ) {
    if (member.hasAvatar) {
      _bindings[row] = (target, member.memberRef, member.avatarVersion ?? '');
    }
    return row;
  }

  Map<String, Object?> project(Map<String, Object?> view) {
    final org = view['organization'];
    if (org is! Map || org['rows'] is! List) return view;
    var changed = false;
    final rows = [for (final row in org['rows'] as List) row];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is! Map<String, Object?>) continue;
      final key = _bindings[row], photo = _ready[_bindings[row]];
      if (key == null || photo == null || row['avatar'] == photo) continue;
      final updated = <String, Object?>{...row, 'avatar': photo};
      _bindings[updated] = key;
      rows[i] = updated;
      changed = true;
    }
    return changed
        ? {
            ...view,
            'organization': {...org, 'rows': rows},
          }
        : view;
  }

  Future<String?> logo(String? source, {bool background = false}) {
    if (source == null ||
        source.length > 699120 ||
        !RegExp(r'^data:image/(png|jpeg|bmp|gif|webp);base64,')
            .hasMatch(source)) {
      return Future.value(null);
    }
    if (!_logos.containsKey(source) && _logos.length >= 32) {
      _logos.remove(_logos.keys.first);
    }
    final pending = _logos.putIfAbsent(source, () async {
      try {
        final image = await decoder(
          base64Decode(source.substring(source.indexOf(',') + 1)),
          64,
        );
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          if (bytes == null || bytes.lengthInBytes > 20000) return null;
          return 'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes))}';
        } finally {
          image.dispose();
        }
      } on Object {
        return null;
      }
    });
    final decoded = pending.then((value) {
      if (value == null && identical(_logos[source], pending)) {
        _logos.remove(source);
      }
      return value;
    });
    // Foreground has a paint budget, not a cancellation budget. Background
    // chat media must still deliver its late onPhoto without a fresh poll.
    return background
        ? decoded
        : decoded.timeout(const Duration(seconds: 2), onTimeout: () => null);
  }

  Future<String?> read(
    CommunityWorkspacePort port,
    String target,
    CommunityWorkspaceMember member,
  ) {
    if (!member.hasAvatar) return Future.value(null);
    final key = (target, member.memberRef, member.avatarVersion ?? '');
    final epoch = _epoch;
    if (!_encoded.containsKey(key) && _encoded.length >= 96) {
      _ready.remove(_encoded.keys.first);
      _encoded.remove(_encoded.keys.first);
    }
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
          if (epoch != _epoch) return null;
          if (value == null && identical(_encoded[key], pending)) {
            _encoded.remove(key);
          } else if (value != null &&
              identical(_encoded[key], pending) &&
              _ready[key] != value) {
            _ready[key] = value;
            onChanged?.call();
          }
          return value;
        })
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
  }

  void clear() {
    _epoch++;
    _ready.clear();
    _bindings = Expando<(String, String, String)>();
    _cache.clear();
    _encoded.clear();
    _logos.clear();
  }

  void dispose() {
    clear();
    _cache.dispose();
    _encoded.clear();
    _logos.clear();
  }
}
