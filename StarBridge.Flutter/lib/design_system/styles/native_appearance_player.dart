import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    super.key,
  });
  final String asset;
  final bool controls;
  final bool nativePixels;
  final bool repeat;
  final (Duration, Duration)? coveredInterval;
  final ValueChanged<bool>? onCoveredChanged;

  @override
  State<NativeAppearancePlayer> createState() => _NativeAppearancePlayerState();
}

class _NativeAppearancePlayerState extends State<NativeAppearancePlayer>
    with WidgetsBindingObserver {
  ui.Codec? _codec;
  ui.Image? _image;
  Timer? _timer;
  int _generation = 0;
  int _index = 0;
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
        oldWidget.repeat != widget.repeat) {
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
    _allowed =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    _timer?.cancel();
    if (_allowed) _schedule();
  }

  Future<void> _load([int? seek]) async {
    final generation = ++_generation;
    _timer?.cancel();
    _codec?.dispose();
    _codec = null;
    ui.Codec? codec;
    try {
      final bytes = await rootBundle.load(widget.asset);
      // Catalogs can decode smaller; fullscreen transitions keep every original
      // physical pixel. Streaming bounds retention to the current/next frame.
      codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        targetWidth: widget.nativePixels ? null : 1000,
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
      _schedule();
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = true);
    }
  }

  void _replace(ui.FrameInfo frame, int index, Duration position) {
    final previous = _image;
    setState(() {
      _image = frame.image;
      _index = index;
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
        _count <= 1 ||
        (!widget.repeat && _index >= _count - 1) ||
        _timer?.isActive == true) {
      return;
    }
    final generation = _generation;
    _timer = Timer(_frameDuration, () async {
      try {
        final frame = await _codec!.getNextFrame();
        if (!mounted || generation != _generation) {
          frame.image.dispose();
          return;
        }
        final nextIndex = (_index + 1) % _count;
        _replace(
          frame,
          nextIndex,
          nextIndex == 0 ? Duration.zero : _position + _frameDuration,
        );
        _schedule();
      } catch (_) {
        if (mounted && generation == _generation) setState(() => _error = true);
      }
    });
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    _codec?.dispose();
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
        TextButton(
          onPressed: _allowed ? _togglePlayback : null,
          child: Text(
            _playing && (widget.repeat || _index < _count - 1)
                ? (zh ? '暂停' : 'Pause')
                : (zh ? '播放' : 'Play'),
          ),
        ),
        TextButton(
          onPressed: () {
            _playing = _allowed;
            unawaited(_load());
          },
          child: Text(zh ? '重播' : 'Replay'),
        ),
        Expanded(
          child: Slider(
            value: _index.toDouble(),
            max: (_count - 1).clamp(1, 100000).toDouble(),
            onChanged: (value) {
              _playing = false;
              _timer?.cancel();
              setState(() => _index = value.round());
            },
            onChangeEnd: (value) => unawaited(_load(value.round())),
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
