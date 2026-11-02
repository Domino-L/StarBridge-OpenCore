import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'remote_image_loader.dart';
export 'remote_image_disk_cache.dart' show RemoteImageResourceKind;

class RemoteImageScope extends InheritedWidget {
  const RemoteImageScope({
    required this.loader,
    required super.child,
    super.key,
  });
  final RemoteImageLoader loader;
  static RemoteImageLoader? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RemoteImageScope>()?.loader;
  @override
  bool updateShouldNotify(RemoteImageScope oldWidget) =>
      loader != oldWidget.loader;
}

/// Original rendering/fallback choices, without NetworkImage's second channel.
class RemoteImage extends StatefulWidget {
  const RemoteImage(
    this.source, {
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.cacheHeight,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.gaplessPlayback = false,
    this.errorBuilder,
    this.loadingBuilder,
    this.kind = RemoteImageResourceKind.other,
    this.followRedirects = true,
    this.filterQuality = FilterQuality.medium,
    this.opacity,
    super.key,
  });

  /// Upscaling quality: a tiny decode drawn large with [FilterQuality.high]
  /// gives a soft blur without an image filter layer.
  final FilterQuality filterQuality;

  /// Image-level opacity: no offscreen layer, unlike an Opacity widget.
  final Animation<double>? opacity;
  final String source;
  final RemoteImageResourceKind kind;

  /// False for addresses whose host was vetted upstream (an RSI avatar the
  /// Host validated): a redirect then fails instead of leaving that host.
  final bool followRedirects;
  final double? width, height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final int? cacheWidth, cacheHeight;
  final String? semanticLabel;
  final bool excludeFromSemantics, gaplessPlayback;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// Shown until the first read answers; without it, [errorBuilder] shows from
  /// the start. A later reread of a failed image does not bring it back.
  final WidgetBuilder? loadingBuilder;
  @override
  State<RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<RemoteImage> {
  RemoteImageLoader? _loader;
  Uint8List? _bytes;
  bool _answered = false;
  int _epoch = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = RemoteImageScope.of(context);
    if (identical(next, _loader)) return;
    _loader?.removeListener(_changed);
    _loader?.rereads.removeListener(_rereadDue);
    _loader = next;
    _answered = false;
    next?.addListener(_changed);
    next?.rereads.addListener(_rereadDue);
    _read();
  }

  void _changed() {
    _read();
  }

  void _rereadDue() {
    if (_loader?.rereadDue(
          widget.source,
          kind: widget.kind,
          followRedirects: widget.followRedirects,
        ) ==
        true) {
      _read();
    }
  }

  Future<void> _read() async {
    final epoch = ++_epoch, loader = _loader;
    if (mounted) {
      setState(
        () => _bytes = loader?.cached(
          widget.source,
          kind: widget.kind,
          followRedirects: widget.followRedirects,
        ),
      );
    }
    if (loader == null) return;
    final bytes = await loader.load(
      widget.source,
      kind: widget.kind,
      followRedirects: widget.followRedirects,
    );
    if (mounted && epoch == _epoch && identical(loader, _loader)) {
      setState(() {
        _bytes = bytes;
        _answered = true;
      });
    }
  }

  @override
  void didUpdateWidget(RemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.kind != widget.kind ||
        oldWidget.followRedirects != widget.followRedirects) {
      _bytes = null;
      _answered = false;
      _read();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _loader?.removeListener(_changed);
    _loader?.rereads.removeListener(_rereadDue);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      final waiting = widget.loadingBuilder;
      if (waiting != null && _loader != null && !_answered) {
        return waiting(context);
      }
      return widget.errorBuilder?.call(
            context,
            StateError('Remote image unavailable'),
            null,
          ) ??
          SizedBox(width: widget.width, height: widget.height);
    }
    return Image.memory(
      bytes,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      semanticLabel: widget.semanticLabel,
      excludeFromSemantics: widget.excludeFromSemantics,
      gaplessPlayback: widget.gaplessPlayback,
      errorBuilder: widget.errorBuilder,
      filterQuality: widget.filterQuality,
      opacity: widget.opacity,
    );
  }
}
