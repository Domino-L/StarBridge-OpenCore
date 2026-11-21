import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_arrange.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_editor_overlay.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_layout.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_visor_overlap_warning.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_layout_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_editor_state.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_inspector.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_layout_geometry.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts, capture;
import 'overlay_appearance_live_session_test.dart' show settings;

// 11-06 free visor positions (user: "可以像现在一样自由调整吗"; size stays S/M/L).
// Same rules as StarBridge.Core OverlayVisorPlacement / OverlayVisorLayout.
const surface = Size(1920, 1080);

OverlayWorkspaceSettings visor({String side = 'Right', double y = 0.34}) =>
    settings()
        .withValue('skin', 'Visor')
        .withValue('visorSize', 'Medium')
        .withValue('eventNotificationSide', side)
        .withValue('eventNotificationY', y)
        .withValue('showMembers', true)
        .withValue('showChat', true)
        .withValue('showEventNotifications', true)
        .withValue('showNotice', true);

OverlayWorkspaceLayoutItem shipped(String key) =>
    OverlayWorkspaceLayoutGeometry.resetPosition(
      OverlayWorkspaceLayoutItem(
        key: key,
        x: 0,
        y: 0,
        width: .1,
        height: .1,
        horizontalAnchor: 'Left',
        verticalAnchor: 'Top',
        isLocked: false,
        textOpacity: 1,
        backgroundOpacity: .6,
      ),
      'default',
    );

List<OverlayWorkspaceLayoutItem> defaults() => [
  for (final key in ['Notice', 'Squads', 'Members', 'Chat']) shipped(key),
];

// The build 72 acceptance machine: members moved to the left edge, ending
// just above where the untouched chat's visor default sits.
OverlayWorkspaceLayoutItem movedMembers() => shipped('Members').copyWith(
  x: 0,
  y: .525,
  width: .1327,
  height: .2,
  horizontalAnchor: 'Left',
  verticalAnchor: 'Middle',
);

// The m102 default preset (members 12 rows, events at 0.254) with [count]
// events at most.
OverlayWorkspaceSettings presetVisor(int count) =>
    visor(y: 0.254)
        .withValue('visorMembersHeight', 554.0)
        .withValue('eventNotificationMaxVisibleCount', count);

// Members the user dragged high against the right edge (top at y 260), saved
// the way the editors save a drop.
List<OverlayWorkspaceLayoutItem> highMembers() => [
  for (final i in defaults())
    i.key == 'Members'
        ? OverlayVisorLayout.save(
            i,
            Rect.fromLTWH(1920 - 56 - 364 * 0.53, 260, 364 * 0.53, 554 * 0.53),
            surface,
          )
        : i,
];

void main() {
  // m102 (11-18 user: "12 人", "这个不是往下延长吗", "事件如果要向下和成员重叠时，
  // 应该自己向上避开", "如果无视就允许重叠"): the default preset's members keep
  // their top and grow down; its events sit above them and grow up; past the
  // top of their column they overlap and the editors warn
  test('the default preset: members grow down, events give way up', () {
    for (final count in [3, 4, 5]) {
      final s = presetVisor(count);
      final boxes = OverlayVisorArrange.all(defaults(), s, surface);
      final members = boxes['Members']!, events = boxes['Events']!;
      expect(members.top, closeTo(OverlayVisorLayout.rightMidTop, 0.5));
      expect(members.top, closeTo(385.6, 0.5), reason: '$count events');
      expect(members.height, closeTo(554 * 0.53, 0.5));
      expect(members.bottom, lessThan(790), reason: 'above the key hints');
      expect(
        events.bottom + OverlayVisorLayout.gap,
        closeTo(members.top, 0.5),
        reason: '$count events sit just above the members',
      );
      expect(events.top, greaterThanOrEqualTo(150), reason: 'under the icons');
      expect(events.overlaps(members), isFalse);
      expect(events.right, closeTo(members.right, 0.5));
      expect(OverlayVisorArrange.eventsOverlap(defaults(), s, surface), isNull);
    }
    // members the user dragged high: the events go no higher than 150 and
    // overlap them; the members stay; the editors warn
    final high = highMembers();
    final s = presetVisor(5);
    final boxes = OverlayVisorArrange.all(high, s, surface);
    expect(boxes['Members']!.top, closeTo(260, 1));
    expect(boxes['Events']!.top, closeTo(150, 0.5));
    final overlap = OverlayVisorArrange.eventsOverlap(high, s, surface);
    expect(overlap, isNotNull);
    expect(overlap!.top, closeTo(260, 1));
    expect(overlap.bottom, closeTo(150 + (22 + 5 * 70) * 0.53, 0.5));
  });

  testWidgets('the editors warn where the events and the members overlap', (
    tester,
  ) async {
    size(tester, surface);
    expect(
      OverlayVisorOverlapWarning.forLayout(
        layout: defaults(),
        settings: presetVisor(5),
        surface: surface,
      ),
      isNull,
      reason: 'the default preset never overlaps',
    );
    await tester.pumpWidget(
      app(
        SizedBox.fromSize(
          size: surface,
          child: Stack(
            children: [
              ?OverlayVisorOverlapWarning.forLayout(
                layout: highMembers(),
                settings: presetVisor(5),
                surface: surface,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overlay-visor-overlap-warning')),
      findsOneWidget,
    );
    expect(find.text('事件和成员会重叠'), findsOneWidget);
    expect(find.textContaining('事件最多 5 条时放不下'), findsOneWidget);
    expect(find.textContaining('不改也可以保存'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('blocks are shown as the visor arranges them: never on top of each '
      'other, the user\'s block stays', () {
    final s = visor();
    final layout = [
      for (final i in defaults()) i.key == 'Members' ? movedMembers() : i,
    ];
    final own = {
      for (final key in ['Members', 'Chat'])
        key: OverlayVisorLayout.boxOf(
          layout.firstWhere((i) => i.key == key),
          s,
          surface,
        ),
    };
    expect(
      own['Members']!.overlaps(own['Chat']!),
      isTrue,
      reason: 'the case from the acceptance screenshot',
    );
    final shown = OverlayVisorLayout.arrange(layout, s, surface);
    // review R5: kept on screen like the visor does (8 from the edge)
    expect(
      shown['Members'],
      OverlayVisorLayout.onScreen(own['Members']!, surface),
      reason: 'the user\'s block stays',
    );
    expect(shown['Chat']!.overlaps(shown['Members']!), isFalse);
    expect(shown['Chat']!.left, own['Chat']!.left, reason: 'only up or down');
    expect(
      shown['Chat']!.top,
      closeTo(own['Members']!.bottom + OverlayVisorLayout.gap, 0.5),
      reason: 'the shorter way: just below the members',
    );
    expect(
      OverlayVisorLayout.boxOf(layout[3], s, surface, layout),
      shown['Chat'],
      reason: 'the editor draws the chat there',
    );
    // both placed by the user and overlapping: members stay, chat moves
    final chat = OverlayVisorLayout.save(layout[3], own['Members']!, surface);
    final both = OverlayVisorLayout.arrange([movedMembers(), chat], s, surface);
    expect(
      both['Members'],
      OverlayVisorLayout.onScreen(own['Members']!, surface),
    );
    expect(both['Chat']!.overlaps(both['Members']!), isFalse);
    // a hidden block takes no room
    expect(
      OverlayVisorLayout.arrange(
        layout,
        s.withValue('showMembers', false),
        surface,
      ).keys,
      ['Chat'],
    );
  });

  test('untouched modules show the visor defaults', () {
    final s = visor();
    final team = OverlayVisorLayout.boxOf(shipped('Members'), s, surface);
    expect(
      team.right,
      closeTo(1920 - 56, 0.5),
      reason: 'members on the right edge',
    );
    // 11-07: the members box is its size setting (364 design units by default)
    expect(team.width, closeTo(364 * OverlayVisorLayout.designUnit, 0.5));
    final chat = OverlayVisorLayout.boxOf(shipped('Chat'), s, surface);
    expect(chat.left, closeTo(56, 0.5), reason: 'chat on the lower left');
    expect(chat.top, greaterThan(600));
    expect(
      OverlayVisorLayout.eventDisplayY(s, surface) * (1080 - 90),
      closeTo(150, 0.5),
      reason: 'untouched events show at the top of the right column',
    );
    expect(OverlayVisorLayout.eventDisplayY(visor(y: 0.6), surface), 0.6);
  });

  test('a saved block comes back exactly where it was dropped', () {
    final s = visor();
    for (final key in ['Members', 'Chat']) {
      final size = OverlayVisorLayout.boxOf(shipped(key), s, surface).size;
      for (final at in const [
        Offset(300, 200),
        Offset(1300, 220),
        Offset(400, 700),
        Offset(1250, 640),
      ]) {
        final box = at & size;
        final saved = OverlayVisorLayout.save(shipped(key), box, surface);
        final back = OverlayVisorLayout.boxOf(saved, s, surface);
        expect(back.left, closeTo(box.left, 0.5), reason: '$key at $at: left');
        expect(back.top, closeTo(box.top, 0.5), reason: '$key at $at: top');
      }
    }
    // Chat's module may not be as short as the visor block; its anchored
    // corner still lands on the block's corner.
    final low =
        Offset(1300, 900) &
        OverlayVisorLayout.boxOf(shipped('Chat'), s, surface).size;
    final saved = OverlayVisorLayout.save(shipped('Chat'), low, surface);
    expect(saved.verticalAnchor, 'Bottom');
    expect(saved.horizontalAnchor, 'Right');
    expect(
      OverlayVisorLayout.boxOf(saved, s, surface).bottomRight,
      offsetMoreOrLessEquals(low.bottomRight, epsilon: 0.5),
    );
  });

  test('snapping aligns one edge and draws a guide; it never blocks', () {
    // A clear spot below the game's heading tape: only the top edge is near a
    // line (the visor's edge margin, 7 units away).
    final box = const Rect.fromLTWH(900, 63, 254, 120);
    final (snapped, guides) = OverlayVisorLayout.snap(box, const [], surface);
    expect(snapped.top, closeTo(56, 0.01), reason: 'the visor edge margin');
    expect(snapped.left, 900, reason: 'only that one edge moves');
    expect(guides.single, (vertical: false, at: 56.0));
    final other = const Rect.fromLTWH(1500, 150, 254, 200);
    final (stacked, _) = OverlayVisorLayout.snap(
      const Rect.fromLTWH(1504, 372, 254, 120),
      [other],
      surface,
    );
    expect(stacked.left, 1500, reason: 'aligned with the block above');
    expect(
      stacked.top,
      150 + 200 + 18,
      reason: 'stacked the visor gap below it',
    );
    final far = const Rect.fromLTWH(900, 500, 254, 120);
    expect(
      OverlayVisorLayout.snap(far, const [], surface).$1,
      far,
      reason: 'free: nothing near, nothing moves',
    );
  });

  test(
    'a block left on another moves just clear of it; off screen comes back',
    () {
      final team = const Rect.fromLTWH(600, 300, 254, 350);
      final dropped = const Rect.fromLTWH(600, 400, 254, 56);
      expect(
        OverlayVisorLayout.clear(dropped, [team], surface).top,
        300 - 18 - 56,
      );
      final out = OverlayVisorLayout.onScreen(
        const Rect.fromLTWH(1900, -50, 254, 350),
        surface,
      );
      expect(out.right, 1920 - 8);
      expect(out.top, 8);
    },
  );

  test('the DM badge: default spot, and a saved spot comes back', () {
    final s = visor();
    final home = OverlayVisorLayout.badgeBox(s, surface);
    expect(home.right, closeTo(1920 - 56, 0.5));
    for (final at in const [Offset(200, 300), Offset(1500, 500)]) {
      final box = at & home.size;
      final (x, y) = OverlayVisorLayout.badgeAt(box, surface);
      final back = OverlayVisorLayout.badgeBox(
        s.withValue('visorBadgeX', x).withValue('visorBadgeY', y),
        surface,
      );
      expect(back.left, closeTo(box.left, 0.5), reason: '$at');
      expect(back.top, closeTo(box.top, 0.5), reason: '$at');
    }
  });

  test('the rally has two spots: top centre and bottom centre', () {
    final s = visor();
    for (final size in const ['Small', 'Medium', 'Large']) {
      final sized = s.withValue('visorSize', size);
      final top = OverlayVisorLayout.rallyBox(
        shipped('Notice'),
        sized,
        surface,
      );
      final bottom = OverlayVisorLayout.rallyBox(
        shipped('Notice').copyWith(verticalAnchor: 'Bottom'),
        sized,
        surface,
      );
      expect(top.center.dx, closeTo(960, 0.5));
      expect(bottom.bottom, closeTo(858, 0.5), reason: size);
      expect(
        OverlayVisorLayout.coversGameHud(bottom, surface),
        isFalse,
        reason: size,
      );
    }
    final docked = OverlayVisorLayout.dockRally(
      shipped('Notice'),
      900,
      surface,
    );
    expect(docked.verticalAnchor, 'Bottom');
    expect(
      OverlayVisorLayout.dockRally(docked, 200, surface).verticalAnchor,
      'Top',
    );
    // review CX-OVERLAY-M102-R1 P2-4: a drag docks at the nearer spot,
    // halfway between the two spots' centres (~469 at medium), not at 540
    final split = OverlayVisorLayout.rallySplit(
      shipped('Notice'),
      visor(),
      surface,
    );
    expect(split, closeTo((113.7 + 824.1) / 2, 0.5));
    expect(
      OverlayVisorLayout.dockRally(
        shipped('Notice'),
        500,
        surface,
        split: split,
      ).verticalAnchor,
      'Bottom',
      reason: '500 is nearer the bottom spot',
    );
  });

  test('only blocks over the game HUD are marked', () {
    expect(
      OverlayVisorLayout.coversGameHud(
        const Rect.fromLTWH(60, 60, 254, 200),
        surface,
      ),
      isTrue,
      reason: 'ship panel',
    );
    expect(
      OverlayVisorLayout.coversGameHud(
        const Rect.fromLTWH(1500, 300, 254, 300),
        surface,
      ),
      isFalse,
    );
  });

  testWidgets(
    'dragging in the editor: free, snapped with a guide, red over the HUD, Alt off',
    (tester) async {
      await tester.runAsync(loadFonts);
      // Review pictures only: a real game screenshot behind the canvas when
      // STARBRIDGE_VISOR_BACKDROP names one (otherwise the plain canvas).
      final path = Platform.environment['STARBRIDGE_VISOR_BACKDROP'];
      Widget? backdrop;
      if (path != null && File(path).existsSync()) {
        final image = MemoryImage(File(path).readAsBytesSync());
        backdrop = Image(image: image, fit: BoxFit.cover);
        await tester.runAsync(() async {
          final completer = Completer<void>();
          image
              .resolve(ImageConfiguration.empty)
              .addListener(ImageStreamListener((_, _) => completer.complete()));
          await completer.future;
        });
      }
      size(tester, const Size(1600, 900));
      var layout = defaults();
      var s = visor();
      final key = GlobalKey();
      Widget editor() => RepaintBoundary(
        key: key,
        child: app(
          SizedBox(
            width: 1600,
            height: 900,
            child: StatefulBuilder(
              builder: (context, setState) => OverlayWorkspaceLayoutWorkbench(
                layout: layout,
                settings: s,
                canvasOnly: true,
                showHiddenModules: false,
                background: backdrop,
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
        ),
      );
      await tester.pumpWidget(editor());
      await tester.pumpAndSettle();
      final members = find.byKey(const Key('overlay-runtime-preview-Members'));
      expect(members, findsOneWidget);
      Rect box() => OverlayVisorLayout.boxOf(
        layout.firstWhere((i) => i.key == 'Members'),
        s,
        surface,
      );
      final start = box();
      // canvas pixels per surface pixel
      final canvas = tester.getSize(
        find.byKey(const Key('overlay-runtime-preview')),
      );
      final sx = canvas.width / 1920, sy = canvas.height / 1080;

      // 1. anywhere: dropped in the middle, it stays there
      final gesture = await tester.startGesture(tester.getCenter(members));
      await gesture.moveBy(const Offset(-400, 60));
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump();
      await capture(tester, key, 'visor-free-1-anywhere');
      await gesture.up();
      await tester.pump();
      expect(
        box().left,
        lessThan(start.left - 300),
        reason: 'the block stays where it was dropped',
      );
      expect(
        layout.firstWhere((i) => i.key == 'Members').horizontalAnchor,
        isNotEmpty,
      );

      // 2. near the left visor margin: snaps and shows the guide while dragging
      final toLeft = await tester.startGesture(tester.getCenter(members));
      await toLeft.moveBy(Offset(-(box().left - 61) * sx, 0));
      await tester.pump();
      // 56: the visor edge margin; 60: the game chat edge; 63: the ladder plus the gap
      expect(
        [56.0, 60.0, 63.0].any((line) => (box().left - line).abs() < 0.5),
        isTrue,
        reason: 'snapped to a line (${box().left})',
      );
      expect(
        find.byKey(const Key('overlay-visor-editor-overlay')),
        findsOneWidget,
      );
      await capture(tester, key, 'visor-free-2-snap-guide');
      await toLeft.up();
      await tester.pump();

      // 3. over the game's ship panel: marked red, still allowed
      final up = await tester.startGesture(tester.getCenter(members));
      await up.moveBy(Offset(0, -(box().top - 40) * sy));
      await up.up();
      await tester.pump();
      expect(
        OverlayVisorLayout.coversGameHud(box(), surface),
        isTrue,
        reason: 'allowed onto the HUD',
      );
      await capture(tester, key, 'visor-free-3-over-hud-red');

      // 4. Alt held: no snapping at the margin
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final alt = await tester.startGesture(tester.getCenter(members));
      await alt.moveBy(Offset((70 - box().left) * sx, (600 - box().top) * sy));
      await tester.pump();
      expect(
        box().left,
        closeTo(70, 1),
        reason: "Alt turns snapping off (63 is in reach)",
      );
      await alt.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();

      // 5. the DM badge is gone (11-13 user: "整个都不要")
      expect(find.byKey(const Key('overlay-visor-badge')), findsNothing);

      // 6. the rally: two fixed spots, it goes to the nearer one
      Rect rally() => OverlayVisorLayout.rallyBox(
        layout.firstWhere((i) => i.key == 'Notice'),
        s,
        surface,
      );
      expect(rally().top, lessThan(120), reason: 'top centre by default');
      final notice = find.byKey(const Key('overlay-runtime-preview-Notice'));
      // 11-18 ("照真实召集的样子"): a sample rally sits in the box
      expect(
        find.descendant(
          of: notice,
          matching: find.byKey(const Key('overlay-visor-rally-sample')),
        ),
        findsOneWidget,
      );
      final docked = tester.getRect(notice);
      await capture(tester, key, 'm102-rally-1-sample');
      Finder slot(String id) => find.byKey(Key('overlay-visor-rally-slot-$id'));
      final down = await tester.startGesture(tester.getCenter(notice));
      await down.moveBy(Offset(-300 * sx, 300 * sy));
      await tester.pump();
      // 11-18 ("框跟着手上下走，松手吸过去"): held, the box follows the pointer
      // up and down only and stays docked until release; both spots show,
      // the nearer one brighter
      final held = tester.getRect(notice);
      expect(held.left, closeTo(docked.left, 1), reason: 'up and down only');
      expect(held.top, closeTo(docked.top + 300 * sy, 2));
      expect(
        layout.firstWhere((i) => i.key == 'Notice').verticalAnchor,
        'Top',
        reason: 'nothing saved while held',
      );
      expect(slot('top-near'), findsOneWidget);
      expect(slot('bottom'), findsOneWidget);
      Finder words(String id) =>
          find.descendant(of: slot(id), matching: find.byType(Text));
      // clear of both spots: both say what they are
      expect(words('top-near'), findsOneWidget);
      expect(words('bottom'), findsOneWidget);
      await capture(tester, key, 'm102-rally-2-held-near-top');
      await down.moveBy(Offset(0, 400 * sy));
      await tester.pump();
      expect(slot('bottom-near'), findsOneWidget);
      expect(slot('top'), findsOneWidget);
      // 11-18 (说明第 2 节): the box covers most of the bottom spot, whose words
      // would read through the sample: only its outline shows; the top says
      // "顶部"
      expect(words('bottom-near'), findsNothing);
      expect(words('top'), findsOneWidget);
      await capture(tester, key, 'm102-rally-3-held-near-bottom');
      await down.up();
      await tester.pump();
      expect(
        layout.firstWhere((i) => i.key == 'Notice').verticalAnchor,
        'Bottom',
      );
      expect(rally().center.dx, closeTo(960, 0.5), reason: 'still centred');
      expect(
        rally().bottom,
        closeTo(858, 0.5),
        reason: 'just above the speed readout',
      );
      expect(OverlayVisorLayout.coversGameHud(rally(), surface), isFalse);
      await capture(tester, key, 'visor-free-5-rally-bottom');

      // m102 review pictures: the default preset with 3 and 5 events, and the
      // overlap warning with the members dragged high
      for (final count in [3, 5]) {
        layout = defaults();
        s = presetVisor(count);
        await tester.pumpWidget(editor());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('overlay-visor-overlap-warning')),
          findsNothing,
        );
        await capture(tester, key, 'm102-default-$count-events');
      }
      layout = highMembers();
      s = presetVisor(5);
      await tester.pumpWidget(editor());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('overlay-visor-overlap-warning')),
        findsOneWidget,
      );
      await capture(tester, key, 'm102-overlap-warning');
      await tester.pumpWidget(const SizedBox());
    },
  );

  // build 72 acceptance: the overview block sat under the visor's members
  // block, and the members block still offered width and height controls.
  testWidgets(
    'full-screen editor with the visor: no overview block, position only',
    (tester) async {
      await tester.runAsync(loadFonts);
      size(tester, const Size(1920, 1080));
      // the acceptance machine's layout: members moved under the overview
      final layout = [
        for (final i in defaults()) i.key == 'Members' ? movedMembers() : i,
      ];
      final key = GlobalKey();
      Future<void> show(OverlayWorkspaceSettings s, String name) async {
        final editor = OverlayWorkspaceEditorState()..selectedKey = 'Members';
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: app(
              OverlayWorkspaceLayoutWorkbench(
                layout: layout,
                settings: s,
                controller: editor,
                fullScreen: true,
                onChanged: (_, _) {},
                onSettingChanged: (_, _) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await capture(tester, key, name);
      }

      Finder byKey(String k) => find.byKey(Key(k));
      const sizeKeys = [
        'overlay-layout-nudge-narrower-Members',
        'overlay-layout-nudge-wider-Members',
        'overlay-layout-nudge-shorter-Members',
        'overlay-layout-nudge-taller-Members',
        'overlay-pixels-Members-width',
        'overlay-pixels-Members-height',
      ];

      await show(visor(), 'build72-visor-members');
      expect(byKey('overlay-layout-module-Squads'), findsNothing);
      expect(byKey('overlay-layout-module-Members'), findsOneWidget);
      expect(
        tester
            .getRect(byKey('overlay-layout-module-Members'))
            .overlaps(tester.getRect(byKey('overlay-layout-module-Chat'))),
        isFalse,
        reason: 'the untouched chat makes way for the moved members',
      );
      for (final k in sizeKeys) {
        expect(byKey(k), findsNothing, reason: k);
      }
      expect(byKey('overlay-pixels-Members-x'), findsOneWidget);
      expect(byKey('overlay-layout-nudge-up-Members'), findsOneWidget);
      expect(find.text('可以调整位置；大小在“全局 → 面罩形态”的“面罩大小”里选'), findsOneWidget);

      // 0.7.3 overlay v2: a saved standard look is shown as the visor too
      await show(
        visor().withValue('skin', 'Default'),
        'build72-standard-members',
      );
      expect(byKey('overlay-layout-module-Squads'), findsNothing);
      for (final k in sizeKeys) {
        expect(byKey(k), findsNothing, reason: k);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('with the visor the overview panel says where it went', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        OverlayWorkspaceLayoutInspector(
          item: shipped('Squads'),
          nudgePixels: 1,
          settings: visor(),
          onChanged: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overlay-layout-visor-overview-Squads')),
      findsOneWidget,
    );
    expect(find.text('面罩投影把舰队总览显示在成员块顶部，跟着成员块走，不单独摆放。'), findsOneWidget);
    expect(
      find.byKey(const Key('overlay-layout-nudge-left-Squads')),
      findsNothing,
    );

    // review picture: the members controls with the visor and with Standard
    await tester.runAsync(loadFonts);
    size(tester, const Size(1500, 760));
    final key = GlobalKey();
    Widget panel(OverlayWorkspaceSettings s) => Expanded(
      child: SingleChildScrollView(
        child: OverlayWorkspaceLayoutInspector(
          item: shipped('Members'),
          nudgePixels: 1,
          settings: s,
          onChanged: (_, _) {},
        ),
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: app(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              panel(visor()),
              panel(visor().withValue('skin', 'Default')),
              Expanded(
                child: OverlayWorkspaceLayoutInspector(
                  item: shipped('Squads'),
                  nudgePixels: 1,
                  settings: visor(),
                  onChanged: (_, _) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, key, 'build72-inspector-visor-standard-overview');
    await tester.pumpWidget(const SizedBox());
  });

  // 11-07 members size: the editor box is the width and height settings (the
  // maximum while adaptive, the fixed size otherwise); its resize corner faces
  // away from the box's anchor, taken when the drag starts (review R3).
  test('the members box follows its size settings and resizes from its free corner', () {
    final members = shipped('Members');
    final base = visor()
        .withValue('visorMembersWidth', 364.0)
        .withValue('visorMembersHeight', 394.0);
    final box = OverlayVisorLayout.boxOf(members, base, surface);
    expect(box.width, closeTo(364 * OverlayVisorLayout.designUnit, 0.01));
    expect(box.height, closeTo(394 * OverlayVisorLayout.designUnit, 0.01));
    expect(box.right, closeTo(surface.width - OverlayVisorLayout.edge, 0.5));
    final bigger = base
        .withValue('visorMembersWidth', 420.0)
        .withValue('visorMembersHeight', 500.0);
    final grown = OverlayVisorLayout.boxOf(members, bigger, surface);
    expect(grown.width, greaterThan(box.width));
    expect(grown.right, closeTo(box.right, 0.5));
    // the shipped members sit on their right slot, centred: dragging the
    // lower-left corner left and down widens them and grows only downward
    final anchor = OverlayVisorLayout.membersAnchor(members, surface);
    expect(anchor, (true, 0));
    final (width, height) = OverlayVisorLayout.resizeMembers(
      base,
      anchor,
      const Offset(-53, 26.5),
      surface,
    );
    expect(width, 464);
    expect(height, 444);
    // a box anchored at its top grows downward by the drag itself
    final (_, topHeight) = OverlayVisorLayout.resizeMembers(
      base,
      (true, -1),
      const Offset(0, 26.5),
      surface,
    );
    expect(topHeight, 444);
    // a box anchored at its bottom grows upward
    final (_, bottomHeight) = OverlayVisorLayout.resizeMembers(
      base,
      (false, 1),
      const Offset(0, -26.5),
      surface,
    );
    expect(bottomHeight, 444);
    // the values stay in range and whole
    final (minWidth, minHeight) = OverlayVisorLayout.resizeMembers(
      base,
      anchor,
      const Offset(900, -900),
      surface,
    );
    expect([minWidth, minHeight], [220, 191]);
    // review R4: the tallest members at the large size keep the right column,
    // as the visor places them (OverlayVisorTests). m102 (11-18 "往下延长"):
    // at the middle slot's top (385.6), below the events' three-line box
    final tallest = visor()
        .withValue('visorSize', 'Large')
        .withValue('visorMembersHeight', 554.0)
        .withValue('showEventNotifications', true)
        // three event lines, as the visor test (the default count)
        .withValue('eventNotificationMaxVisibleCount', 3);
    final placed = OverlayVisorLayout.arrange(
      [shipped('Members'), shipped('Chat')],
      tallest,
      surface,
    )['Members']!;
    expect(placed.top, closeTo(OverlayVisorLayout.rightMidTop, 0.01));
    expect(placed.top, greaterThan(150 + 232 * 0.53 * 1.36 + 18));
    expect(placed.right, closeTo(surface.width - OverlayVisorLayout.edge, 0.5));
    // review R5 (OverlayVisorTests.MovedEvents checks the same numbers):
    // 1. members moved to the left at top 400, events on the left at 0.4: the
    //    members keep their place (the visor moves the events instead)
    const big = Size(2560, 1440);
    final medium = visor().withValue('visorMembersHeight', 394.0);
    final leftTop = OverlayVisorLayout.save(
      shipped('Members'),
      Rect.fromLTWH(
        57.6 / (1080 / 1440),
        400 / (1080 / 1440),
        364 * 0.53 / (1080 / 1440),
        394 * 0.53 / (1080 / 1440),
      ),
      big,
    );
    final kept = OverlayVisorLayout.arrange(
      [leftTop],
      medium
          .withValue('eventNotificationSide', 'Left')
          .withValue('eventNotificationY', 0.4)
          .withValue('showChat', false),
      big,
    )['Members']!;
    expect(kept.top * (1080 / 1440), closeTo(400, 0.5));
    // 2. events on the right at 0.6 at 1440 high: their top is 0.6 x 990 =
    //    594 layout units, just over the default members' bottom. m102
    //    (11-18: the events give way, never the members): the members stay,
    //    the events placed below them move a gap below them
    final low = medium
        .withValue('eventNotificationY', 0.6)
        .withValue('showChat', false)
        .withValue('eventNotificationMaxVisibleCount', 3);
    final stays = OverlayVisorLayout.arrange([shipped('Members')], low, big);
    expect(
      stays['Members']!.top * (1080 / 1440),
      closeTo(OverlayVisorLayout.rightMidTop, 0.5),
    );
    expect(
      OverlayVisorLayout.eventsPlacement([shipped('Members')], low, big)!.top *
          (1080 / 1440),
      closeTo(OverlayVisorLayout.rightMidTop + 394 * 0.53 + 18, 0.5),
    );
    // 11-07 "2放": the chat box is its width setting and its most lines
    // (OverlayVisorDraw.ChatBoxHeight: 22 + lines x 28), as the visor places it
    final chatBox = OverlayVisorLayout.chatBoxSize(
      visor()
          .withValue('visorChatWidth', 300.0)
          .withValue('chatMaxVisibleCount', 2),
    );
    expect(chatBox.width, closeTo(300 * 0.53, 0.01));
    // two lines are shorter than the chat preview's least height (104)
    expect(chatBox.height, closeTo(104, 0.01));
    final tallChat = OverlayVisorLayout.chatBoxSize(
      visor().withValue('chatMaxVisibleCount', 8),
    );
    expect(tallChat.height, closeTo((22 + 8 * 28) * 0.53, 0.01));
    final eventsBox = OverlayVisorLayout.eventsBoxSize(
      visor().withValue('eventNotificationMaxVisibleCount', 5),
    );
    expect(eventsBox.height, closeTo((22 + 5 * 70) * 0.53, 0.01));
    // review R6: the editor's event preview sits where the visor shows the
    // events, and a drag saves the height the way the visor reads it (at 0.7,
    // clear of the members: 0.7 x 990 = 693)
    final eventsAt = OverlayVisorLayout.eventsPlacement(
      [shipped('Members')],
      medium
          .withValue('eventNotificationY', 0.7)
          .withValue('showChat', false)
          .withValue('eventNotificationMaxVisibleCount', 3),
      big,
    )!;
    expect(eventsAt.top * (1080 / 1440), closeTo(693, 0.5));
    expect(
      OverlayVisorLayout.eventYFromTop(eventsAt.top, big),
      closeTo(0.7, 1e-6),
    );
    // review R7 (OverlayVisorTests checks the same numbers): at the large size
    // the tallest members and five events overflow the right column. m102
    // (11-18 "成员不挪，事件让，让不开就重叠"): the members stay on the right at the
    // middle slot's top, the events stay at 150 and overlap them; the editors
    // warn
    final overflowing = visor()
        .withValue('visorSize', 'Large')
        .withValue('visorMembersHeight', 554.0)
        .withValue('showEventNotifications', true)
        .withValue('eventNotificationMaxVisibleCount', 5)
        .withValue('showChat', false);
    final stayed = OverlayVisorLayout.arrange(
      [shipped('Members')],
      overflowing,
      surface,
    )['Members']!;
    expect(stayed.right, closeTo(surface.width - OverlayVisorLayout.edge, 0.5));
    expect(stayed.top, closeTo(OverlayVisorLayout.rightMidTop, 0.01));
    expect(
      OverlayVisorArrange.eventsOverlap(
        [shipped('Members')],
        overflowing,
        surface,
      ),
      isNotNull,
    );
    expect(
      OverlayVisorLayout.eventsPlacement(
        [shipped('Members')],
        overflowing,
        surface,
      )!.top,
      closeTo(150, 0.01),
    );
    // a right-side drag that lands in the "never moved" band saves just outside
    // it, so the events stay where they were dropped; the left side is free
    expect(OverlayVisorLayout.eventYFromTop(330, surface), 0.319);
    expect(OverlayVisorLayout.eventYFromTop(343, surface), 0.361);
    // review R8: saved with three decimals and read back, they still count as
    // moved (the events stay at Y x 990, not the right top 150)
    for (final y in const [0.319, 0.361]) {
      final reloaded = double.parse(y.toStringAsFixed(3));
      final placed = OverlayVisorLayout.eventsPlacement(
        [shipped('Members')],
        visor()
            .withValue('eventNotificationY', reloaded)
            .withValue('showChat', false)
            .withValue('showMembers', false),
        surface,
      )!;
      expect(placed.top, closeTo(reloaded * 990, 0.01));
    }
    expect(
      OverlayVisorLayout.eventYFromTop(330, surface, right: false),
      closeTo(330 / 990, 1e-9),
    );
    // no resize corner while members are hidden
    expect(OverlayVisorLayout.membersResizable(base), isTrue);
    expect(
      OverlayVisorLayout.membersResizable(base.withValue('showMembers', false)),
      isFalse,
    );
  });
}
