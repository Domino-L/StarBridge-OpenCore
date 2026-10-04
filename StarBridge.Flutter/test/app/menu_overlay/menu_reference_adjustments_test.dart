import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/platform/window/menu_image_preferences.dart';

// Controller-only fixture. Pixel rendering is covered by the native fixture
// and widget tests using fully encoded synthetic PNGs.
Uint8List pngHeader() {
  final bytes = Uint8List(33)
    ..setRange(0, 8, [137, 80, 78, 71, 13, 10, 26, 10]);
  ByteData.sublistView(bytes)
    ..setUint32(8, 13)
    ..setUint32(12, 0x49484452)
    ..setUint32(16, 8)
    ..setUint32(20, 4);
  return bytes;
}

String identity(int n) =>
    '{00000000-0000-0000-0000-${n.toRadixString(16).padLeft(12, '0')}}';
Map<String, Object?> selected(int n) => {
  'bytes': pngHeader(),
  'imageId': identity(n),
};

void main() {
  test(
    'same opaque file restores adjustments, not pixels or pin acknowledgement',
    () async {
      var next = 1;
      final tools = MenuLocalToolsController(
        (action, _) async => action == 'image'
            ? selected(next)
            : action == 'imageEdit'
            ? pngHeader()
            : true,
      );
      addTearDown(tools.dispose);
      await tools.image();
      tools.referenceChanged(turns: 3, opacity: .35);
      tools.referenceView(imageOnly: true);
      tools.referenceTransform.value = Matrix4.identity()
        ..scaleByDouble(2, 2, 2, 1);
      tools.referenceScaleMode = null;
      await tools.pin(const {});
      next = 2;
      await tools.image();
      expect(tools.referenceTurns, 0);
      expect(tools.referenceOpacity, 1);
      expect(tools.referenceImageOnly, isFalse);
      next = 1;
      await tools.image();
      expect(tools.referenceTurns, 3);
      expect(tools.referenceOpacity, .35);
      expect(tools.referenceImageOnly, isTrue);
      expect(tools.referenceTransform.value.getMaxScaleOnAxis(), 2);
      expect(tools.referenceScaleMode, isNull);
      expect(tools.pinned, isFalse);
      expect(tools.referenceAutoPinPending, isTrue);
      expect(tools.referenceNoticeKey, 'restored');
    },
  );
  test('disabling memory immediately forgets prior adjustments without changing current image', () async {
    var next = 1;
    final tools = MenuLocalToolsController((_, _) async => selected(next));
    addTearDown(tools.dispose);
    await tools.image();
    tools.referenceChanged(turns: 2, opacity: .4);
    next = 2;
    await tools.image();
    final current = tools.reference;
    tools.settings(
      image: const MenuImagePreferences(rememberAdjustments: false),
    );
    expect(identical(current, tools.reference), isTrue);
    tools.settings(image: const MenuImagePreferences());
    next = 1;
    await tools.image();
    expect(tools.referenceTurns, 0);
    expect(tools.referenceOpacity, 1);
  });
  test('memory is bounded to 32 recently selected files', () async {
    var next = 1;
    final tools = MenuLocalToolsController((_, _) async => selected(next));
    addTearDown(tools.dispose);
    await tools.image();
    tools.referenceChanged(turns: 2);
    for (next = 2; next <= 34; next++) {
      await tools.image();
    }
    next = 1;
    await tools.image();
    expect(tools.referenceTurns, 0);
    expect(tools.referenceNoticeKey, isEmpty);
  });
  test('manual unpin beats default pin when the same image returns', () async {
    var next = 1;
    final tools = MenuLocalToolsController(
      (action, _) async => action == 'image' ? selected(next) : true,
    );
    addTearDown(tools.dispose);
    tools.settings(image: const MenuImagePreferences(defaultPinned: true));
    await tools.image();
    expect(tools.referenceAutoPinPending, isTrue);
    await tools.pin(const {});
    await tools.clear(unpinOnly: true);
    next = 2;
    await tools.image();
    next = 1;
    await tools.image();
    expect(tools.referenceAutoPinPending, isFalse);
    expect(tools.pinned, isFalse);
  });
  test(
    'cancel, invalid identity and late disposed reply do not apply adjustments',
    () async {
      Object? reply = selected(1);
      final tools = MenuLocalToolsController((_, _) async => reply);
      await tools.image();
      tools.referenceChanged(turns: 2);
      final current = tools.reference;
      for (reply in <Object?>[
        null,
        {...selected(1), 'imageId': 'path.png'},
        {...selected(1), 'path': 'path.png'},
      ]) {
        await tools.image();
        expect(identical(current, tools.reference), isTrue);
        expect(tools.referenceTurns, 2);
      }
      reply = {
        'bytes': Uint8List.fromList([1]),
        'imageId': null,
      };
      await tools.image();
      expect(tools.referenceNoticeKey, 'identityUnavailable');
      tools.dispose();
      final pending = Completer<Object?>();
      final closed = MenuLocalToolsController((_, _) => pending.future);
      final load = closed.image();
      closed.dispose();
      pending.complete(selected(1));
      await load;
      expect(closed.reference, isNull);
      expect(closed.referenceAutoPinPending, isFalse);
    },
  );
  test('new owner never inherits the prior owner runtime memory', () async {
    final old = MenuLocalToolsController((_, _) async => selected(1));
    await old.image();
    old.referenceChanged(turns: 3);
    old.dispose();
    final fresh = MenuLocalToolsController((_, _) async => selected(1));
    addTearDown(fresh.dispose);
    await fresh.image();
    expect(fresh.referenceTurns, 0);
  });
}
