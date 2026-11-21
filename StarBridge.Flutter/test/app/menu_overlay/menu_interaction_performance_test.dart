import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_interaction_presentation.dart';

// Review CX-PERF-MODE-073-REVIEW P2: the menu engine has its own frame
// governor and learns the user's performance mode from this envelope.
void main() {
  test('performance mode round trips and is sent only when on', () {
    const on = MenuInteractionPresentation(
      language: 'zh-CN',
      performanceMode: true,
    );
    expect(
      MenuInteractionPresentation.parse(on.encode())!.performanceMode,
      isTrue,
    );
    const off = MenuInteractionPresentation(language: 'zh-CN');
    expect(jsonDecode(off.encode()), isNot(contains('performanceMode')));
    expect(
      MenuInteractionPresentation.parse(off.encode())!.performanceMode,
      isFalse,
    );
  });

  test('only a literal true is accepted', () {
    for (final value in <Object?>[false, 'true', 1, null]) {
      final payload = jsonEncode({
        'schemaVersion': 1,
        'style': 'standard',
        'reduceMotion': false,
        'performanceMode': value,
      });
      expect(
        MenuInteractionPresentation.parse(payload),
        isNull,
        reason: '$value',
      );
    }
  });

  test('the longest holiday id with performance mode still fits', () {
    final presentation = MenuInteractionPresentation(
      language: 'zh-CN',
      holiday: 'x' * 32,
      performanceMode: true,
    );
    final encoded = presentation.encode();
    expect(
      encoded.length,
      lessThanOrEqualTo(MenuInteractionPresentation.maxPayloadLength),
    );
    final parsed = MenuInteractionPresentation.parse(encoded)!;
    expect(parsed.performanceMode, isTrue);
    expect(parsed.holiday, 'x' * 32);
  });

  // Review CX-SKIA-MAIN-073-REVIEW P3: the native bridge forwards the envelope
  // only within the same length limit as the Dart parser.
  test('the native bridge uses the same envelope length limit', () {
    final bridge = File('windows/runner/menu_overlay_bridge.cpp')
        .readAsStringSync();
    const limit = MenuInteractionPresentation.maxPayloadLength;
    expect(bridge, contains('interaction->size() <= $limit'));
    expect(
      bridge,
      contains('"interactionPresentation" && payload->size() > $limit'),
    );
  });
}
