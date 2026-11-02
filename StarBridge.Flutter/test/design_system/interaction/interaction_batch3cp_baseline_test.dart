import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_browser_tool.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/menu_overlay/menu_browser_tabs_test.dart'
    show BrowserFake, workspace, flush;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cn_visual_test.dart' show pixels;

void main() {
  testWidgets('original actual browser control geometry', (t) async {
    final native = BrowserFake(), work = workspace();
    size(t, const Size(900, 650));
    await t.pumpWidget(
      scopedApp(
        MenuBrowserTool(call: native.call, workspace: work),
        InteractionSuite.standard,
      ),
    );
    await flush(t);
    expect(
      t.getSize(find.byKey(const ValueKey('browser-close-t1'))),
      const Size(48, 48),
    );
    expect(
      t.getSize(find.byKey(const ValueKey('browser-new-tab'))),
      const Size(48, 48),
    );
    expect(
      t.getRect(find.byKey(const ValueKey('browser-address'))),
      const Rect.fromLTRB(8, 89, 831.5, 133),
    );
    expect(
      native.calls.lastWhere((c) => c.$1 == 'browserBounds').$2['y'],
      134.0,
    );
    await t.pumpWidget(const SizedBox());
    work.dispose();
  });
  testWidgets('existing icon standard keyboard focus stays static', (t) async {
    final frame = GlobalKey(), focus = FocusNode();
    await t.pumpWidget(
      scopedApp(
        RepaintBoundary(
          key: frame,
          child: StarBridgeIconAction(
            label: 'icon-probe',
            focusNode: focus,
            onActivate: (_) {},
            icon: const Icon(Icons.add),
          ),
        ),
        InteractionSuite.standard,
      ),
    );
    await t.pumpAndSettle();
    focus.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(milliseconds: 20));
    final first = await pixels(t, find.byKey(frame));
    await t.pump(const Duration(milliseconds: 100));
    expect(await pixels(t, find.byKey(frame)), orderedEquals(first));
    await t.pumpWidget(const SizedBox());
    focus.dispose();
  });
}
