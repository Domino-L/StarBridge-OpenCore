import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

typedef ApplicationUpdateHeroRead = Future<Map<String, dynamic>> Function(
  String version,
  int offset,
);

/// 和 Host 的 `applicationUpdates.heroRead` 对上：主图最大 3 MiB，单块最大 256 KiB。
const _heroMaxBytes = 3145728, _heroMaxChunkBytes = 262144;

/// 分块读主图。任何一处不对都返回 null，弹窗继续用自带的图。
Future<Uint8List?> readApplicationUpdateHero(
  ApplicationUpdateHeroRead read,
  String version, {
  bool Function()? isCurrent,
}) async {
  try {
    Uint8List? bytes;
    String? digest;
    var offset = 0;
    while (true) {
      final reply = await read(version, offset);
      if (isCurrent?.call() == false) return null;
      final length = reply['length'], next = reply['nextOffset'];
      final chunk = reply['chunk'], done = reply['done'], sha = reply['sha256'];
      if (reply.length != 9 ||
          reply['schemaVersion'] != 1 ||
          reply['version'] != version ||
          reply['offset'] != offset ||
          !const {'image/jpeg', 'image/png'}.contains(reply['mediaType']) ||
          length is! int ||
          length <= 0 ||
          length > _heroMaxBytes ||
          next is! int ||
          chunk is! String ||
          done is! bool ||
          sha is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
          (digest != null && digest != sha) ||
          (bytes != null && bytes.length != length)) {
        return null;
      }
      digest = sha;
      bytes ??= Uint8List(length);
      final decoded = base64Decode(chunk);
      if (decoded.isEmpty ||
          decoded.length > _heroMaxChunkBytes ||
          decoded.length > length - offset ||
          next != offset + decoded.length ||
          done != (next == length)) {
        return null;
      }
      bytes.setRange(offset, next, decoded);
      offset = next;
      if (done) {
        return sha256.convert(bytes).toString() == digest ? bytes : null;
      }
    }
  } on Object {
    return null;
  }
}
