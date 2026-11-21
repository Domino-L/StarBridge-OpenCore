import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// One small, preblurred texture per mounted background. No filter enters the
/// live layer tree. The provider, crop, blur and logical window size form the
/// cache key; darkening is applied by UserBackgroundLayer above this texture.
class CachedUserBackground extends StatefulWidget {
  const CachedUserBackground({
    required this.provider,
    required this.logicalSize,
    required this.sigma,
    required this.alignment,
    super.key,
  });

  static const maxDimension = 512;
  final ImageProvider provider;
  final Size logicalSize;
  final double sigma;
  final Alignment alignment;

  @override
  State<CachedUserBackground> createState() => _CachedUserBackgroundState();
}

class _CachedUserBackgroundState extends State<CachedUserBackground> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _texture;
  int _generation = 0;
  Timer? _resize;

  /// A window drag changes the size every frame: keep the current texture
  /// (it is stretched) and bake once the size has rested (review
  /// CX-C-FULL-073-REVIEW P2-2).
  static const resizeRest = Duration(milliseconds: 200);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(CachedUserBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      // A different picture: never show the old one meanwhile.
      _resize?.cancel();
      _texture?.dispose();
      _texture = null;
      _resolve();
    } else if (oldWidget.sigma != widget.sigma ||
        oldWidget.alignment != widget.alignment) {
      _resize?.cancel();
      _resolve();
    } else if (oldWidget.logicalSize != widget.logicalSize) {
      _resize?.cancel();
      _resize = Timer(resizeRest, () {
        if (mounted) _resolve();
      });
    }
  }

  void _detach() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  void _resolve() {
    final generation = ++_generation;
    _detach();
    // The current texture stays until the new one is baked.
    if (widget.logicalSize.isEmpty || !widget.logicalSize.isFinite) return;
    final configuration = createLocalImageConfiguration(context);
    final request = widget;
    final stream = request.provider.resolve(configuration);
    var accepted = false;
    _stream = stream;
    _listener = ImageStreamListener(
      (info, synchronous) {
        if (accepted || !mounted || generation != _generation) {
          info.dispose();
          return;
        }
        accepted = true;
        _detach();
        _bake(info, generation, request);
      },
      onError: (Object error, StackTrace? stack) {
        if (generation == _generation) _detach();
      },
    );
    stream.addListener(_listener!);
  }

  Future<void> _bake(
    ImageInfo source,
    int generation,
    CachedUserBackground request,
  ) async {
    ui.PictureRecorder? recorder;
    ui.Picture? picture;
    ui.Image? result;
    try {
      final size = request.logicalSize;
      final scale = math.min(
        1.0,
        CachedUserBackground.maxDimension / size.longestSide,
      );
      final width = math.max(1, (size.width * scale).ceil());
      final height = math.max(1, (size.height * scale).ceil());
      final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.saveLayer(
        rect,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: request.sigma * scale,
            sigmaY: request.sigma * scale,
            tileMode: TileMode.clamp,
          ),
      );
      paintImage(
        canvas: canvas,
        rect: rect,
        image: source.image,
        fit: BoxFit.cover,
        alignment: request.alignment,
        filterQuality: FilterQuality.medium,
      );
      canvas.restore();
      picture = recorder.endRecording();
      result = await picture.toImage(width, height);
      if (!mounted || generation != _generation) return;
      final completed = result;
      result = null;
      setState(() {
        _texture?.dispose();
        _texture = completed;
      });
    } catch (_) {
      // Like the full-quality Image.errorBuilder: a missing/undecodable local
      // image leaves the existing scrim. Never fall back to a live blur.
    } finally {
      result?.dispose();
      picture?.dispose();
      if (recorder?.isRecording == true) recorder!.endRecording().dispose();
      source.dispose();
    }
  }

  @override
  void dispose() {
    _resize?.cancel();
    ++_generation;
    _detach();
    _texture?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawImage(
    key: const Key('user-background-cached-blur'),
    image: _texture,
    fit: BoxFit.fill,
    filterQuality: FilterQuality.medium,
  );
}
