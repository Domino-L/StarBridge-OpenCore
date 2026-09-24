import '../../design_system/styles/home_scene_palette.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

class HomeSceneVideo extends StatefulWidget {
  const HomeSceneVideo({
    this.assetPath = 'assets/home-scenes/orison-night-loop-v1.mp4',
    super.key,
  });

  final String assetPath;

  @override
  State<HomeSceneVideo> createState() => _HomeSceneVideoState();
}

class _HomeSceneVideoState extends State<HomeSceneVideo>
    with WidgetsBindingObserver {
  // Local diagnostic build only: isolate native video from ordinary images.
  static const _posterOnly = bool.fromEnvironment('STARBRIDGE_HOME_POSTER_ONLY');
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _reduceMotion = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_posterOnly) unawaited(_initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        context.tokens.motion.surfaceEnter == Duration.zero;
    if (reduced == _reduceMotion) return;
    _reduceMotion = reduced;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (reduced || !_foreground) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.asset(widget.assetPath);
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(true);
      if (!mounted) return;
      await controller.setVolume(0);
      if (!mounted) return;
      if (!_reduceMotion && _foreground) await controller.play();
      if (mounted) setState(() {});
    } on Object {
      if (!mounted) return;
      await controller.dispose();
      if (identical(_controller, controller)) _controller = null;
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    unawaited(
      _foreground && !_reduceMotion ? controller.play() : controller.pause(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.dispose());
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_posterOnly) return const _HomeSceneFallback();
    final controller = _controller;
    if (_failed || controller == null || !controller.value.isInitialized) {
      return const _HomeSceneFallback();
    }
    final size = controller.value.size;
    return ColoredBox(
      color: HomeScenePalette.base,
      child: ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSceneFallback extends StatelessWidget {
  const _HomeSceneFallback();

  @override
  Widget build(BuildContext context) => Stack(
    key: const Key('home-scene-fallback'),
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [HomeScenePalette.fallbackStart, HomeScenePalette.base, HomeScenePalette.fallbackEnd],
            stops: [0, .58, 1],
          ),
        ),
      ),
      Image.asset(
        'assets/home-scenes/orison-night-poster-v1.jpg',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    ],
  );
}
