import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_members_size.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_editor_overlay.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_projection.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';

import '../friends/social_layout_test.dart' show app, size;
import 'overlay_visor_layout_test.dart' show visor, shipped, surface;

void main() {
  final settings = visor().withValue('showEventNotifications', false);
  final member = shipped('Members');
  final box = OverlayVisorLayout.boxOf(member, settings, surface);
  OverlayMembersResize resize(OverlayMembersHandle handle) =>
      OverlayMembersResize(member, settings, box, surface, handle);

  test('edges change only their axis; inner corner changes both', () {
    final bottom = resize(OverlayMembersHandle.bottom)
        .at(const Offset(-53, 26.5));
    expect(bottom.width, 364);
    expect(bottom.height, 444);
    expect(bottom.box.top, box.top);
    expect(bottom.box.bottom - box.bottom, closeTo(26.5, .01));
    final side = resize(OverlayMembersHandle.side).at(const Offset(-53, 26.5));
    expect(side.width, 464);
    expect(side.height, 394);
    expect(side.box.right, box.right);
    final corner = resize(OverlayMembersHandle.bottomCorner)
        .at(const Offset(-53, 26.5));
    expect((corner.width, corner.height), (464, 444));
    expect(corner.box.topRight, box.topRight);
  });

  test(
    'centred default saves the fixed opposite edge; all sizes and scales',
    () {
      expect(OverlayVisorLayout.membersAnchor(member, surface), (true, 0));
      for (final preset in ['Small', 'Medium', 'Large']) {
        for (final screen in [surface, const Size(2560, 1440)]) {
          final initial = settings.withValue('visorSize', preset);
          final before = OverlayVisorLayout.boxOf(member, initial, screen);
          for (final handle in [
            OverlayMembersHandle.top,
            OverlayMembersHandle.bottom,
          ]) {
            final delta = handle == OverlayMembersHandle.top ? -17.0 : 17.0;
            final next = OverlayMembersResize(
              member,
              initial,
              before,
              screen,
              handle,
            ).at(Offset(0, delta));
            final saved = initial.withValue('visorMembersHeight', next.height);
            final after = OverlayVisorLayout.boxOf(next.item, saved, screen);
            expect(OverlayVisorLayout.unmoved(next.item, screen), isFalse);
            if (handle == OverlayMembersHandle.bottom) {
              expect(after.top, closeTo(before.top, .01));
              expect(after.bottom - before.bottom, closeTo(delta, .6));
            } else {
              expect(after.bottom, closeTo(before.bottom, .01));
              expect(after.top - before.top, closeTo(delta, .6));
            }
          }
        }
      }
    },
  );

  test('limits saturate without moving the opposite edge', () {
    final gesture = resize(OverlayMembersHandle.bottomCorner);
    final large = gesture.at(const Offset(-10000, 10000));
    final larger = gesture.at(const Offset(-20000, 20000));
    expect(
      (large.width, large.height),
      (OverlayMembersSize.width.maximum, OverlayMembersSize.height.maximum),
    );
    expect(larger.box, large.box);
    final small = gesture.at(const Offset(10000, -10000));
    expect(
      (small.width, small.height),
      (OverlayMembersSize.width.minimum, OverlayMembersSize.height.minimum),
    );
    expect(gesture.at(const Offset(20000, -20000)).box, small.box);
    expect(large.box.topRight, box.topRight);
    expect(small.box.topRight, box.topRight);
  });

  test('left anchored side and corners preserve the left edge', () {
    final leftBox = Rect.fromLTWH(100, 300, box.width, box.height);
    final left = OverlayVisorLayout.save(member, leftBox, surface);
    for (final handle in [
      OverlayMembersHandle.side,
      OverlayMembersHandle.topCorner,
      OverlayMembersHandle.bottomCorner,
    ]) {
      final gesture = OverlayMembersResize(
        left,
        settings,
        leftBox,
        surface,
        handle,
      );
      final next = gesture.at(const Offset(26.5, 10));
      expect(gesture.right, isFalse);
      expect(next.width, 414);
      expect(next.box.left, leftBox.left);
      expect(next.item.horizontalAnchor, 'Left');
      final saved = settings
          .withValue('visorMembersWidth', next.width)
          .withValue('visorMembersHeight', next.height);
      expect(
        OverlayVisorLayout.boxOf(next.item, saved, surface).left,
        leftBox.left,
      );
    }
  });

  test('screen boundary stops growth without translating opposite edge', () {
    final nearBottom = Rect.fromLTWH(
      1500,
      surface.height - box.height - 20,
      box.width,
      box.height,
    );
    final item = OverlayVisorLayout.save(member, nearBottom, surface);
    final next = OverlayMembersResize(
      item,
      settings,
      nearBottom,
      surface,
      OverlayMembersHandle.bottom,
    ).at(const Offset(0, 1000));
    expect(next.box.top, nearBottom.top);
    expect(
      next.box.bottom,
      lessThanOrEqualTo(surface.height - OverlayVisorLayout.screenMargin),
    );
  });

  test('release uses existing collision clearing', () {
    final startBox = Rect.fromLTWH(1300, 400, box.width, box.height);
    final moved = OverlayVisorLayout.save(member, startBox, surface);
    final next = OverlayMembersResize(
      moved,
      settings,
      startBox,
      surface,
      OverlayMembersHandle.bottom,
    ).at(const Offset(0, 40));
    final saved = settings.withValue('visorMembersHeight', next.height);
    final chat = OverlayVisorLayout.save(
      shipped('Chat'),
      Rect.fromLTWH(1300, next.box.bottom - 30, box.width, 104),
      surface,
    );
    final dropped = OverlayVisorLayout.drop(
      next.item,
      [next.item, chat],
      saved,
      surface,
    );
    expect(dropped, isNotNull);
    final after = OverlayVisorLayout.boxOf(dropped!, saved, surface);
    final other = OverlayVisorLayout.boxOf(chat, saved, surface);
    expect(after.overlaps(other), isFalse);
  });

  for (final right in [true, false]) {
    testWidgets('handles face inward: right=$right; drag label and one start', (
      tester,
    ) async {
      size(tester, surface);
      // flat (0 degrees): the handles stay on the flat box as before; the
      // leaning cases are below
      var current = settings.withValue('visorTilt', 0.0);
      var item = right
          ? member
          : OverlayVisorLayout.save(
              member,
              Rect.fromLTWH(100, 300, box.width, box.height),
              surface,
            );
      var starts = 0;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) => OverlayVisorEditorOverlay(
              layout: [item],
              settings: current,
              surface: surface,
              guides: const [],
              guideColor: Colors.cyan,
              warningColor: Colors.red,
              onGestureStart: () => starts++,
              onMembersResized: (width, height, next) => setState(() {
                current = current
                    .withValue('visorMembersWidth', width)
                    .withValue('visorMembersHeight', height);
                item = next;
              }),
            ),
          ),
        ),
      );
      await tester.pump();
      final side = right ? 'left' : 'right';
      final fixed = right ? 'right' : 'left';
      expect(
        find.byKey(Key('overlay-visor-members-resize-$side')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('overlay-visor-members-resize-$fixed')),
        findsNothing,
      );
      for (final edge in ['top', 'bottom', 'top-$side', 'bottom-$side']) {
        expect(
          find.byKey(Key('overlay-visor-members-resize-$edge')),
          findsOneWidget,
        );
      }
      final before = OverlayVisorLayout.boxOf(item, current, surface);
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const Key('overlay-visor-members-resize-bottom')),
        ),
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      final rows = OverlayMembersSize.rows(
        OverlayVisorLayout.membersHeight(current),
      );
      final width = OverlayVisorLayout.membersWidth(current).round();
      final after = OverlayVisorLayout.boxOf(item, current, surface);
      expect(after.top, closeTo(before.top, .01));
      expect(after.bottom - before.bottom, closeTo(50, .6));
      expect(find.text('高 $rows 行 · 宽 $width'), findsOneWidget);
      expect(starts, 1);
      await gesture.up();
      await tester.pump();
      expect(
        find.byKey(const Key('overlay-visor-members-size-label')),
        findsNothing,
      );
    });
  }

  testWidgets('locked or hidden members have no handles', (tester) async {
    for (final locked in [true, false]) {
      await tester.pumpWidget(
        app(
          OverlayVisorEditorOverlay(
            layout: [member.copyWith(isLocked: locked)],
            settings: settings.withValue('showMembers', locked),
            surface: surface,
            guides: const [],
            guideColor: Colors.cyan,
            warningColor: Colors.red,
            onMembersResized: (_, _, _) => fail('locked resize'),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'overlay-visor-members-resize-',
              ),
        ),
        findsNothing,
      );
    }
  });

  // 11-15 user screenshot ("15度 右边"): the handles sat on the flat box beside
  // the tilted panel. Leaning, they sit on the shown panel and a drag moves the
  // shown edge one to one with the pointer.
  for (final degrees in [0.0, 15.0, 60.0]) {
    for (final right in [true, false]) {
      testWidgets('handles on the shown panel: $degrees deg, right=$right', (
        tester,
      ) async {
        size(tester, surface);
        var current = settings.withValue('visorTilt', degrees);
        var item = right
            ? member
            : OverlayVisorLayout.save(
                member,
                Rect.fromLTWH(100, 300, box.width, box.height),
                surface,
              );
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (context, setState) => OverlayVisorEditorOverlay(
                layout: [item],
                settings: current,
                surface: surface,
                guides: const [],
                guideColor: Colors.cyan,
                warningColor: Colors.red,
                onMembersResized: (width, height, next) => setState(() {
                  current = current
                      .withValue('visorMembersWidth', width)
                      .withValue('visorMembersHeight', height);
                  item = next;
                }),
              ),
            ),
          ),
        );
        await tester.pump();
        final lean = OverlayVisorProjection.tilts(
          [item],
          current,
          surface,
        )['Members'];
        expect(lean, right, reason: 'the members lean to their side');
        List<Offset> shownCorners() => OverlayVisorProjection.quad(
          OverlayVisorLayout.boxOf(item, current, surface),
          right: right,
          degrees: degrees,
          surface: surface,
          distance: OverlayVisorProjection.distance(current),
        );
        final q =
            shownCorners(); // top left, top right, bottom right, bottom left
        final side = right ? 'left' : 'right';
        final sideTop = right ? q[0] : q[1];
        final sideBottom = right ? q[3] : q[2];
        Offset centre(String name) => tester.getCenter(
          find.byKey(Key('overlay-visor-members-resize-$name')),
        );
        void near(Offset actual, Offset expected, String what) {
          expect(
            (actual - expected).distance,
            lessThan(1.0),
            reason: '$what: $actual vs $expected',
          );
        }

        near(centre('top-$side'), sideTop, 'top corner');
        near(centre('bottom-$side'), sideBottom, 'bottom corner');
        near(centre('top'), (q[0] + q[1]) / 2, 'top edge');
        near(centre('bottom'), (q[3] + q[2]) / 2, 'bottom edge');
        final sideRect = tester.getRect(
          find.byKey(Key('overlay-visor-members-resize-$side')),
        );
        expect(sideRect.center.dx, closeTo(sideTop.dx, 1.0));
        expect(sideRect.top, closeTo(sideTop.dy, 1.0));
        expect(sideRect.bottom, closeTo(sideBottom.dy, 1.0));
        if (degrees > 0) {
          final flat = OverlayVisorLayout.boxOf(item, current, surface);
          expect(
            (sideTop.dx - (right ? flat.left : flat.right)).abs(),
            greaterThan(1.0),
            reason: 'the case really leans: shown and flat corners differ',
          );
        }

        // the top edge grabbed a quarter of the way along (not its centre) and
        // dragged straight up: that point of the shown edge stays under the
        // pointer, on the slanting edge's own band (review
        // CX-HANDLES-PROJ-073-R1 P2/P3)
        final along = Offset.lerp(q[0], q[1], right ? .25 : .75)!;
        final grabbed = OverlayVisorProjection.unproject(
          along,
          right: right,
          degrees: degrees,
          surface: surface,
          distance: OverlayVisorProjection.distance(current),
        );
        final lift = await tester.startGesture(along);
        await lift.moveBy(const Offset(3, -10));
        await tester.pump();
        await lift.moveBy(const Offset(-3, -10));
        await tester.pump();
        near(
          OverlayVisorProjection.point(
            Offset(
              grabbed.dx,
              OverlayVisorLayout.boxOf(item, current, surface).top,
            ),
            right: right,
            degrees: degrees,
            surface: surface,
            distance: OverlayVisorProjection.distance(current),
          ),
          along + const Offset(0, -20),
          'top edge point under the pointer',
        );
        await lift.up();
        await tester.pump();

        // a drag on the inner bottom corner: the shown corner follows the
        // pointer one to one on both axes
        final before = shownCorners();
        final corner = right ? before[3] : before[2];
        final outward = right ? -40.0 : 40.0;
        final gesture = await tester.startGesture(corner);
        await gesture.moveBy(Offset(outward / 2, 15));
        await tester.pump();
        await gesture.moveBy(Offset(outward / 2, 15));
        await tester.pump();
        final after = shownCorners();
        near(
          right ? after[3] : after[2],
          corner + Offset(outward, 30),
          'dragged corner under the pointer',
        );
        near(
          right ? after[1] : after[0],
          right ? before[1] : before[0],
          'the fixed top corner stays',
        );
        await gesture.up();
        await tester.pump();
      });
    }
  }

  // review CX-HANDLES-PROJ-073-R1 P2: a corner held at a width limit while the
  // pointer goes on sideways keeps its height and place
  for (final degrees in [15.0, 60.0]) {
    for (final right in [true, false]) {
      testWidgets('corner at the width limit: $degrees deg, right=$right', (
        tester,
      ) async {
        size(tester, surface);
        final live = _Live(settings.withValue('visorTilt', degrees), right);
        await tester.pumpWidget(app(live.overlay()));
        await tester.pump();
        final start = live.shown();
        final corner = right ? start[3] : start[2];
        final out = right ? -1.0 : 1.0;
        final gesture = await tester.startGesture(corner);
        for (var i = 0; i < 4; i++) {
          await gesture.moveBy(Offset(out * 300, 0));
          await tester.pump();
        }
        final width = OverlayVisorLayout.membersWidth(live.current);
        expect(width, OverlayMembersSize.width.maximum.toDouble());
        final held = live.shown();
        final heldCorner = right ? held[3] : held[2];
        // the height may follow the pointer's shown height on the way out (the
        // corner keeps the pointer's screen height); at the limit it stops
        final heldHeight = OverlayVisorLayout.membersHeight(live.current);
        await gesture.moveBy(Offset(out * 200, 0));
        await tester.pump();
        await gesture.moveBy(Offset(-out * 100, 0));
        await tester.pump();
        final later = live.shown();
        expect(
          ((right ? later[3] : later[2]) - heldCorner).distance,
          lessThan(1.0),
          reason: 'the corner stays put at the limit',
        );
        expect(
          OverlayVisorLayout.membersHeight(live.current),
          closeTo(heldHeight, .6),
          reason: 'a sideways drag at the limit leaves the height',
        );
        await gesture.up();
        await tester.pump();
      });
    }
  }

  // the canvas zoomed to half: handles and drags still follow the shown panel
  testWidgets('handles on the shown panel of a half-size canvas', (
    tester,
  ) async {
    size(tester, surface);
    final live = _Live(settings.withValue('visorTilt', 15.0), true);
    await tester.pumpWidget(
      app(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: surface.width / 2,
            height: surface.height / 2,
            child: live.overlay(),
          ),
        ),
      ),
    );
    await tester.pump();
    final start = live.shown();
    final corner = start[3] / 2;
    expect(
      (tester.getCenter(
                find.byKey(
                  const Key('overlay-visor-members-resize-bottom-left'),
                ),
              ) -
              corner)
          .distance,
      lessThan(1.0),
    );
    final gesture = await tester.startGesture(corner);
    await gesture.moveBy(const Offset(-10, 8));
    await tester.pump();
    await gesture.moveBy(const Offset(-10, 7));
    await tester.pump();
    expect(
      (live.shown()[3] / 2 - (corner + const Offset(-20, 15))).distance,
      lessThan(1.0),
    );
    await gesture.up();
    await tester.pump();
  });
}

/// A members editor overlay that keeps what it saves (surface 1920 x 1080).
final class _Live {
  _Live(this.current, this.right)
    : item = right
          ? shipped('Members')
          : OverlayVisorLayout.save(
              shipped('Members'),
              Rect.fromLTWH(
                100,
                300,
                OverlayVisorLayout.boxOf(
                  shipped('Members'),
                  current,
                  surface,
                ).width,
                OverlayVisorLayout.boxOf(
                  shipped('Members'),
                  current,
                  surface,
                ).height,
              ),
              surface,
            );
  final bool right;
  OverlayWorkspaceSettings current;
  OverlayWorkspaceLayoutItem item;

  Widget overlay() => StatefulBuilder(
    builder: (context, setState) => OverlayVisorEditorOverlay(
      layout: [item],
      settings: current,
      surface: surface,
      guides: const [],
      guideColor: Colors.cyan,
      warningColor: Colors.red,
      onMembersResized: (width, height, next) => setState(() {
        current = current
            .withValue('visorMembersWidth', width)
            .withValue('visorMembersHeight', height);
        item = next;
      }),
    ),
  );

  /// The shown corners: top left, top right, bottom right, bottom left.
  List<Offset> shown() => OverlayVisorProjection.quad(
    OverlayVisorLayout.boxOf(item, current, surface),
    right: right,
    degrees: OverlayVisorProjection.degrees(current),
    surface: surface,
    distance: OverlayVisorProjection.distance(current),
  );
}
