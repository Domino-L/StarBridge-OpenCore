import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';

MenuPanelSpec spec(
  String id, [
  Rect bounds = const Rect.fromLTWH(20, 30, 320, 260),
]) => MenuPanelSpec(id: id, initialBounds: bounds);
const viewport = Size(1280, 720);

void main() {
  late MenuWorkspaceController controller;
  setUp(() {
    controller = MenuWorkspaceController(
      scope: 'owner-a',
      panels: [spec('friends'), spec('chat')],
    );
  });
  tearDown(() => controller.dispose());

  test('open is unique; activation retains lease and close restores previous active', () {
    expect(controller.open('unsupported'), isFalse);
    controller.open('friends');
    final first = controller.openPanels.single;
    controller.open('friends');
    controller.open('chat');
    controller.activate('friends');
    expect(controller.openPanels.map((p) => p.id), ['chat', 'friends']);
    expect(controller.isCurrent(first), isTrue);
    controller.close('friends');
    expect(controller.activeId, 'chat');
    expect(controller.isCurrent(first), isFalse);
    controller.open('friends');
    expect(controller.isCurrent(first), isFalse);
  });

  test('hide retains panels; explicit clean hide disposes leases', () {
    controller.open('friends');
    final lease = controller.openPanels.single;
    controller.setVisible(false);
    expect(controller.isCurrent(lease), isTrue);
    final rect = controller.boundsFor('friends', viewport);
    controller.moveTo(lease, const Offset(300, 300), viewport);
    expect(controller.boundsFor('friends', viewport), rect);
    controller.setVisible(true);
    expect(controller.openPanels.single, same(lease));
    controller.setVisible(false, retainPanels: false);
    expect(controller.isCurrent(lease), isFalse);
    controller.setVisible(true);
    expect(controller.openPanels, isEmpty);
  });

  test(
    'scope change clears panels and placements, invalidates old responses',
    () {
      controller.open('friends');
      final lease = controller.openPanels.single;
      controller.moveTo(lease, const Offset(300, 300), viewport, snap: false);
      final layoutLease = controller.captureLayoutLease();
      final layout = controller.exportLayout();
      controller.reconcile(scope: 'owner-b', panels: [spec('friends')]);
      expect(controller.openPanels, isEmpty);
      expect(controller.isCurrent(lease), isFalse);
      expect(controller.restoreLayout(layout, lease: layoutLease), isFalse);
      controller.open('friends');
      controller.moveTo(lease, const Offset(600, 600), viewport);
      expect(
        controller.boundsFor('friends', viewport).topLeft,
        const Offset(20, 30),
      );
    },
  );

  test(
    'revocation closes only revoked panel; rejected registrations are atomic',
    () {
      controller.open('friends');
      final friend = controller.openPanels.single;
      controller.open('chat');
      final chat = controller.openPanels.last;
      expect(
        () => controller.reconcile(
          scope: 'owner-b',
          panels: [spec('x'), spec('x')],
        ),
        throwsArgumentError,
      );
      expect(controller.isCurrent(friend), isTrue);
      controller.reconcile(scope: 'owner-a', panels: [spec('friends')]);
      expect(controller.isCurrent(friend), isTrue);
      expect(controller.isCurrent(chat), isFalse);
      expect(controller.open('chat'), isFalse);
    },
  );

  test(
    'moving snaps to viewport and peer edges, keyboard can bypass snapping',
    () {
      controller.snapWindows = true;
      controller.open('friends');
      final lease = controller.openPanels.single;
      controller.moveTo(lease, const Offset(8, 9), viewport);
      expect(controller.boundsFor('friends', viewport).topLeft, Offset.zero);
      controller.moveTo(lease, const Offset(8, 9), viewport, snap: false);
      expect(
        controller.boundsFor('friends', viewport).topLeft,
        const Offset(8, 9),
      );
      controller.open('chat');
      final chat = controller.openPanels.last;
      controller.moveTo(chat, const Offset(650, 30), viewport, snap: false);
      controller.moveTo(lease, const Offset(322, 30), viewport);
      expect(controller.boundsFor('friends', viewport).right, 650);
    },
  );

  test('resize keeps minimum and anchor but can exceed the display', () {
    controller.open('friends');
    final lease = controller.openPanels.single;
    controller.resizeTo(lease, const Size(-100, -100), viewport);
    expect(
      controller.boundsFor('friends', viewport),
      const Rect.fromLTWH(20, 30, 240, 160),
    );
    controller.resizeTo(lease, const Size(9000, 9000), viewport);
    expect(
      controller.boundsFor('friends', viewport),
      const Rect.fromLTWH(20, 30, 9000, 9000),
    );
  });

  test('small monitor clips without relocating or resizing windows', () {
    controller.open('friends');
    final lease = controller.openPanels.single;
    controller.moveTo(lease, const Offset(800, 440), viewport, snap: false);
    final wide = controller.boundsFor('friends', viewport);
    final tiny = controller.boundsFor('friends', const Size(160, 120));
    expect(tiny, wide);
    expect(controller.boundsFor('friends', viewport), wide);
    expect(controller.boundsFor('friends', Size.zero), Rect.zero);
  });

  test('invalid input does not poison layout', () {
    controller.open('friends');
    final lease = controller.openPanels.single;
    final before = controller.exportLayout();
    controller.moveTo(lease, const Offset(double.nan, 0), viewport);
    controller.resizeTo(lease, const Size(double.infinity, 200), viewport);
    controller.moveTo(lease, Offset.zero, Size.zero);
    expect(controller.exportLayout(), before);
  });

  test(
    'layout round trip preserves order and geometry but not content or scope',
    () {
      controller.open('friends');
      controller.moveTo(
        controller.openPanels.single,
        const Offset(110, 120),
        viewport,
        snap: false,
      );
      controller.open('chat');
      final encoded = jsonEncode(controller.exportLayout());
      expect(encoded, isNot(contains('owner-a')));
      final target = MenuWorkspaceController(
        scope: Object(),
        panels: [spec('friends'), spec('chat')],
      );
      addTearDown(target.dispose);
      expect(
        target.restoreLayout(
          jsonDecode(encoded),
          lease: target.captureLayoutLease(),
          reopenPanels: true,
        ),
        isTrue,
      );
      expect(target.openPanels.map((p) => p.id), ['friends', 'chat']);
      expect(target.activeId, 'chat');
      expect(
        target.boundsFor('friends', viewport).topLeft,
        const Offset(110, 120),
      );
    },
  );

  test(
    'restore does not reopen by default and ignores unregistered panel IDs',
    () {
      controller.open('chat');
      final layout = controller.exportLayout();
      controller.reconcile(scope: 'owner-b', panels: [spec('friends')]);
      expect(
        controller.restoreLayout(
          layout,
          lease: controller.captureLayoutLease(),
          reopenPanels: true,
        ),
        isTrue,
      );
      expect(controller.openPanels, isEmpty);
      controller.reconcile(scope: 'owner-c', panels: [spec('chat')]);
      expect(
        controller.restoreLayout(
          layout,
          lease: controller.captureLayoutLease(),
        ),
        isTrue,
      );
      expect(controller.openPanels, isEmpty);
    },
  );

  test(
    'late restore cannot overwrite a drag or cross controller ownership',
    () {
      final token = controller.captureLayoutLease();
      final layout = controller.exportLayout();
      controller.open('friends');
      expect(controller.restoreLayout(layout, lease: token), isFalse);
      final other = MenuWorkspaceController(
        scope: 'owner-a',
        panels: [spec('friends')],
      );
      addTearDown(other.dispose);
      expect(
        other.restoreLayout(layout, lease: controller.captureLayoutLease()),
        isFalse,
      );
    },
  );

  test(
    'unknown versions, malformed and oversized snapshots fail without mutation',
    () {
      controller.open('friends');
      final before = controller.exportLayout();
      final invalid = <Object?>[
        null,
        {'version': 2, 'panels': [], 'open': []},
        {
          'version': 1,
          'panels': [
            {
              'id': 'friends',
              'bounds': [0, 0, double.nan, 200],
            },
          ],
          'open': [],
        },
        {
          'version': 1,
          'panels': [],
          'open': ['friends', 'friends'],
        },
        {
          'version': 1,
          'panels': List.filled(33, {'id': 'x'}),
          'open': [],
        },
      ];
      for (final value in invalid) {
        expect(
          controller.restoreLayout(
            value,
            lease: controller.captureLayoutLease(),
          ),
          isFalse,
        );
        expect(controller.exportLayout(), before);
      }
    },
  );
}
