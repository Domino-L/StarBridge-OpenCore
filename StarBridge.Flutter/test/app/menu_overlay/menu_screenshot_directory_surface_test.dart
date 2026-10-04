import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_surface_app.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_screenshot_directory_card.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

import 'menu_overlay_surface_app_test.dart' show channel, snapshot, push;
import '../../features/friends/social_layout_test.dart' show capture, loadFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  for (final width in [1280.0, 1440.0]) {
    testWidgets(
      'live menu directory card reuses committed settings and clears on hide at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.reset);
        final calls = <MethodCall>[];
        var value = <String, Object?>{
          'schemaVersion': 1,
          'revision': 0,
          'directory': r'C:\Synthetic\Screenshots',
          'isDefault': true,
          'cancelled': false,
          'opened': false,
        };
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            if (call.method == 'ready') return snapshot(0, wanted: false);
            if (call.method == 'screenshotDirectory') {
              final args = call.arguments as Map;
              expect(args['opening'], 1);
              if (args['action'] == 'choose') {
                expect(args, {'opening': 1, 'action': 'choose', 'revision': 0});
                value = {
                  ...value,
                  'revision': 1,
                  'directory': r'C:\Synthetic\Chosen',
                  'isDefault': false,
                };
              }
              return jsonEncode(value);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final imageKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: imageKey, child: const MenuOverlaySurfaceApp()),
        );
        await tester.pumpAndSettle();
        Map<String, Object?> live(int opening) => {
          ...snapshot(opening),
          'workspacePreview': true,
          'nativeTools': true,
          'localToolsEpoch': 0,
          'liveFriends': true,
          'screenshotDirectory': true,
          'preferences': MenuWindowPreferences.defaults.encode(),
        };
        await push(tester, live(1));
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        expect(find.byType(MenuScreenshotDirectoryCard), findsOneWidget);
        expect(find.textContaining('只读试用'), findsNothing);
        final choose = find.byKey(
          const Key('menu-screenshot-directory-choose'),
        );
        await tester.ensureVisible(choose);
        await tester.pumpAndSettle();
        await tester.tap(choose);
        await tester.pumpAndSettle();
        expect(find.text(r'C:\Synthetic\Chosen'), findsOneWidget);
        await capture(
          tester,
          imageKey,
          'menu-directory-surface-${width.toInt()}',
        );
        expect(
          calls.where((call) => call.method == 'screenshotDirectory').length,
          2,
        );
        await push(tester, snapshot(1, wanted: false));
        await tester.pumpAndSettle();
        expect(find.text(r'C:\Synthetic\Chosen'), findsNothing);
        await push(tester, {...live(2), 'screenshotDirectory': false});
        await tester.pumpAndSettle();
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        expect(find.byType(MenuScreenshotDirectoryCard), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
