import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../interaction/starbridge_action_button.dart';
import '../interaction/starbridge_interaction_theme.dart';
import '../interaction/starbridge_slider.dart';

typedef NativeAppearanceDecoder = Future<ui.Codec> Function(
  Uint8List bytes, {
  int? targetWidth,
});

/// Single native clip, streamed frame by frame (never retains a full decoded
/// movie). No host requests, settings changes or synthetic overlay animations.
class NativeAppearancePlayer extends StatefulWidget {
  const NativeAppearancePlayer({
    required this.asset,
    this.controls = true,
    this.nativePixels = false,
    this.repeat = false,
    this.coveredInterval,
    this.onCoveredChanged,
    this.decoder = ui.instantiateImageCodec,
    this.assetBundle,
    super.key,
  });
  final String asset;
  final bool controls;
  final bool nativePixels;
  final bool repeat;
  final (Duration, Duration)? coveredInterval;
  final ValueChanged<bool>? onCoveredChanged;

  /// Internal decoding seam. Production uses the original engine codec;
  /// tests can hold a frame response without guessing a wall-clock delay.
  @visibleForTesting
  final NativeAppearanceDecoder decoder;

  /// Testing seam for fixtures without private artwork. Production keeps the
  /// original root bundle; this does not apply or persist an appearance.
  @visibleForTesting
  final AssetBundle? assetBundle;

  @override
  State<NativeAppearancePlayer> createState() => _NativeAppearancePlayerState();
}

class _NativeAppearancePlayerState extends State<NativeAppearancePlayer>
    with WidgetsBindingObserver {
  ui.Codec? _codec;
  ui.Image? _image;
  ui.FrameInfo? _readyFrame;
  bool _decoding = false;
  Timer? _timer;
  int _generation = 0;
  int _index = 0;
  int _displayedIndex = 0;
  int _count = 1;
  bool _playing = true;
  bool _allowed = true;
  bool _error = false;
  bool _covered = false;
  Duration _position = Duration.zero;
  Duration _frameDuration = const Duration(milliseconds: 40);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(NativeAppearancePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset ||
        oldWidget.nativePixels != widget.nativePixels ||
        oldWidget.repeat != widget.repeat ||
        oldWidget.decoder != widget.decoder ||
        oldWidget.assetBundle != widget.assetBundle) {
      _playing = true;
      unawaited(_load());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAllowed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _updateAllowed(state);

  void _updateAllowed([AppLifecycleState? state]) {
    final lifecycle = state ?? WidgetsBinding.instance.lifecycleState;
    final wasAllowed = _allowed;
    _allowed =
        !resolveStarBridgeInteraction(context).reduceMotion &&
        TickerMode.valuesOf(context).enabled &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    // Palette/suite rebuilds must not keep moving the next media deadline.
    if (wasAllowed == _allowed) return;
    _timer?.cancel();
    if (_allowed) _schedule();
    setState(() {});
  }

  Future<void> _load([int? seek]) async {
    _invalidateDecode();
    final generation = _generation;
    final asset = widget.asset;
    final decoder = widget.decoder;
    final nativePixels = widget.nativePixels;
    final bundle = widget.assetBundle ?? rootBundle;
    _decoding = true;
    ui.Codec? codec;
    try {
      final bytes = await bundle.load(asset);
      // Catalogs can decode smaller; fullscreen transitions keep every original
      // physical pixel. Streaming bounds retention to the current/next frame.
      codec = await decoder(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        targetWidth: nativePixels ? null : 1000,
      );
      if (!mounted || generation != _generation) {
        codec.dispose();
        return;
      }
      _codec = codec;
      _count = codec.frameCount;
      final target = (seek ?? (_allowed ? 0 : _count - 1)).clamp(0, _count - 1);
      var position = Duration.zero;
      for (var index = 0; index <= target; index++) {
        final frame = await codec.getNextFrame();
        if (!mounted || generation != _generation) {
          frame.image.dispose();
          return;
        }
        if (index < target) {
          position += frame.duration;
          frame.image.dispose();
          continue;
        }
        _replace(frame, index, position);
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = true);
    } finally {
      if (mounted && generation == _generation) {
        _decoding = false;
        _schedule();
      }
    }
  }

  void _invalidateDecode() {
    ++_generation;
    _timer?.cancel();
    _codec?.dispose();
    _codec = null;
    _readyFrame?.image.dispose();
    _readyFrame = null;
    _decoding = false;
  }

  void _replace(ui.FrameInfo frame, int index, Duration position) {
    final previous = _image;
    setState(() {
      _image = frame.image;
      _index = index;
      _displayedIndex = index;
      _frameDuration = frame.duration;
      _position = position;
      _error = false;
    });
    // RawImage still references the previous frame until the next build.
    final interval = widget.coveredInterval;
    final covered =
        interval != null && position >= interval.$1 && position < interval.$2;
    if (covered != _covered) {
      _covered = covered;
      widget.onCoveredChanged?.call(covered);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => previous?.dispose());
  }

  void _schedule() {
    if (!_allowed ||
        !_playing ||
        _codec == null ||
        _decoding ||
        _error ||
        _count <= 1 ||
        (!widget.repeat && _index >= _count - 1) ||
        _timer?.isActive == true) {
      return;
    }
    final generation = _generation;
    final codec = _codec!;
    _timer = Timer(_frameDuration, () async {
      _decoding = true;
      try {
        final ready = _readyFrame;
        _readyFrame = null;
        final frame = ready ?? await codec.getNextFrame();
        if (!mounted || generation != _generation) {
          frame.image.dispose();
          return;
        }
        // Keep one decoded frame while stopped: dropping it would advance the
        // codec cursor without advancing the displayed index on resume.
        if (!_allowed || !_playing) {
          _readyFrame = frame;
          return;
        }
        final nextIndex = (_index + 1) % _count;
        _replace(
          frame,
          nextIndex,
          nextIndex == 0 ? Duration.zero : _position + _frameDuration,
        );
      } catch (_) {
        if (mounted && generation == _generation) setState(() => _error = true);
      } finally {
        if (mounted && generation == _generation) {
          _decoding = false;
          _schedule();
        }
      }
    });
  }

  @override
  void dispose() {
    _invalidateDecode();
    _image?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _togglePlayback() {
    if (!_allowed) return;
    if (!widget.repeat && _index >= _count - 1) {
      _playing = true;
      unawaited(_load());
    } else {
      setState(() => _playing = !_playing);
      _timer?.cancel();
      _schedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final playbackLabel = _playing && (widget.repeat || _index < _count - 1)
        ? (zh ? '暂停' : 'Pause')
        : (zh ? '播放' : 'Play');
    final picture = _error
        ? Center(child: Text(zh ? '暂时无法播放预览' : 'Preview unavailable'))
        : RawImage(
            image: _image,
            scale: widget.nativePixels
                ? MediaQuery.devicePixelRatioOf(context)
                : 1,
            fit: widget.nativePixels ? BoxFit.none : BoxFit.contain,
            filterQuality: widget.nativePixels
                ? FilterQuality.none
                : FilterQuality.medium,
          );
    final controls = Row(
      children: [
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('native-appearance-playback'),
          semanticLabel: playbackLabel,
          onActivate: _allowed ? (_) => _togglePlayback() : null,
          child: Text(playbackLabel),
        ),
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('native-appearance-replay'),
          semanticLabel: zh ? '重播' : 'Replay',
          onActivate: (_) {
            _playing = _allowed;
            unawaited(_load());
          },
          child: Text(zh ? '重播' : 'Replay'),
        ),
        Expanded(
          child: StarBridgeSlider(
            controlKey: const Key('native-appearance-progress'),
            semanticLabel: zh ? '预览进度' : 'Preview progress',
            valueLabel: (value) => '${value.round() + 1} / $_count',
            keyboardStep: 1,
            value: _index.toDouble(),
            max: (_count - 1).clamp(1, 100000).toDouble(),
            onChanged: (value) {
              _playing = false;
              _invalidateDecode();
              setState(() => _index = value.round());
            },
            onChangeEnd: (value) => unawaited(_load(value.round())),
            onChangeCancel: () {
              setState(() => _index = _displayedIndex);
              unawaited(_load(_displayedIndex));
            },
          ),
        ),
      ],
    );
    if (widget.nativePixels) {
      // Controls overlay the image: never reduce its physical pixel viewport.
      return Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.space) {
            _togglePlayback();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(child: picture),
            if (widget.controls && !_covered)
              Positioned(
                left: 20,
                right: 20,
                bottom: 12,
                child: ColoredBox(
                  color: const Color(0xD0080F14),
                  child: controls,
                ),
              ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Expanded(child: picture),
        if (widget.controls) controls,
      ],
    );
  }
}
