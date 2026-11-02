import 'dart:convert';
import 'dart:typed_data';

/// Optional display bytes. This never resolves a URL or selects an account.
String? boundedInlineAvatar(Object? value) {
  if (value is! String || value.length > ((512 * 1024 + 2) ~/ 3) * 4 + 24) {
    return null;
  }
  final png = value.startsWith('data:image/png;base64,');
  final jpeg = value.startsWith('data:image/jpeg;base64,');
  if (!png && !jpeg) return null;
  Uint8List bytes;
  try {
    bytes = base64Decode(value.substring(value.indexOf(',') + 1));
  } on FormatException {
    return null;
  }
  if (bytes.length < 24 || bytes.length > 512 * 1024) return null;
  final data = ByteData.sublistView(bytes);
  bool bounded(int width, int height) =>
      width > 0 && width <= 1024 && height > 0 && height <= 1024;
  if (png) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (List.generate(8, (i) => bytes[i] == signature[i]).every((v) => v) &&
        ascii.decode(bytes.sublist(12, 16), allowInvalid: true) == 'IHDR' &&
        bounded(data.getUint32(16), data.getUint32(20))) {
      return value;
    }
    return null;
  }
  if (bytes[0] != 0xff || bytes[1] != 0xd8) return null;
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset++] != 0xff) return null;
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) return null;
    final marker = bytes[offset++];
    if (marker == 0xd9 || marker == 0xda) return null;
    if (offset + 2 > bytes.length) return null;
    final length = data.getUint16(offset);
    if (length < 2 || offset + length > bytes.length) return null;
    if (marker == 0xc0 || marker == 0xc1 || marker == 0xc2) {
      return length >= 8 &&
              bounded(data.getUint16(offset + 5), data.getUint16(offset + 3))
          ? value
          : null;
    }
    offset += length;
  }
  return null;
}

DateTime? inlineAvatarObservedAt(Object? value) {
  final time = value is String ? DateTime.tryParse(value) : null;
  return time != null &&
          time.isUtc &&
          time.isAfter(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)) &&
          !time.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)))
      ? time
      : null;
}
