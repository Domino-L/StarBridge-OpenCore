import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_flutter/platform/window/overlay_editor_window_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/appearance_motion_browser.dart';
import 'package:starbridge_flutter/design_system/styles/native_appearance_player.dart';

// Rendered appearance clips are not distributed with public source.
const _privateArtworkOnly = bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every browsable action has a decodable native clip and no Verdict asset',
    () async {
      final manifest = jsonDecode(
        File('assets/overlay-appearances/motion-manifest.json')
            .readAsStringSync(),
      );
      final clips = manifest['clips'] as List<dynamic>;
      expect(clips, hasLength(13));
      for (final skin in ['Default', 'NightShadow']) {
        expect(
          clips
              .where((dynamic clip) => clip['skin'] == skin)
              .map((dynamic clip) => clip['mode']),
          unorderedEquals([
            'notice-in',
            'notice-out',
            'event-in',
            'event-out',
            'event-cycle',
            'transition',
            if (skin == 'NightShadow') 'flow',
          ]),
        );
      }
      for (final dynamic clip in clips) {
        if (clip['skin'] == 'NightShadow' &&
            !File('assets/overlay-appearances/${clip['file']}').existsSync()) {
          continue;
        }
        final codec = await ui.instantiateImageCodec(
          File('assets/overlay-appearances/${clip['file']}').readAsBytesSync(),
        );
        expect(codec.frameCount, clip['frameCount']);
        final first = await codec.getNextFrame();
        expect(first.image.width, clip['width']);
        expect(first.image.height, clip['height']);
        if (clip['mode'] == 'transition') {
          expect(first.image.width, 2560);
          expect(first.image.height, 1440);
        }
        first.image.dispose();
        codec.dispose();
      }
    },
    skip: _privateArtworkOnly,
  );

  testWidgets(
    'browser selects actions and both released transitions without applying a skin',
    (tester) async {
      final window = _PreviewWindow();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppearanceMotionBrowser(
                context,
                'NightShadow',
                editorWindow: window,
              ),
              child: const Text('Browse'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Browse'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      String asset() => tester
          .widget<NativeAppearancePlayer>(find.byType(NativeAppearancePlayer))
          .asset;
      expect(asset(), endsWith('NightShadow-notice-in.webp'));
      for (final choice in [
        'Announcement out',
        'Event in',
        'Event out',
        'Startup transition',
      ]) {
        await tester.tap(find.byKey(const Key('appearance-motion-mode')));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.text(choice).last);
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.byType(NativeAppearancePlayer), findsNothing);
      await tester.tap(find.byKey(const Key('appearance-motion-skin')));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Fleet Standard').last);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(
        find.byKey(const Key('appearance-transition-fullscreen')),
      );
      await tester.pump();
      await tester.pump();
      expect(window.enters, 1);
      expect(asset(), endsWith('Default-transition.webp'));
      expect(
        tester
            .widget<NativeAppearancePlayer>(find.byType(NativeAppearancePlayer))
            .nativePixels,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(window.exits, greaterThanOrEqualTo(1));
      expect(
        find.byKey(const Key('appearance-transition-fullscreen')),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(NativeAppearancePlayer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('decoded playback supports pause, seeking and replay', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: NativeAppearancePlayer(
              asset: 'assets/overlay-appearances/Default-event-in.webp',
            ),
          ),
        ),
      ),
    );
    Future<void> decode() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pump();
    }

    await decode();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    final paused = tester.widget<Slider>(find.byType(Slider)).value;
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<Slider>(find.byType(Slider)).value, paused);
    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await decode();
    expect(
      tester.widget<Slider>(find.byType(Slider)).value,
      greaterThan(paused),
    );
    await tester.tap(find.text('Replay'));
    await decode();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    await tester.pumpWidget(const SizedBox());
    await decode();
    expect(tester.takeException(), isNull);
  }, skip: _privateArtworkOnly);

  testWidgets(
    'repeating player wraps the final frame and can pause at the boundary',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NativeAppearancePlayer(
              asset: 'assets/overlay-appearances/Default-event-cycle.webp',
              repeat: true,
            ),
          ),
        ),
      );
      Future<void> decode() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
      }

      await decode();
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(slider.max);
      slider.onChangeEnd!(slider.max);
      await decode();
      expect(tester.widget<Slider>(find.byType(Slider)).value, slider.max);
      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(seconds: 7));
      await decode();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
      await tester.tap(find.text('Pause'));
      await tester.pump(const Duration(seconds: 7));
      await decode();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
    skip: _privateArtworkOnly,
  );

  testWidgets(
    '2K decoder and viewport retain physical pixels even with Windows scaling',
    (tester) async {
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1.25;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NativeAppearancePlayer(
              asset: 'assets/overlay-appearances/Default-transition.webp',
              nativePixels: true,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 160)),
      );
      await tester.pump();
      final picture = tester.widget<RawImage>(find.byType(RawImage));
      expect(picture.image!.width, 2560);
      expect(picture.image!.height, 1440);
      expect(picture.fit, BoxFit.none);
      expect(picture.scale, 1.25);
      expect(tester.getSize(find.byType(RawImage)), const Size(2048, 1152));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
    skip: _privateArtworkOnly,
  );

  testWidgets('missing optional clip reports unavailable without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NativeAppearancePlayer(
            asset: 'assets/overlay-appearances/source-build-missing.webp',
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Preview unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _PreviewWindow implements OverlayEditorWindowPort {
  int enters = 0;
  int exits = 0;
  @override
  Future<void> enter() async {
    enters++;
  }

  @override
  Future<void> exit() async {
    exits++;
  }
}
