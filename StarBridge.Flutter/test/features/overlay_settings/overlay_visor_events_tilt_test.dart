import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_events_sample.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_layout.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_projection.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_editor_state.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_fixed_previews.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_layout_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';

import '../friends/social_layout_test.dart' show app, size;
import 'overlay_visor_layout_test.dart' show defaults, visor;

/// 11-11 user: the events block follows the most events at once ("跟用户选择的
/// 最大同时事件挂钩") and the editors show the visor's lean ("要用同样的3d效果").
void main() {
  const surface = Size(1920, 1080);
  OverlayWorkspaceSettings visorWith(int events, {double tilt = 15}) => visor()
      .withValue('eventNotificationMaxVisibleCount', events)
      .withValue('visorEventsWidth', 364.0)
      .withValue('visorMembersWidth', 364.0)
      .withValue('visorMembersHeight', 394.0)
      .withValue('visorTilt', tilt);

  // the visor's own events box, measured from its renderer (OverlayVisorRenderer
  // Positions / Sizes) on 1920x1080, medium size, default layout
  const native = {
    1: Rect.fromLTWH(1671.1, 150, 192.9, 48.8),
    3: Rect.fromLTWH(1671.1, 150, 192.9, 123.0),
    5: Rect.fromLTWH(1671.1, 150, 192.9, 197.2),
  };

  for (final MapEntry(key: count, value: box) in native.entries) {
    testWidgets(
      '$count events: the editor box is the visor box with $count rows',
      (tester) async {
        size(tester, surface);
        final s = visorWith(count, tilt: 0);
        expect(
          OverlayVisorLayout.eventsPlacement(defaults(), s, surface),
          rectMoreOrLessEquals(box, epsilon: 0.1),
        );
        await tester.pumpWidget(
          app(
            SizedBox.fromSize(
              size: surface,
              child: OverlayWorkspaceFixedPreviews(
                settings: s,
                layout: defaults(),
                surfaceSize: surface,
                simulate: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final origin = tester.getTopLeft(
          find.byType(OverlayWorkspaceFixedPreviews),
        );
        expect(
          tester
              .getRect(find.byKey(const Key('overlay-runtime-preview-event')))
              .shift(-origin),
          rectMoreOrLessEquals(box, epsilon: 0.1),
        );
        // the editor's simplified panel fills that box (11-12)
        expect(
          find.byKey(const Key('overlay-simulated-structure-Events')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a tilted block is hit where it shows, not on its flat box', (
    tester,
  ) async {
    size(tester, surface);
    final s = visorWith(3);
    final layout = defaults();
    final editor = OverlayWorkspaceEditorState();
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      app(
        SizedBox.fromSize(
          size: surface,
          child: OverlayWorkspaceLayoutWorkbench(
            layout: layout,
            settings: s,
            controller: editor,
            canvasOnly: true,
            showHiddenModules: false,
            showGrid: false,
            onSettingChanged: (_, _) {},
            onChanged: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final members = find.byKey(const Key('overlay-runtime-preview-Members'));
    final box = tester.renderObject<RenderBox>(members);
    final local = box.size;
    // a point inside the shown (leaning) block, left of its flat box: hits
    final inside = box.localToGlobal(Offset(4, local.height / 2));
    final flat = tester.getRect(
      find.ancestor(of: members, matching: find.byType(Positioned)).first,
    );
    expect(inside.dx, lessThan(flat.left), reason: 'the lean moves it out');
    await tester.tapAt(inside);
    await tester.pumpAndSettle();
    expect(editor.selectedKey, 'Members');
    // a point on the flat box's top left corner, above the leaning top: misses
    editor.selectedKey = null;
    await tester.pumpAndSettle();
    final corner = flat.topLeft + const Offset(6, 3);
    final quad = OverlayVisorProjection.quad(
      OverlayVisorLayout.boxOf(layout[2], s, surface, layout),
      right: true,
      degrees: 15,
      surface: surface,
    );
    // in surface pixels the leaning top edge is lower there than the point
    expect(
      quad[0].dy,
      greaterThan(
        3 + OverlayVisorLayout.boxOf(layout[2], s, surface, layout).top,
      ),
    );
    await tester.tapAt(corner);
    await tester.pumpAndSettle();
    expect(editor.selectedKey, isNot('Members'));
  });

  // review CX-VISOR-EVENTS3D-R1: on a leaning block the point grabbed stays
  // under the pointer on screen (the flat block moves by the camera undone)
  // 11-11 viewing distance (视距): the shown block and the drag follow it
  for (final distance in [1000.0, 600.0, 3000.0]) {
    testWidgets(
      'a leaning block follows the pointer one to one (distance $distance)',
      (tester) async {
        size(tester, surface);
        var s = visorWith(
          3,
          tilt: 40,
        ).withValue('visorViewingDistance', distance);
        var layout = defaults();
        final editor = OverlayWorkspaceEditorState();
        addTearDown(editor.dispose);
        Widget workbench() => app(
          SizedBox.fromSize(
            size: surface,
            child: StatefulBuilder(
              builder: (context, setState) => OverlayWorkspaceLayoutWorkbench(
                layout: layout,
                settings: s,
                controller: editor,
                canvasOnly: true,
                showHiddenModules: false,
                showGrid: false,
                onSettingChanged: (field, value) =>
                    setState(() => s = s.withValue(field, value)),
                onChanged: (item, _) => setState(
                  () => layout = [
                    for (final i in layout) i.key == item.key ? item : i,
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(workbench());
        await tester.pumpAndSettle();
        final members = find.byKey(
          const Key('overlay-runtime-preview-Members'),
        );
        final local = Offset(
          20,
          tester.renderObject<RenderBox>(members).size.height / 2,
        );
        final before = tester
            .renderObject<RenderBox>(members)
            .localToGlobal(local);
        // shown where the camera at this distance puts it
        final box = OverlayVisorLayout.boxOf(layout[2], s, surface, layout);
        final shownLeft = tester
            .renderObject<RenderBox>(members)
            .localToGlobal(Offset(0, box.height / 2));
        final want = OverlayVisorProjection.point(
          Offset(box.left, box.center.dy),
          right: true,
          degrees: 40,
          surface: surface,
          distance: distance,
        );
        expect(shownLeft.dx, closeTo(want.dx, 1));
        final drag = await tester.startGesture(before);
        await drag.moveBy(const Offset(0, 140));
        await drag.moveBy(const Offset(0, 140));
        await drag.up();
        await tester.pumpAndSettle();
        final after = tester
            .renderObject<RenderBox>(members)
            .localToGlobal(local);
        // the visor snaps within 12
        expect(after.dy - before.dy, closeTo(280, 13));
        expect((after.dx - before.dx).abs(), lessThan(13));
      },
    );
  }

  // review CX-VISOR-EVENTS3D-R1: the events change side where the pointer
  // crosses the middle of the screen, whatever the lean
  testWidgets('leaning events change side at the middle of the screen', (
    tester,
  ) async {
    size(tester, surface);
    var s = visorWith(3);
    final layout = defaults();
    Widget workbench() => app(
      SizedBox.fromSize(
        size: surface,
        child: StatefulBuilder(
          builder: (context, setState) => OverlayWorkspaceLayoutWorkbench(
            layout: layout,
            settings: s,
            canvasOnly: true,
            showHiddenModules: false,
            showGrid: false,
            onSettingChanged: (_, _) {},
            onChanged: (_, _) {},
            onEventNotificationPlacement: (side, y, {x}) => setState(
              () => s = s
                  .withValue('eventNotificationSide', side)
                  .withValue('eventNotificationY', y)
                  .withValue('visorEventsX', x ?? -1.0),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(workbench());
    await tester.pumpAndSettle();
    final events = find.byKey(const Key('overlay-runtime-preview-event'));
    final box = tester.renderObject<RenderBox>(events);
    // grabbed at its middle: the block's centre decides the side (11-12,
    // the events may sit anywhere)
    final grab = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    final canvas = tester.getRect(find.byType(OverlayWorkspaceFixedPreviews));
    final drag = await tester.startGesture(grab);
    // just short of the middle: still right; just past it: left
    await drag.moveTo(Offset(canvas.center.dx + 6, grab.dy));
    await tester.pump();
    expect(s['eventNotificationSide'], 'Right');
    await drag.moveTo(Offset(canvas.center.dx - 6, grab.dy));
    await tester.pump();
    expect(s['eventNotificationSide'], 'Left');
    await drag.up();
  });

  testWidgets('sample events take the text and decoration opacities apart', (
    tester,
  ) async {
    Future<double> barAlpha(double text, double decoration) async {
      await tester.pumpWidget(
        app(
          SizedBox(
            width: 200,
            height: 200,
            child: OverlayVisorEventsSample(
              count: 1,
              right: true,
              unit: .53,
              textOpacity: text,
              decorationOpacity: decoration,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widget<ColoredBox>(
            find
                .descendant(
                  of: find.byKey(
                    const Key('overlay-visor-events-sample-row-0'),
                  ),
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color
          .a;
    }

    expect(await barAlpha(1, 0), 0, reason: 'decoration off: no bar');
    expect(await barAlpha(0, 1), greaterThan(0), reason: 'text off: bar kept');
  });

  // review CX-VISOR-EVENTS3D-R2: across the middle the lean turns; the block
  // is placed from where the pointer is, so the grabbed point stays under it
  testWidgets(
    'a leaning block dragged across the middle stays under the pointer',
    (tester) async {
      size(tester, surface);
      var s = visorWith(3);
      var layout = defaults();
      Widget workbench() => app(
        SizedBox.fromSize(
          size: surface,
          child: StatefulBuilder(
            builder: (context, setState) => OverlayWorkspaceLayoutWorkbench(
              layout: layout,
              settings: s,
              canvasOnly: true,
              showHiddenModules: false,
              showGrid: false,
              onSettingChanged: (_, _) {},
              onChanged: (item, _) => setState(
                () => layout = [
                  for (final i in layout) i.key == item.key ? item : i,
                ],
              ),
              onEventNotificationPlacement: (side, y, {x}) => setState(
                () => s = s
                    .withValue('eventNotificationSide', side)
                    .withValue('eventNotificationY', y)
                    .withValue('visorEventsX', x ?? -1.0),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(workbench());
      await tester.pumpAndSettle();
      final canvas = tester.getRect(find.byType(OverlayWorkspaceFixedPreviews));
      for (final key in const [
        'overlay-runtime-preview-Members',
        'overlay-runtime-preview-event',
      ]) {
        final block = find.byKey(Key(key));
        final grab = Offset(
          30,
          tester.renderObject<RenderBox>(block).size.height / 2,
        );
        final start = tester.renderObject<RenderBox>(block).localToGlobal(grab);
        final end = Offset(canvas.left + canvas.width * .3, start.dy + 60);
        final drag = await tester.startGesture(start);
        for (var i = 1; i <= 12; i++) {
          await drag.moveTo(Offset.lerp(start, end, i / 12)!);
          await tester.pump();
        }
        await drag.up();
        await tester.pumpAndSettle();
        final now = tester.renderObject<RenderBox>(block).localToGlobal(grab);
        // the visor snaps within 12 surface pixels; the events stay against a
        // screen edge, so only their height follows the pointer
        final off = key.endsWith('event')
            ? (now.dy - end.dy).abs()
            : (now - end).distance;
        expect(off, lessThan(14), reason: '$key: $now vs $end');
      }
      expect(s['eventNotificationSide'], 'Left');
    },
  );
}
