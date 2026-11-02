import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/native_appearance_player.dart';

class TinyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData(1);
}

final fixtureBundle = TinyBundle();

class TestFrame implements ui.FrameInfo {
  TestFrame(this.image);
  @override
  final ui.Image image;
  @override
  Duration get duration => const Duration(milliseconds: 40);
}

class ControlledCodec implements ui.Codec {
  ControlledCodec(this.image);
  final ui.Image image;
  bool hold = false, disposed = false;
  int requests = 0;
  final pending = <Completer<ui.FrameInfo>>[];
  @override
  int get frameCount => 3;
  @override
  int get repetitionCount => -1;
  @override
  Future<ui.FrameInfo> getNextFrame() {
    requests++;
    if (hold) {
      final c = Completer<ui.FrameInfo>();
      pending.add(c);
      return c.future;
    }
    return Future.value(TestFrame(image.clone()));
  }

  ui.Image finish() {
    final frame = image.clone();
    pending.removeAt(0).complete(TestFrame(frame));
    return frame;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

Future<ui.Image> tinyImage(WidgetTester t) async {
  return (await t.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()..color = Colors.white,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    picture.dispose();
    return image;
  }))!;
}

void main() {
  for (final stop in ['pause', 'reduce', 'ticker', 'lifecycle']) {
    testWidgets('pending decoded frame cannot advance after $stop', (t) async {
      final image = await tinyImage(t), codec = ControlledCodec(image);
      Future<ui.Codec> decode(Uint8List bytes, {int? targetWidth}) async =>
          codec;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        while (codec.pending.isNotEmpty) {
          codec.finish();
        }
        await t.pump();
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        image.dispose();
      });
      var reduce = false, ticker = true;
      late StateSetter update;
      await t.pumpWidget(
        DefaultAssetBundle(
          bundle: TinyBundle(),
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (c, s) {
                  update = s;
                  return MediaQuery(
                    data: MediaQuery.of(c).copyWith(disableAnimations: reduce),
                    child: TickerMode(
                      enabled: ticker,
                      child: NativeAppearancePlayer(
                        asset: 'assets/overlay-appearances/Default-event-cycle.webp',
                        repeat: true,
                        decoder: decode,
                        assetBundle: fixtureBundle,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await t.pump();
      await t.pump();
      expect(t.widget<Slider>(find.byType(Slider)).value, 0);
      codec.hold = true;
      await t.pump(const Duration(milliseconds: 40));
      expect(codec.pending.length, 1);
      if (stop == 'pause') {
        await t.tap(find.text('Pause'));
      } else if (stop == 'lifecycle') {
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      } else {
        update(() {
          if (stop == 'reduce') {
            reduce = true;
          } else {
            ticker = false;
          }
        });
      }
      await t.pump();
      codec.finish();
      await t.pump();
      await t.pump();
      expect(t.widget<Slider>(find.byType(Slider)).value, 0);
      expect(codec.requests, 2);
      if (stop == 'pause') {
        await t.tap(find.text('Play'));
      } else if (stop == 'lifecycle') {
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      } else {
        update(() {
          reduce = false;
          ticker = true;
        });
      }
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      expect(t.widget<Slider>(find.byType(Slider)).value, 1);
      expect(
        codec.requests,
        2,
        reason: 'resume uses retained next frame, not another decode',
      );
    });
  }
  testWidgets('rapid pause/play cannot start overlapping frame decodes', (
    t,
  ) async {
    final image = await tinyImage(t), codec = ControlledCodec(image);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      while (codec.pending.isNotEmpty) {
        codec.finish();
      }
      await t.pump();
      image.dispose();
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeAppearancePlayer(
            asset: 'assets/overlay-appearances/Default-event-cycle.webp',
            repeat: true,
            decoder: (_, {int? targetWidth}) async => codec,
            assetBundle: fixtureBundle,
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    codec.hold = true;
    await t.pump(const Duration(milliseconds: 40));
    for (var i = 0; i < 4; i++) {
      await t.tap(find.text('Pause'));
      await t.pump();
      await t.tap(find.text('Play'));
      await t.pump(const Duration(milliseconds: 40));
    }
    expect(codec.requests, 2);
    expect(codec.pending.length, 1);
    codec.finish();
    await t.pump();
    await t.pump();
    expect(t.widget<Slider>(find.byType(Slider)).value, 1);
    await t.tap(find.text('Pause'));
    await t.pump();
  });

  for (final action in ['dispose', 'replay', 'seek', 'swap', 'decoder']) {
    testWidgets('late frame cannot overwrite $action and is disposed', (
      t,
    ) async {
      final image = await tinyImage(t);
      final first = ControlledCodec(image), second = ControlledCodec(image);
      var calls = 0, swapped = false;
      late StateSetter update;
      Future<ui.Codec> decoder(Uint8List bytes, {int? targetWidth}) async =>
          calls++ == 0 ? first : second;
      Future<ui.Codec> replacement(Uint8List bytes, {int? targetWidth}) async =>
          second;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        for (final codec in [first, second]) {
          while (codec.pending.isNotEmpty) {
            codec.finish();
          }
        }
        await t.pump();
        image.dispose();
      });
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (c, s) {
                update = s;
                return NativeAppearancePlayer(
                  asset: swapped && action == 'swap'
                      ? 'assets/overlay-appearances/Default-transition.webp'
                      : 'assets/overlay-appearances/Default-event-cycle.webp',
                  repeat: true,
                  coveredInterval: (
                    const Duration(milliseconds: 40),
                    const Duration(milliseconds: 80),
                  ),
                  decoder: swapped && action == 'decoder'
                      ? replacement
                      : decoder,
                  assetBundle: fixtureBundle,
                );
              },
            ),
          ),
        ),
      );
      await t.pump();
      await t.pump();
      first.hold = true;
      await t.pump(const Duration(milliseconds: 40));
      expect(first.pending.length, 1);
      if (action == 'dispose') {
        await t.pumpWidget(const SizedBox());
      }
      if (action == 'replay') {
        await t.tap(find.text('Replay'));
      }
      if (action == 'swap' || action == 'decoder') {
        update(() => swapped = true);
      }
      if (action == 'seek') {
        final slider = t.widget<Slider>(find.byType(Slider));
        slider.onChanged!(2);
        slider.onChangeEnd!(2);
      }
      await t.pump();
      await t.pump();
      final lateFrame = first.finish();
      await t.pump();
      await t.pump();
      expect(lateFrame.debugDisposed, isTrue);
      expect(first.disposed, isTrue);
      if (action != 'dispose') {
        expect(
          t.widget<Slider>(find.byType(Slider)).value,
          action == 'seek' ? 2 : 0,
        );
      }
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('held frame is released on disposal without a covered callback', (
    t,
  ) async {
    final image = await tinyImage(t), codec = ControlledCodec(image);
    final covered = <bool>[];
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      while (codec.pending.isNotEmpty) {
        codec.finish();
      }
      await t.pump();
      image.dispose();
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeAppearancePlayer(
            asset: 'assets/overlay-appearances/Default-event-cycle.webp',
            repeat: true,
            coveredInterval: (
              const Duration(milliseconds: 40),
              const Duration(milliseconds: 80),
            ),
            onCoveredChanged: covered.add,
            decoder: (_, {int? targetWidth}) async => codec,
            assetBundle: fixtureBundle,
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    codec.hold = true;
    await t.pump(const Duration(milliseconds: 40));
    await t.tap(find.text('Pause'));
    await t.pump();
    final held = codec.finish();
    await t.pump();
    await t.pump();
    expect(held.debugDisposed, isFalse);
    expect(covered, isEmpty);
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(held.debugDisposed, isTrue);
    expect(codec.disposed, isTrue);
    expect(covered, isEmpty);
  });
  testWidgets('frame decode failure stops retries and replay recovers', (
    t,
  ) async {
    final image = await tinyImage(t),
        first = ControlledCodec(image),
        second = ControlledCodec(image);
    var calls = 0;
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      for (final codec in [first, second]) {
        while (codec.pending.isNotEmpty) {
          codec.finish();
        }
      }
      await t.pump();
      image.dispose();
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeAppearancePlayer(
            asset: 'assets/overlay-appearances/Default-event-cycle.webp',
            repeat: true,
            decoder: (_, {int? targetWidth}) async =>
                calls++ == 0 ? first : second,
            assetBundle: fixtureBundle,
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    first.hold = true;
    await t.pump(const Duration(milliseconds: 40));
    first.pending.removeAt(0).completeError(StateError('decode failed'));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Preview unavailable'), findsOneWidget);
    expect(first.requests, 2);
    await t.tap(find.text('Replay'));
    await t.pump();
    await t.pump();
    expect(find.text('Preview unavailable'), findsNothing);
    expect(t.widget<Slider>(find.byType(Slider)).value, 0);
    await t.tap(find.text('Pause'));
    await t.pump();
  });
}
