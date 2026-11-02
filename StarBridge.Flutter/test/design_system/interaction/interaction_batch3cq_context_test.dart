import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_image_controls.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../app/menu_overlay/menu_reference_crop_test.dart' show pixels;
import 'interaction_batch3cq_support.dart';

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite retired preparation cannot block or clear new pin work',
      (t) async {
        size(t, const Size(900, 900));
        final png = await pixels(t),
            ar = Completer<Object?>(),
            br = Completer<Object?>();
        var ac = 0, bc = 0;
        final a = owner(png, (name, _) async {
          if (name == 'imagePreparePin') {
            ac++;
            return ar.future;
          }
          return false;
        });
        final b = owner(png, (name, _) async {
          if (name == 'imagePin') {
            bc++;
            return br.future;
          }
          return false;
        });
        final h = GlobalKey<ImageHarnessState>(), imageKey = GlobalKey();
        await t.pumpWidget(ImageHarness(a, suite, imageKey: imageKey, key: h));
        await cache(t, png);
        dynamic state = imageKey.currentState;
        a.referenceAutoPinOnClose = true;
        final pendingA = state.pinReference(prepare: true) as Future<void>;
        await painted(t, until: () => ac == 1);
        expect(ac, 1);
        h.currentState!.change(() => h.currentState!.tools = b);
        await cache(t, png);
        expect(state.preparingPin, isFalse);
        await fire(t, '固定到游戏', 'pointer');
        await painted(t, until: () => bc == 1);
        expect(bc, 1);
        b.notice = 'new owner notice';
        state.pinPreparationFailed = true;
        ar.complete(true);
        await pendingA;
        await frames(t);
        expect(b.notice, 'new owner notice');
        expect(state.pinPreparationFailed, isTrue);
        expect(state.capturingFrame, isTrue);
        br.complete(true);
        await frames(t);
        await t.pumpWidget(const SizedBox());
        a.dispose();
        b.dispose();
      },
    );
    testWidgets('$suite old pin state cannot write a rebound owner', (t) async {
      size(t, const Size(900, 900));
      final png = await pixels(t), reply = Completer<Object?>();
      var reads = 0;
      final a = owner(png, (name, _) {
        if (name == 'imagePinState') {
          reads++;
          return reply.future;
        }
        return Future<Object?>.value(false);
      });
      final b = owner(png, (_, _) async => false);
      final workspace = MenuWorkspaceController(
        scope: Object(),
        panels: [
          MenuPanelSpec(
            id: 'image',
            initialBounds: const Rect.fromLTWH(0, 0, 900, 900),
          ),
        ],
      )..open('image');
      final h = GlobalKey<ImageHarnessState>(), imageKey = GlobalKey();
      await t.pumpWidget(
        ImageHarness(
          a,
          suite,
          workspace: workspace,
          imageKey: imageKey,
          key: h,
        ),
      );
      await cache(t, png);
      expect(reads, 1);
      final oldElement = imageKey.currentContext;
      h.currentState!.change(() => h.currentState!.tools = b);
      await frames(t);
      expect(imageKey.currentContext, same(oldElement));
      reply.complete(true);
      await frames(t);
      expect(b.pinned, isFalse);
      await t.pumpWidget(const SizedBox());
      a.dispose();
      b.dispose();
      workspace.dispose();
    });
    testWidgets('$suite old pin completion cannot retire the new pin frame', (
      t,
    ) async {
      size(t, const Size(900, 900));
      final png = await pixels(t),
          ar = Completer<Object?>(),
          br = Completer<Object?>();
      var ac = 0, bc = 0;
      final a = owner(png, (name, _) async {
        if (name == 'imagePin') {
          ac++;
          return ar.future;
        }
        return false;
      });
      final b = owner(png, (name, _) async {
        if (name == 'imagePin') {
          bc++;
          return br.future;
        }
        return false;
      });
      final h = GlobalKey<ImageHarnessState>(), imageKey = GlobalKey();
      await t.pumpWidget(ImageHarness(a, suite, imageKey: imageKey, key: h));
      await cache(t, png);
      await fire(t, '固定到游戏', 'pointer');
      await painted(t, until: () => ac == 1);
      expect(ac, 1);
      h.currentState!.change(() => h.currentState!.tools = b);
      await cache(t, png);
      await fire(t, '固定到游戏', 'pointer');
      await painted(t, until: () => bc == 1);
      expect(bc, 1);
      dynamic state = imageKey.currentState;
      expect(state.capturingFrame, isTrue);
      ar.complete(true);
      await frames(t);
      expect(state.capturingFrame, isTrue);
      expect(
        t.widget<MenuImageBusy>(find.byType(MenuImageBusy)).source,
        InteractionSource.pointer,
      );
      br.complete(true);
      await frames(t);
      expect(state.capturingFrame, isFalse);
      await t.pumpWidget(const SizedBox());
      a.dispose();
      b.dispose();
    });
  }
}
