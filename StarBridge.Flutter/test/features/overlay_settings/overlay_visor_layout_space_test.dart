import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_layout.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_layout_item.dart';

import 'overlay_settings_ux_a_test.dart' show settings;

/// Review CX-VISOR-EDITOR-B88-R1: the visor resolves modules in its 1080-high
/// layout space (StarBridge.Core ResolveItemRect), so the module size limits
/// are layout units. The editors must too: on a small window or canvas the
/// "never moved" check and a moved block's corner are the game's, only scaled.
void main() {
  const members = OverlayWorkspaceLayoutItem(
    key: 'Members',
    x: .0042,
    y: .4864,
    width: .1875,
    height: .1944,
    horizontalAnchor: 'Left',
    verticalAnchor: 'Bottom',
    isLocked: false,
    textOpacity: 1,
    backgroundOpacity: .5,
  );
  const full = Size(1920, 1080), small = Size(1280, 720);

  Rect scaled(Rect r, double f) =>
      Rect.fromLTRB(r.left * f, r.top * f, r.right * f, r.bottom * f);

  test('the never-moved check does not depend on the window size', () {
    expect(
      OverlayVisorLayout.unmoved(members, small),
      OverlayVisorLayout.unmoved(members, full),
    );
    expect(OverlayVisorLayout.unmoved(members, full), isFalse);
  });

  test('a moved block sits where the game puts it, only scaled', () {
    final visor = settings(const {'showMembers': true});
    expect(
      scaled(OverlayVisorLayout.boxOf(members, visor, small), 1.5),
      rectMoreOrLessEquals(
        OverlayVisorLayout.boxOf(members, visor, full),
        epsilon: 0.5,
      ),
    );
  });

  test('a block saved on a small canvas reads back at the same corner', () {
    final visor = settings(const {'showMembers': true});
    final box = OverlayVisorLayout.boxOf(members, visor, small);
    final target = box.shift(const Offset(40, -30));
    final saved = OverlayVisorLayout.save(members, target, small);
    // read back exactly where it was put (review R2), and the game's spot
    expect(
      OverlayVisorLayout.boxOf(saved, visor, small),
      rectMoreOrLessEquals(target, epsilon: 0.5),
    );
    expect(
      scaled(OverlayVisorLayout.boxOf(saved, visor, small), 1.5),
      rectMoreOrLessEquals(
        OverlayVisorLayout.boxOf(saved, visor, full),
        epsilon: 0.5,
      ),
    );
  });
}
