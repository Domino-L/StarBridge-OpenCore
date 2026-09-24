import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

abstract interface class CommunityShipImagePort {
  bool get shipImageAvailable;
  Future<Map<String, Object?>> readShipImage(
    String targetRef,
    String shipRef, {
    required int offset,
    String? version,
  });
}

final class CommunityShipImage {
  const CommunityShipImage(
    this.bytes,
    this.mimeType,
    this.focusX,
    this.focusY,
    this.zoom,
    this.version,
  );
  final Uint8List bytes;
  final String mimeType;
  final String version;
  final double focusX, focusY, zoom;
}

/// No image bytes are published before the entire version has been verified.
Future<CommunityShipImage> assembleCommunityShipImage(
  CommunityShipImagePort port,
  String targetRef,
  String shipRef, {
  required void Function() checkCurrent,
}) async {
  final bytes = BytesBuilder(copy: false);
  var offset = 0;
  String? version, hash, mime;
  int? total;
  (double, double, double)? crop;
  while (true) {
    checkCurrent();
    final row = await port.readShipImage(
      targetRef,
      shipRef,
      offset: offset,
      version: version,
    );
    checkCurrent();
    final currentVersion = row['version'], currentHash = row['contentHash'];
    final currentTotal = row['totalBytes'], currentMime = row['mimeType'];
    final data = row['data'];
    double number(String key, double min, double max) {
      final value = row[key];
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw const FormatException();
      }
      return value.toDouble();
    }

    final currentCrop = (
      number('cropFocusX', 0, 1),
      number('cropFocusY', 0, 1),
      number('cropZoom', 1, 3),
    );
    final digest = RegExp(r'^[a-f0-9]{64}$');
    if (row['schemaVersion'] != 1 ||
        row['targetRef'] != targetRef ||
        row['shipRef'] != shipRef ||
        row['offset'] != offset ||
        currentVersion is! String ||
        !digest.hasMatch(currentVersion) ||
        currentHash is! String ||
        !digest.hasMatch(currentHash) ||
        currentTotal is! int ||
        currentTotal <= offset ||
        currentTotal > 2 * 1024 * 1024 ||
        currentMime is! String ||
        !const {'image/png', 'image/jpeg'}.contains(currentMime) ||
        data is! String ||
        data.length > 256 * 1024 ||
        version != null &&
            (version != currentVersion ||
                hash != currentHash ||
                total != currentTotal ||
                mime != currentMime ||
                crop != currentCrop)) {
      throw const FormatException();
    }
    version = currentVersion;
    hash = currentHash;
    total = currentTotal;
    mime = currentMime;
    crop = currentCrop;
    final chunk = base64Decode(data);
    if (chunk.length != (total - offset).clamp(0, 192 * 1024)) {
      throw const FormatException();
    }
    offset += chunk.length;
    if (row['next'] != (offset < total ? offset : null)) {
      throw const FormatException();
    }
    bytes.add(chunk);
    if (offset == total) break;
  }
  final result = bytes.takeBytes();
  if (sha256.convert(result).toString() != hash) throw const FormatException();
  checkCurrent();
  return CommunityShipImage(result, mime, crop.$1, crop.$2, crop.$3, version);
}
