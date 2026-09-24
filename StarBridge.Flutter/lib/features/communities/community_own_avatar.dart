import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Optional, current-account inline image already obtained during sign-in.
/// It is display data only, never membership or authorization evidence.
abstract interface class CommunityOwnAvatarSource {
  String? get ownAvatarImageData;
}

Uint8List? readOwnCommunityAvatar(
  Object source, {
  required bool isSelf,
  required String? version,
}) {
  if (!isSelf || version == null || source is! CommunityOwnAvatarSource) {
    return null;
  }
  final data = source.ownAvatarImageData;
  if (data == null ||
      data.length > ((512 * 1024 + 2) ~/ 3 * 4) + 24 ||
      !(data.startsWith('data:image/png;base64,') ||
          data.startsWith('data:image/jpeg;base64,'))) {
    return null;
  }
  // Same S2 content-version convention as the authorized member/chat metadata.
  // Never match by callsign, and never replace a newer or historical image.
  final encoded = data.substring(data.indexOf(',') + 1);
  // Older stored avatars may omit the data URI prefix; the account projection
  // adds it. Both matches still prove the exact same bytes, not a guessed user.
  if (sha256.convert(utf8.encode(data)).toString() != version &&
      sha256.convert(utf8.encode(encoded)).toString() != version) {
    return null;
  }
  try {
    final bytes = base64Decode(encoded);
    return bytes.isEmpty || bytes.length > 512 * 1024 ? null : bytes;
  } on FormatException {
    return null;
  }
}
