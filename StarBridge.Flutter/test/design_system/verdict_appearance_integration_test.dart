import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/appearance_motion_browser.dart';
import 'package:starbridge_flutter/design_system/styles/native_appearance_player.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/platform/window/overlay_editor_window_port.dart';

const _privatePack = bool.fromEnvironment('STARBRIDGE_TEST_PRIVATE_APPEARANCE');

Map<String, Object?> _profile() => {
  'id': 'Verdict',
  'displayNameZh': '裁决',
  'displayNameEn': 'Verdict',
  'summaryZh': '预览',
  'summaryEn': 'Preview',
  'traitsZh': ['折角'],
  'traitsEn': ['Folds'],
  'previewSurface': '#0B1015',
  'previewPrimary': '#E5EAEE',
  'previewSecondary': '#F12D3F',
  'locksTheme': true,
  'supportsBloom': true,
  'startupTransition': 'VerdictProtocol',
  'requiresEntitlement': true,
  'isReleased': false,
  'isAvailable': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preview readiness is optional, strict and independent of release', () {
    final old = OverlayWorkspaceAppearance.fromMap(_profile());
    expect(old.isPreviewAvailable, isFalse);
    final ready = OverlayWorkspaceAppearance.fromMap({
      ..._profile(),
      'isPreviewAvailable': true,
    });
    expect(ready.isPreviewAvailable, isTrue);
    expect(ready.isReleased, isFalse);
    expect(ready.isAvailable, isFalse);
    expect(ready.copyWith(isAvailable: true).isPreviewAvailable, isTrue);
    expect(
      ready.copyWith(isPreviewAvailable: false).isPreviewAvailable,
      isFalse,
    );
    expect(
      () => OverlayWorkspaceAppearance.fromMap({
        ..._profile(),
        'isPreviewAvailable': 'true',
      }),
      throwsFormatException,
    );
    expect(
      () => OverlayWorkspaceAppearance.fromMap({
        ..._profile(),
        'isPreviewAvailable': null,
      }),
      throwsFormatException,
    );
    expect(
      () => OverlayWorkspaceAppearance.fromMap({
        ..._profile(),
        'unknownFlag': true,
      }),
      throwsFormatException,
    );
  });

  testWidgets('ordinary preview browser cannot select unreleased media', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppearanceMotionBrowser(context, 'Default'),
            child: const Text('Browse'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Browse'));
    await tester.pump();
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byKey(const Key('appearance-motion-skin')),
    );
    expect(dropdown.items!.map((item) => item.value), [
      'Default',
      'NightShadow',
    ]);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'private pack contains seven native clips, a marker, and fixed 2K opening',
    () async {
      final manifest = jsonDecode(
        File('assets/overlay-appearances/verdict-manifest.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(manifest['schemaVersion'], 2);
      expect(manifest['designRevision'], 'notice-live-clock-review-2026-09-09');
      expect(manifest['allNativeFramesPixelExact'], isTrue);
      expect(manifest['fullCoverEndMs'] - manifest['fullCoverStartMs'], 220);
      expect(manifest['sceneSwitchMs'], 930);
      expect(
        manifest['transitionLifecycle'],
        'unopened -> seal -> covered -> unseal -> modules',
      );
      final clips = manifest['clips'] as List;
      expect(
        clips.map((dynamic clip) => clip['mode']),
        unorderedEquals([
          'flow',
          'notice-in',
          'notice-out',
          'event-in',
          'event-out',
          'event-cycle',
          'transition',
        ]),
      );
      for (final dynamic clip in clips) {
        final codec = await ui.instantiateImageCodec(
          File('assets/overlay-appearances/${clip['file']}').readAsBytesSync(),
        );
        expect(codec.frameCount, clip['frameCount']);
        var duration = Duration.zero;
        for (var i = 0; i < codec.frameCount; i++) {
          final frame = await codec.getNextFrame();
          expect(frame.image.width, clip['width']);
          expect(frame.image.height, clip['height']);
          duration += frame.duration;
          frame.image.dispose();
        }
        expect(duration.inMilliseconds, clip['durationMs']);
        if (clip['mode'] == 'transition') {
          expect(clip['width'], 2560);
          expect(clip['height'], 1440);
        }
        if (clip['mode'] == 'event-cycle') {
          expect(duration.inMilliseconds, 96000);
          for (final key in [
            'eventCycleMs',
            'lightCycleMs',
            'eventDockLightCycleMs',
          ]) {
            expect(duration.inMilliseconds % (manifest[key] as int), 0);
          }
        }
        codec.dispose();
      }
      final codec = await ui.instantiateImageCodec(
        File('assets/overlay-appearances/Verdict.png').readAsBytesSync(),
      );
      final image = (await codec.getNextFrame()).image;
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var redPixels = 0;
      for (var y = 89; y <= 98; y++) {
        for (var x = 574; x <= 583; x++) {
          final offset = (y * image.width + x) * 4;
          final red = bytes.getUint8(offset);
          if (red > 120 &&
              red > bytes.getUint8(offset + 1) + 50 &&
              red > bytes.getUint8(offset + 2) + 50) {
            redPixels++;
          }
        }
      }
      expect(redPixels, greaterThanOrEqualTo(8));
      image.dispose();
      codec.dispose();
    },
    skip: !_privatePack,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'private fullscreen cover hides controls and Escape remains available',
    (tester) async {
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1.25;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final window = _Window();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppearanceMotionBrowser(
                context,
                'Verdict',
                editorWindow: window,
                previewableIds: const {'Default', 'NightShadow', 'Verdict'},
              ),
              child: const Text('Browse'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Browse'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('appearance-motion-mode')));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Startup transition').last);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(
        find.byKey(const Key('appearance-transition-fullscreen')),
      );
      await tester.pump();
      await tester.pump();
      Future<void> decode() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 160)),
        );
        await tester.pump();
      }

      await decode();
      final player = tester.widget<NativeAppearancePlayer>(
        find.byType(NativeAppearancePlayer),
      );
      expect(player.nativePixels, isTrue);
      final raw = tester.widget<RawImage>(find.byType(RawImage));
      expect(raw.image!.width, 2560);
      expect(raw.image!.height, 1440);
      expect(raw.scale, 1.25);
      expect(raw.fit, BoxFit.none);
      var coveredIndex = 0;
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          File('assets/overlay-appearances/Verdict-transition.webp')
              .readAsBytesSync(),
        );
        var time = Duration.zero;
        for (var i = 0; i < codec.frameCount; i++) {
          final frame = await codec.getNextFrame();
          final covered = time.inMilliseconds >= 820;
          time += frame.duration;
          frame.image.dispose();
          if (covered) {
            coveredIndex = i;
            break;
          }
        }
        codec.dispose();
      });
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(coveredIndex.toDouble());
      slider.onChangeEnd!(coveredIndex.toDouble());
      // Full-resolution decoding is asynchronous; wait for the requested frame,
      // not an arbitrary single-frame decode delay on a particular test machine.
      for (
        var attempt = 0;
        attempt < 20 && find.byType(Slider).evaluate().isNotEmpty;
        attempt++
      ) {
        await decode();
      }
      expect(find.byType(Slider), findsNothing);
      expect(find.byKey(const Key('appearance-transition-exit')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(window.exits, greaterThan(0));
      expect(
        find.byKey(const Key('appearance-transition-fullscreen')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
    skip: !_privatePack,
  );
}

class _Window implements OverlayEditorWindowPort {
  int exits = 0;
  @override
  Future<void> enter() async {}
  @override
  Future<void> exit() async {
    exits++;
  }
}
