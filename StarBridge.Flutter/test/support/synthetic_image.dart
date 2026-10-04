import 'dart:convert';
import 'dart:typed_data';

/// A one-pixel PNG for image-loading tests, independent of optional media packs.
ByteData syntheticImageData() => ByteData.sublistView(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);
