import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// Local-only preview data. Never part of workspace settings or preset exports.
Future<Uint8List?> pickOverlayPreviewBackground() async {
  final path = await const MethodChannel('starbridge/gameplay_files')
      .invokeMethod<String>('pickOverlayBackground');
  if (path == null) return null;
  if (!RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
    throw const FormatException('Only local files are supported');
  }
  final file = File(path);
  if (await file.length() > 20 * 1024 * 1024) {
    throw const FormatException('Image is too large');
  }
  final bytes = await file.readAsBytes();
  await validateOverlayPreviewBackground(bytes);
  return bytes;
}

Future<void> validateOverlayPreviewBackground(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('Image is too large or empty');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width * descriptor.height > 32000000 ||
          descriptor.width > 16384 ||
          descriptor.height > 16384) {
        throw const FormatException('Image dimensions exceed preview limits');
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}
