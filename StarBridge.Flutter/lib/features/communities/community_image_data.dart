import 'dart:convert';
import 'dart:typed_data';

/// Same decoded logo budget as the Host media channel. The wire value is base64.
const communityLogoMaxBytes = 512 * 1024;
const communityLogoMaxDataLength = ((communityLogoMaxBytes + 2) ~/ 3) * 4 + 64;

Uint8List? decodeCommunityLogo(String? data) {
  if (data == null ||
      data.length > communityLogoMaxDataLength ||
      !RegExp(r'^data:image/(png|jpeg|bmp|gif|webp);base64,').hasMatch(data)) {
    return null;
  }
  try {
    final bytes = base64Decode(data.substring(data.indexOf(',') + 1));
    return bytes.isNotEmpty && bytes.length <= communityLogoMaxBytes
        ? bytes
        : null;
  } on FormatException {
    return null;
  }
}
