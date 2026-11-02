import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_announcement_details_control.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_announcement_details_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_browser_tool.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_native_popup.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

import '../../app/menu_overlay/menu_browser_tabs_test.dart'
    show BrowserFake, workspace;
import '../../app/menu_overlay/menu_announcement_details_control_test.dart'
    show fixture;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3ch_test.dart' show activate;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final exit in ['pointer', 'keyboard', 'reader', 'escape', 'retire']) {
      testWidgets(
        '$suite actual details $exit preserves native viewport lease',
        (t) async {
          final semantics = t.ensureSemantics();
          final native = BrowserFake(), work = workspace();
          final observer = MenuNativePopupObserver(),
              active = ValueNotifier(true);
          bool browserVisible() =>
              native.calls
                  .lastWhere((c) => c.$1 == 'browserBounds')
                  .$2['visible'] ==
              true;
          try {
            expect(nativeViewportMenus.value, 0);
            size(t, const Size(1000, 900));
            await t.pumpWidget(
              scopedApp(
                Navigator(
                  observers: [observer],
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => Column(
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable: active,
                          builder: (context, enabled, _) =>
                              MenuAnnouncementDetailsControl(
                                view: MenuAnnouncementDetailsView.parse(
                                  fixture(),
                                )!,
                                action: 'a1',
                                enabled: true,
                                active: enabled,
                                dispatch: (_, _) {},
                              ),
                        ),
                        Expanded(
                          child: MenuBrowserTool(
                            call: native.call,
                            workspace: work,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                suite,
              ),
            );
            await frames(t);
            expect(browserVisible(), true);
            await activate(
              t,
              exit == 'keyboard' ? 'keyboard' : 'pointer',
              'menu-announcement-details-open',
            );
            await frames(t);
            expect(nativeViewportMenus.value, 1);
            expect(browserVisible(), false);
            if (exit == 'retire') {
              active.value = false;
            } else if (exit == 'escape') {
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
            } else {
              await activate(t, exit, 'menu-announcement-details-close');
            }
            await t.pump();
            await t.pump(const Duration(milliseconds: 20));
            if (exit == 'pointer' && suite != InteractionSuite.standard) {
              expect(nativeViewportMenus.value, 1);
              expect(browserVisible(), false);
            } else if (exit != 'pointer') {
              expect(nativeViewportMenus.value, 0);
            }
            await frames(t);
            expect(nativeViewportMenus.value, 0);
            expect(browserVisible(), true);
            expect(find.byType(AlertDialog), findsNothing);
            if (exit == 'keyboard') {
              // Closing the keyboard-opened dialog restores the actual entry's
              // focus, not just a route-level FocusScope or a hidden close target.
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
              await frames(t);
              expect(find.byType(AlertDialog), findsOneWidget);
              expect(nativeViewportMenus.value, 1);
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
              await frames(t);
              expect(nativeViewportMenus.value, 0);
              expect(browserVisible(), true);
            }
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            observer.dispose();
            active.dispose();
            work.dispose();
            semantics.dispose();
          }
        },
      );
    }
  }
}
