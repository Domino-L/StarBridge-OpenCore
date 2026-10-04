import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_image_edit.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_preferences.dart';

void main() {
  test(
    'direct export reads destination once then saves same recipe, never a path',
    () async {
      final pending = Completer<Object?>(),
          calls = <(String, Map<String, Object?>)>[];
      final tools =
          MenuLocalToolsController((action, args) {
              calls.add((action, args));
              return action == 'screenshotDestination'
                  ? pending.future
                  : Future.value(true);
            })
            ..screenshot = Uint8List.fromList([1])
            ..screenshotDirectoryAvailable = true;
      tools.screenshotEdit = const MenuImageEdit().rotate();
      final recipe = tools.screenshotEdit.toMap();
      tools.settings(
        screenshot: const MenuScreenshotPreferences(
          format: 'jpeg',
          jpegQuality: 75,
          copyAfterSave: true,
        ),
      );
      final work = tools.save(toDirectory: true);
      await tools.save(toDirectory: true);
      expect(calls.map((call) => call.$1), ['screenshotDestination']);
      expect(calls.single.$2, isEmpty);
      tools.settings(screenshot: const MenuScreenshotPreferences());
      pending.complete(true);
      await work;
      expect(calls.map((c) => c.$1), [
        'screenshotDestination',
        'saveToDirectory',
        'screenshotCopy',
      ]);
      expect(calls[1].$2, {
        ...recipe,
        'export': {'format': 'jpeg', 'jpegQuality': 75},
      });
      expect(calls.last.$2, recipe);
      expect(tools.screenshotNoticeKey, 'savedCopied');
      tools.dispose();
    },
  );
  for (final capability in [false, true]) {
    for (final reply in [false, null, 'C:\\synthetic']) {
      test(
        'unavailable destination cap=$capability reply=$reply never writes or falls back',
        () async {
          final calls = <String>[];
          final tools =
              MenuLocalToolsController((action, _) async {
                  calls.add(action);
                  return reply;
                })
                ..screenshot = Uint8List.fromList([1])
                ..screenshotDirectoryAvailable = capability;
          await tools.save(toDirectory: true);
          expect(calls, capability ? ['screenshotDestination'] : isEmpty);
          expect(tools.screenshotNoticeKey, 'directoryUnavailable');
          expect(tools.screenshot, [1]);
          tools.dispose();
        },
      );
    }
  }
  test(
    'failed direct save is not dialog cancellation and cannot copy',
    () async {
      final calls = <String>[];
      final tools =
          MenuLocalToolsController((action, _) async {
              calls.add(action);
              return action == 'screenshotDestination';
            })
            ..screenshot = Uint8List.fromList([1])
            ..screenshotDirectoryAvailable = true;
      tools.settings(
        screenshot: const MenuScreenshotPreferences(copyAfterSave: true),
      );
      await tools.save(toDirectory: true);
      expect(calls, ['screenshotDestination', 'saveToDirectory']);
      expect(tools.screenshotNoticeKey, 'saveFailed');
      tools.dispose();
    },
  );
  for (final action in ['screenshotDestination', 'saveToDirectory']) {
    test('late $action cannot continue after disposal', () async {
      final pending = Completer<Object?>(), calls = <String>[];
      final tools =
          MenuLocalToolsController((name, _) {
              calls.add(name);
              return name == action ? pending.future : Future.value(true);
            })
            ..screenshot = Uint8List.fromList([1])
            ..screenshotDirectoryAvailable = true;
      tools.settings(
        screenshot: const MenuScreenshotPreferences(copyAfterSave: true),
      );
      final work = tools.save(toDirectory: true);
      await Future<void>.delayed(Duration.zero);
      tools.dispose();
      pending.complete(true);
      await work;
      expect(
        calls,
        action == 'screenshotDestination'
            ? ['screenshotDestination']
            : ['screenshotDestination', 'saveToDirectory'],
      );
      expect(tools.screenshot, isNull);
    });
  }
  test('capture and direct save retains preferences chosen at click', () async {
    final pending = Completer<Object?>(),
        calls = <(String, Map<String, Object?>)>[];
    final tools = MenuLocalToolsController((name, args) {
      calls.add((name, args));
      return name == 'capture' ? pending.future : Future.value(true);
    })..screenshotDirectoryAvailable = true;
    tools.settings(
      screenshot: const MenuScreenshotPreferences(
        format: 'jpeg',
        jpegQuality: 60,
      ),
    );
    final work = tools.captureAndSave(toDirectory: true);
    tools.settings(screenshot: const MenuScreenshotPreferences());
    pending.complete(Uint8List.fromList([2]));
    await work;
    expect(calls.map((c) => c.$1), [
      'capture',
      'screenshotDestination',
      'saveToDirectory',
    ]);
    expect(calls.last.$2['export'], {'format': 'jpeg', 'jpegQuality': 60});
    tools.dispose();
  });
}
