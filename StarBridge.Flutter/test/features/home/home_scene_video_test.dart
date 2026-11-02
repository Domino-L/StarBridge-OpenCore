import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Tests the exact platform contract already supplied by video_player.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/home/home_scene.dart';
import 'package:starbridge_flutter/features/home/home_scene_video.dart';

void main() {
  late _VideoPlatform platform;
  setUp(() {
    final original = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = original);
  });

  if (const bool.fromEnvironment('STARBRIDGE_HOME_POSTER_ONLY')) {
    for (final scene in HomeScenes.values) {
      testWidgets('${scene.id} poster-only mode never initializes video', (
        tester,
      ) async {
        await tester.pumpWidget(_app(HomeSceneVideo(scene: scene)));
        await tester.pumpAndSettle();
        final image =
            tester.widget<Image>(find.byType(Image)).image as AssetImage;
        expect(image.assetName, scene.posterAsset);
        expect(platform.sources, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
    return;
  }

  for (final scene in HomeScenes.values) {
    testWidgets('${scene.id} initializes only its own muted looping video', (
      tester,
    ) async {
      await tester.pumpWidget(_app(HomeSceneVideo(scene: scene)));
      await tester.pumpAndSettle();
      expect(platform.sources.single.asset, scene.videoAsset);
      expect(platform.calls, contains('loop:true'));
      expect(
        platform.calls.lastIndexOf('volume:0.0'),
        lessThan(platform.calls.lastIndexOf('play')),
      );
      expect(find.byKey(const Key('test-video-view')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(
        () => platform.disposed.future.timeout(const Duration(seconds: 2)),
      );
      expect(platform.calls, contains('dispose'));
    });

    testWidgets('${scene.id} failure keeps its own still fallback', (
      tester,
    ) async {
      platform.fail = true;
      await tester.pumpWidget(_app(HomeSceneVideo(scene: scene)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-scene-fallback')), findsOneWidget);
      final image =
          tester.widget<Image>(find.byType(Image)).image as AssetImage;
      expect(image.assetName, scene.posterAsset);
      expect(platform.sources, hasLength(1));
      expect(platform.calls, isNot(contains('play')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  testWidgets('reduced motion pauses and never restarts in background', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const HomeSceneVideo(scene: HomeScenes.area18Dusk), reduced: true),
    );
    await tester.pumpAndSettle();
    expect(platform.calls, isNot(contains('play')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.calls, isNot(contains('play')));
    expect(platform.calls, contains('pause'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('background pauses; foreground resumes the same single player', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const HomeSceneVideo(scene: HomeScenes.area18Dusk)),
    );
    await tester.pumpAndSettle();
    platform.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(platform.calls, contains('pause'));
    platform.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.calls, contains('play'));
    expect(platform.sources, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'missing video and still retain a neutral surface without retrying another scene',
    (tester) async {
      platform.fail = true;
      await tester.pumpWidget(
        _app(
          const HomeSceneVideo(
            scene: HomeScene(
              id: 'synthetic-unavailable',
              videoAsset: 'assets/home-scenes/missing.mp4',
              posterAsset: 'assets/home-scenes/missing.jpg',
              locationKey: 'home.scene.area18',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-scene-fallback')), findsOneWidget);
      expect(platform.sources, hasLength(1));
      expect(find.byType(DecoratedBox), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}

Widget _app(Widget scene, {bool reduced = false}) {
  final tokens = StyleRegistry()
      .resolve('future-restraint-a', AppearanceMode.dark)
      .tokens;
  return MaterialApp(
    theme: buildStarBridgeTheme(tokens, const Locale('en')),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: SizedBox(width: 800, height: 300, child: scene),
    ),
  );
}

class _VideoPlatform extends VideoPlayerPlatform {
  final sources = <DataSource>[];
  final calls = <String>[];
  final events = <int, StreamController<VideoEvent>>{};
  final disposed = Completer<void>();
  bool fail = false;

  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = sources.length;
    sources.add(options.dataSource);
    final stream = events[id] = StreamController<VideoEvent>();
    if (fail) {
      stream.addError(
        PlatformException(
          code: 'fixture-unavailable',
          message: 'Synthetic unavailable video',
        ),
      );
    } else {
      stream.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 11),
          size: const Size(2560, 1440),
        ),
      );
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    if (!disposed.isCompleted) disposed.complete();
    await events[playerId]!.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      calls.add('loop:$looping');
  @override
  Future<void> setVolume(int playerId, double volume) async =>
      calls.add('volume:$volume');
  @override
  Future<void> play(int playerId) async => calls.add('play');
  @override
  Future<void> pause(int playerId) async => calls.add('pause');
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(key: Key('test-video-view'), color: Colors.black);
}
