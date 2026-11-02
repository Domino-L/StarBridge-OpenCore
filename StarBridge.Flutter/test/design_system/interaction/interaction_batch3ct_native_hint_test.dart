import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_notice_banner.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, closeKey, notice, detach;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite hint exit releases only its own lease after actual paint exit',
      (t) async {
        final baseline = nativeViewportMenus.value;
        late VoidCallback foreignOpen, foreignClose;
        final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await t.pumpWidget(
            host(
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NativeViewportMenu(
                    builder: (open, close) {
                      foreignOpen = open;
                      foreignClose = close;
                      return const SizedBox.shrink();
                    },
                  ),
                  const SizedBox(
                    width: 360,
                    child: MenuNoticeBanner(notice: notice),
                  ),
                ],
              ),
              suite,
            ),
          );
          await t.pump();
          foreignOpen();
          expect(nativeViewportMenus.value, baseline + 1);
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(t.getCenter(find.byKey(closeKey)));
          await t.pump();
          await t.pump(const Duration(milliseconds: 800));
          await t.pump(const Duration(milliseconds: 200));
          expect(nativeViewportMenus.value, baseline + 2);
          await mouse.moveTo(Offset.zero);
          await t.pump();
          await t.pump(const Duration(milliseconds: 45));
          final hint = find.text('关闭');
          final painted =
              hint.evaluate().isNotEmpty &&
              t
                      .widget<Opacity>(
                        find
                            .ancestor(of: hint, matching: find.byType(Opacity))
                            .first,
                      )
                      .opacity >
                  0;
          // Group-browsing hints may close instantly. Retain the lease for as
          // long as this hint actually paints, without forcing a fixed duration.
          expect(nativeViewportMenus.value, baseline + (painted ? 2 : 1));
          await t.pump(const Duration(milliseconds: 200));
          expect(find.text('关闭'), findsNothing);
          expect(nativeViewportMenus.value, baseline + 1);
          foreignClose();
          expect(nativeViewportMenus.value, baseline);
        } finally {
          await mouse.removePointer();
          await detach(t);
        }
        expect(nativeViewportMenus.value, baseline);
      },
    );

    testWidgets(
      '$suite expiry disposes a visible hint without releasing another owner',
      (t) async {
        final baseline = nativeViewportMenus.value;
        late VoidCallback foreignOpen, foreignClose;
        final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await t.pumpWidget(
            host(
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NativeViewportMenu(
                    builder: (open, close) {
                      foreignOpen = open;
                      foreignClose = close;
                      return const SizedBox.shrink();
                    },
                  ),
                  const SizedBox(
                    width: 360,
                    child: MenuNoticeBanner(notice: notice),
                  ),
                ],
              ),
              suite,
            ),
          );
          await t.pump();
          foreignOpen();
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(t.getCenter(find.byKey(closeKey)));
          await t.pump();
          await t.pump(const Duration(milliseconds: 800));
          await t.pump(const Duration(milliseconds: 200));
          expect(nativeViewportMenus.value, baseline + 2);
          await t.pump(const Duration(milliseconds: 2999));
          expect(find.text(notice.title), findsOneWidget);
          await t.pump(const Duration(milliseconds: 1));
          expect(find.text(notice.title), findsNothing);
          expect(find.text('关闭'), findsNothing);
          expect(nativeViewportMenus.value, baseline + 1);
          foreignClose();
        } finally {
          await mouse.removePointer();
          await detach(t);
        }
        expect(nativeViewportMenus.value, baseline);
      },
    );

    for (final gate in ['native-scope', 'ancestor-tooltip']) {
      testWidgets(
        '$suite $gate hides the hint and releases its lease without resetting expiry',
        (t) async {
          final baseline = nativeViewportMenus.value;
          var visible = true;
          late StateSetter update;
          final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
          try {
            await t.pumpWidget(
              StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return host(
                    TooltipVisibility(
                      visible: gate != 'ancestor-tooltip' || visible,
                      child: NativeViewportScope(
                        active: gate != 'native-scope' || visible,
                        child: const SizedBox(
                          width: 360,
                          child: MenuNoticeBanner(notice: notice),
                        ),
                      ),
                    ),
                    suite,
                  );
                },
              ),
            );
            await t.pump();
            await mouse.addPointer(location: Offset.zero);
            await mouse.moveTo(t.getCenter(find.byKey(closeKey)));
            await t.pump();
            await t.pump(const Duration(milliseconds: 800));
            await t.pump(const Duration(milliseconds: 200));
            expect(nativeViewportMenus.value, baseline + 1);
            update(() => visible = false);
            await t.pump();
            await t.pump();
            expect(find.text('关闭'), findsNothing);
            expect(nativeViewportMenus.value, baseline);
            expect(find.text(notice.title), findsOneWidget);
            await t.pump(const Duration(seconds: 3));
            expect(find.text(notice.title), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await mouse.removePointer();
            await detach(t);
          }
          expect(nativeViewportMenus.value, baseline);
        },
      );
    }

    testWidgets('$suite hiding the actual bridge disposes its hint lease', (
      t,
    ) async {
      final baseline = nativeViewportMenus.value;
      var visible = true;
      late StateSetter update;
      final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await t.pumpWidget(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return host(
                MenuBridgePreview(
                  visible: visible,
                  onDismiss: () {},
                  notice: notice,
                ),
                suite,
              );
            },
          ),
        );
        await t.pump();
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(t.getCenter(find.byKey(closeKey)));
        await t.pump();
        await t.pump(const Duration(milliseconds: 800));
        await t.pump(const Duration(milliseconds: 200));
        expect(nativeViewportMenus.value, baseline + 1);
        update(() => visible = false);
        await t.pump();
        await t.pump();
        expect(find.byKey(closeKey), findsNothing);
        expect(find.text('关闭'), findsNothing);
        expect(nativeViewportMenus.value, baseline);
        expect(t.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await detach(t);
      }
      expect(nativeViewportMenus.value, baseline);
    });
    testWidgets('$suite shown notice hint owns a native viewport lease', (
      t,
    ) async {
      final baseline = nativeViewportMenus.value;
      final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await t.pumpWidget(
          host(
            const SizedBox(width: 360, child: MenuNoticeBanner(notice: notice)),
            suite,
          ),
        );
        await t.pump();
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(t.getCenter(find.byKey(closeKey)));
        await t.pump();
        await t.pump(const Duration(milliseconds: 800));
        await t.pump(const Duration(milliseconds: 200));
        expect(find.text('关闭'), findsOneWidget);
        expect(nativeViewportMenus.value, baseline + 1);
      } finally {
        await mouse.removePointer();
        await detach(t);
      }
      expect(nativeViewportMenus.value, baseline);
    });
  }
}
