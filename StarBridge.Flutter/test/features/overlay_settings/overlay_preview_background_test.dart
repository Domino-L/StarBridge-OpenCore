import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preview_background.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('B3 accepts a local preview image and rejects malformed or oversized data', () async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII=');
    await validateOverlayPreviewBackground(png);
    await expectLater(validateOverlayPreviewBackground(Uint8List(0)), throwsFormatException);
    await expectLater(validateOverlayPreviewBackground(Uint8List(20 * 1024 * 1024 + 1)), throwsFormatException);
    await expectLater(validateOverlayPreviewBackground(Uint8List.fromList([1, 2, 3])), throwsA(anything));
  });
  test('B3 picker cancellation is harmless and remote paths are rejected before reading', () async {
    const channel = MethodChannel('starbridge/gameplay_files');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    String? response;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickOverlayBackground');
      return response;
    });
    expect(await pickOverlayPreviewBackground(), isNull);
    for (final path in [r'\\server\share\image.png', 'https://example.invalid/image.png', 'relative.png']) {
      response = path;
      await expectLater(pickOverlayPreviewBackground(), throwsFormatException);
    }
  });
}
