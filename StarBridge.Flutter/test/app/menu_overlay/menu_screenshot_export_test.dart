import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_image_edit.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

void main() {
  for (final hidden in [false, true]) {
    test('capture uses visibility at click time: $hidden', () async {
      final sent = <(String, Map<String, Object?>)>[];
      final tools = MenuLocalToolsController((action, args) async {
        sent.add((action, args));
        return action == 'capture' ? Uint8List.fromList([1, 2]) : null;
      });
      tools.screenshotPreferences = MenuScreenshotPreferences(hideMenu: hidden);
      var changed = false;
      tools.addListener(() {
        if (!changed && tools.busy) {
          changed = true;
          tools.settings(
            screenshot: MenuScreenshotPreferences(hideMenu: !hidden),
          );
        }
      });
      await tools.image(capture: true);
      expect(sent.single.$1, 'capture');
      expect(sent.single.$2, {'hideMenu': hidden});
      expect(tools.screenshot, [1, 2]);
      await tools.image();
      expect(sent.last.$1, 'image');
      expect(sent.last.$2, isEmpty);
      expect(
        tools.screenshotPreferences.toExportOptions().containsKey('hideMenu'),
        false,
      );
      tools.dispose();
    });
  }
  test('legacy defaults do not add a setting; strict policies reject unrelated data', () {
    final legacy = {...MenuWindowPreferences.defaults.settings};
    expect(
      MenuScreenshotPreferences.fromSettings(legacy)!.toMap(),
      const MenuScreenshotPreferences().toMap(),
    );
    expect(legacy.containsKey('screenshot'), false);
    final oldExport = const MenuScreenshotPreferences().toMap()
      ..remove('hideMenu');
    expect(
      MenuScreenshotPreferences.fromSettings({'screenshot': oldExport})!
          .hideMenu,
      true,
    );
    expect(oldExport.containsKey('hideMenu'), false);
    for (final invalid in [
      null,
      {},
      {...const MenuScreenshotPreferences().toMap(), 'format': 'gif'},
      {...const MenuScreenshotPreferences().toMap(), 'jpegQuality': 49},
      {...const MenuScreenshotPreferences().toMap(), 'jpegQuality': 101},
      {...const MenuScreenshotPreferences().toMap(), 'jpegQuality': 90.0},
      {...const MenuScreenshotPreferences().toMap(), 'copyAfterSave': 1},
      {...const MenuScreenshotPreferences().toMap(), 'showConfirmation': null},
      {...const MenuScreenshotPreferences().toMap(), 'hideMenu': null},
      {...const MenuScreenshotPreferences().toMap(), 'hideMenu': 'false'},
      {...const MenuScreenshotPreferences().toMap(), 'hideMenu': 0},
      {...const MenuScreenshotPreferences().toMap(), 'path': 'synthetic.png'},
    ]) {
      expect(
        MenuWindowPreferences.parse({
          ...MenuWindowPreferences.defaults.toMap(),
          'settings': {...legacy, 'screenshot': invalid},
        }),
        isNull,
      );
    }
    for (final format in ['png', 'jpeg']) {
      for (final quality in [50, 90, 100]) {
        final value = MenuWindowPreferences.defaults.withSettingsPatch(
          MenuScreenshotPreferences(
            format: format,
            jpegQuality: quality,
          ).toSettingsPatch(),
        );
        expect(MenuWindowPreferences.parse(value.toMap()), isNotNull);
        expect(value.layout, MenuWindowPreferences.defaults.layout);
        expect(value.settings['hotkey'], legacy['hotkey']);
      }
    }
  });
  test('save and optional lossless clipboard share the edited recipe and snapshot preferences', () async {
    final pending = Completer<Object?>(),
        calls = <(String, Map<String, Object?>)>[];
    final tools = MenuLocalToolsController((action, args) {
      calls.add((action, args));
      return action == 'save' ? pending.future : Future<Object?>.value(true);
    })..screenshot = Uint8List.fromList([1]);
    tools.screenshotEdit = const MenuImageEdit()
        .select(const Rect.fromLTRB(.2, .1, .8, .9))!
        .rotate();
    final recipe = tools.screenshotEdit.toMap();
    tools.settings(
      screenshot: const MenuScreenshotPreferences(
        format: 'jpeg',
        jpegQuality: 75,
        copyAfterSave: true,
      ),
    );
    final save = tools.save();
    await tools.save();
    expect(calls.length, 1);
    tools.settings(screenshot: const MenuScreenshotPreferences());
    pending.complete(true);
    await save;
    expect(calls.map((call) => call.$1), ['save', 'screenshotCopy']);
    expect(calls.first.$2, {
      ...recipe,
      'export': {'format': 'jpeg', 'jpegQuality': 75},
    });
    expect(calls.last.$2, recipe);
    expect(tools.screenshotNoticeKey, 'savedCopied');
    expect(tools.busy, false);
    tools.dispose();
  });
  for (final reply in [true, false, null, 'invalid']) {
    test(
      'save response $reply never copies unless successful and opted in',
      () async {
        final calls = <String>[];
        final tools = MenuLocalToolsController((action, _) async {
          calls.add(action);
          return reply;
        })..screenshot = Uint8List.fromList([1]);
        await tools.save();
        expect(calls, ['save']);
        expect(
          tools.screenshotNoticeKey,
          reply == true
              ? 'exported'
              : reply == false
              ? 'cancelled'
              : 'saveFailed',
        );
        tools.dispose();
      },
    );
  }
  for (final throwing in [false, true]) {
    test(
      'clipboard failure after successful save is not a file save failure $throwing',
      () async {
        final tools = MenuLocalToolsController((action, _) async {
          if (action == 'save') return true;
          if (throwing) throw StateError('synthetic clipboard failure');
          return false;
        })..screenshot = Uint8List.fromList([1]);
        tools.settings(
          screenshot: const MenuScreenshotPreferences(
            copyAfterSave: true,
            showConfirmation: false,
          ),
        );
        await tools.save();
        expect(tools.screenshotNoticeKey, 'savedCopyFailed');
        expect(tools.screenshot, isNotNull);
        tools.dispose();
      },
    );
  }
  test('confirmation switch hides success only; cancellation and errors remain actionable', () async {
    Object? reply = true;
    PlatformException? error;
    final tools = MenuLocalToolsController((_, _) async {
      if (error != null) throw error;
      return reply;
    })..screenshot = Uint8List.fromList([1]);
    tools.settings(
      screenshot: const MenuScreenshotPreferences(showConfirmation: false),
    );
    await tools.save();
    expect(tools.screenshotNoticeKey, '');
    reply = false;
    await tools.save();
    expect(tools.screenshotNoticeKey, 'cancelled');
    error = PlatformException(code: 'menu.screenshot_extension_mismatch');
    await tools.save();
    expect(tools.screenshotNoticeKey, 'extensionMismatch');
    await tools.save(copy: true);
    expect(tools.screenshotNoticeKey, 'extensionMismatch');
    error = PlatformException(code: 'synthetic');
    await tools.save(copy: true);
    expect(tools.screenshotNoticeKey, 'copyFailed');
    tools.dispose();
  });
  for (final captureReply in [
    Uint8List.fromList([2]),
    null,
    Uint8List(0),
  ]) {
    test(
      'capture and save requires a new successful capture $captureReply',
      () async {
        final calls = <String>[];
        final tools = MenuLocalToolsController((action, _) async {
          calls.add(action);
          return action == 'capture' ? captureReply : true;
        })..screenshot = Uint8List.fromList([1]);
        await tools.captureAndSave();
        final captured = captureReply is Uint8List && captureReply.isNotEmpty;
        expect(calls, captured ? ['capture', 'save'] : ['capture']);
        expect(tools.screenshot, captured ? captureReply : [1]);
        tools.dispose();
      },
    );
  }
  for (final action in ['capture', 'save', 'screenshotCopy']) {
    test(
      'late $action cannot write or repopulate after session disposal',
      () async {
        final pending = Completer<Object?>(), calls = <String>[];
        final tools = MenuLocalToolsController((name, _) {
          calls.add(name);
          return name == action ? pending.future : Future<Object?>.value(true);
        })..screenshot = Uint8List.fromList([1]);
        tools.settings(
          screenshot: const MenuScreenshotPreferences(copyAfterSave: true),
        );
        final operation = action == 'capture'
            ? tools.captureAndSave()
            : tools.save();
        await Future<void>.delayed(Duration.zero);
        tools.dispose();
        pending.complete(action == 'capture' ? Uint8List.fromList([2]) : true);
        await operation;
        expect(
          calls,
          action == 'screenshotCopy' ? ['save', 'screenshotCopy'] : [action],
        );
        expect(tools.screenshot, isNull);
        expect(tools.screenshotNoticeKey, isEmpty);
      },
    );
  }
}
