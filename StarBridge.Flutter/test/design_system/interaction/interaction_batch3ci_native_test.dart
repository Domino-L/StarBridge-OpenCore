import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_avatar_actions.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_browser_tool.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_native_popup.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

import '../../app/menu_overlay/menu_browser_tabs_test.dart'
    show BrowserFake, workspace;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3ci_test.dart' show row, choose;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final exit in ['pointer', 'keyboard', 'reader', 'retire', 'reopen']) {
      testWidgets(
        '$suite actual avatar/browser $exit holds exactly its lease',
        (t) async {
          final semantics = t.ensureSemantics();
          final native = BrowserFake(),
              work = workspace(),
              target = ValueNotifier('a');
          final observer = MenuNativePopupObserver();
          bool browserVisible() =>
              native.calls
                  .lastWhere((c) => c.$1 == 'browserBounds')
                  .$2['visible'] ==
              true;
          var profileCalls = 0;
          late VoidCallback holdOther, releaseOther;
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
                        NativeViewportMenu(
                          builder: (open, close) {
                            holdOther = open;
                            releaseOther = close;
                            return const SizedBox.shrink();
                          },
                        ),
                        ValueListenableBuilder<String>(
                          valueListenable: target,
                          builder: (_, id, _) => MenuAvatarActions(
                            key: const Key('native-avatar'),
                            identity: id,
                            name: '原生网页旁的用户',
                            onProfile: () => profileCalls++,
                            child: const SizedBox.square(
                              dimension: 32,
                              child: Text('A'),
                            ),
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
            await t.tap(find.byKey(const Key('native-avatar')));
            await frames(t);
            expect(nativeViewportMenus.value, 1);
            expect(browserVisible(), false);
            if (exit == 'retire') {
              // Keep the browser and Navigator stable while a second real lease
              // is held. Retiring this avatar must not release the other owner.
              holdOther();
              await t.pump();
              expect(nativeViewportMenus.value, 2);
              target.value = 'b';
              await t.pump();
              await t.pump();
              expect(nativeViewportMenus.value, 1);
              expect(browserVisible(), false);
              releaseOther();
              await t.pump();
              await frames(t);
              expect(nativeViewportMenus.value, 0);
              expect(browserVisible(), true);
              expect(profileCalls, 0);
            } else if (exit == 'reopen') {
              await t.tapAt(const Offset(980, 880));
              await t.pump();
              await t.pump(const Duration(milliseconds: 20));
              if (suite != InteractionSuite.standard) {
                expect(nativeViewportMenus.value, 1);
              }
              await t.tap(find.byKey(const Key('native-avatar')));
              await t.pump();
              await frames(t);
              expect(nativeViewportMenus.value, 1);
              expect(browserVisible(), false);
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
              await frames(t);
              expect(nativeViewportMenus.value, 0);
              expect(browserVisible(), true);
              expect(profileCalls, 0);
            } else {
              await choose(t, exit, '查看个人页面', row('avatar-profile'));
              await t.pump();
              await t.pump(const Duration(milliseconds: 20));
              if (exit == 'pointer' && suite != InteractionSuite.standard) {
                expect(nativeViewportMenus.value, 1);
                expect(browserVisible(), false);
              } else if (exit != 'pointer') {
                expect(nativeViewportMenus.value, 0);
              }
              expect(profileCalls, 1);
              await frames(t);
              expect(nativeViewportMenus.value, 0);
              expect(browserVisible(), true);
            }
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            observer.dispose();
            target.dispose();
            work.dispose();
            semantics.dispose();
            expect(nativeViewportMenus.value, 0);
          }
        },
      );
    }
  }
}
