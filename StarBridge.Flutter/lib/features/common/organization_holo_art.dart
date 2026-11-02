import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../shared/remote_image.dart';

/// Where an organization's banner, background or logo comes from, so the
/// main fleet and communities share one holo shell (user decision
/// 2026-10-23: "组织页面应该和主舰队用同一套外观"): a remote URL (the main
/// fleet's RSI images) or bytes the community source already read.
sealed class OrganizationHoloArt {
  const OrganizationHoloArt();

  const factory OrganizationHoloArt.url(String url) = _UrlArt;

  factory OrganizationHoloArt.bytes(Uint8List bytes) = _BytesArt;

  /// Null-tolerant helpers for callers whose image may be missing.
  static OrganizationHoloArt? fromUrl(String? url) =>
      url == null || url.isEmpty ? null : OrganizationHoloArt.url(url);

  static OrganizationHoloArt? fromBytes(Uint8List? bytes) =>
      bytes == null || bytes.isEmpty ? null : OrganizationHoloArt.bytes(bytes);

  Widget image({
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    int? cacheWidth,
    bool gaplessPlayback = false,
    bool excludeFromSemantics = false,
    ImageErrorWidgetBuilder? errorBuilder,
    FilterQuality filterQuality = FilterQuality.medium,
    Animation<double>? opacity,
  });
}

final class _UrlArt extends OrganizationHoloArt {
  const _UrlArt(this.url);

  final String url;

  @override
  Widget image({
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    int? cacheWidth,
    bool gaplessPlayback = false,
    bool excludeFromSemantics = false,
    ImageErrorWidgetBuilder? errorBuilder,
    FilterQuality filterQuality = FilterQuality.medium,
    Animation<double>? opacity,
  }) => RemoteImage(
    url,
    kind: RemoteImageResourceKind.organization,
    fit: fit,
    alignment: alignment,
    cacheWidth: cacheWidth,
    gaplessPlayback: gaplessPlayback,
    excludeFromSemantics: excludeFromSemantics,
    errorBuilder: errorBuilder,
    filterQuality: filterQuality,
    opacity: opacity,
  );

  @override
  bool operator ==(Object other) => other is _UrlArt && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

final class _BytesArt extends OrganizationHoloArt {
  _BytesArt(this.bytes);

  final Uint8List bytes;

  @override
  Widget image({
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    int? cacheWidth,
    bool gaplessPlayback = false,
    bool excludeFromSemantics = false,
    ImageErrorWidgetBuilder? errorBuilder,
    FilterQuality filterQuality = FilterQuality.medium,
    Animation<double>? opacity,
  }) {
    Widget decoded(int? width) => Image.memory(
      bytes,
      fit: fit,
      alignment: alignment,
      cacheWidth: width,
      gaplessPlayback: gaplessPlayback,
      excludeFromSemantics: excludeFromSemantics,
      errorBuilder: errorBuilder,
      filterQuality: filterQuality,
      opacity: opacity,
    );
    if (cacheWidth != null) return decoded(cacheWidth);
    // Community banners and backgrounds arrive at full size (up to 2 MiB of
    // JPEG); decoding them at their shown size keeps each layer small.
    return _DisplaySizedImage(bytes: bytes, fit: fit, builder: decoded);
  }

  // The same read bytes are the same art; a new read is a new image.
  @override
  bool operator ==(Object other) =>
      other is _BytesArt && identical(other.bytes, bytes);

  @override
  int get hashCode => identityHashCode(bytes);
}

/// Decodes community art at the size it is shown: the cover (or contain)
/// scale of the box times the device pixel ratio, rounded up to 256px so a
/// window resize does not re-decode on every frame.
class _DisplaySizedImage extends StatefulWidget {
  const _DisplaySizedImage({
    required this.bytes,
    required this.fit,
    required this.builder,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final Widget Function(int? cacheWidth) builder;

  @override
  State<_DisplaySizedImage> createState() => _DisplaySizedImageState();
}

class _DisplaySizedImageState extends State<_DisplaySizedImage> {
  // Header-only reads, shared by every layer showing the same bytes.
  static final _sizes = Expando<Future<Size?>>();
  Size? _source;
  bool _unknown = false;
  // The largest decode width used so far (null once at full size). A shrinking
  // box (the deck collapsing during the screen switch) keeps this decode;
  // only a larger box decodes again (2026-10-28: re-decoding on every bucket
  // stalled the end of the community switch).
  bool _decided = false;
  int? _width;

  static Future<Size?> _read(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      buffer.dispose();
      return size.isEmpty ? null : size;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void didUpdateWidget(_DisplaySizedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _decided = false;
      _width = null;
      _measure();
    }
  }

  void _measure() {
    final bytes = widget.bytes;
    final pending = _sizes[bytes] ??= _read(bytes);
    pending.then((size) {
      if (!mounted || !identical(bytes, widget.bytes)) return;
      setState(() {
        _source = size;
        _unknown = size == null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // An unreadable header falls back to the plain decode and its error path.
    if (_unknown) return widget.builder(null);
    final source = _source;
    if (source == null) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, box) {
        if (!box.hasBoundedWidth || !box.hasBoundedHeight) {
          return widget.builder(null);
        }
        final sx = box.maxWidth / source.width,
            sy = box.maxHeight / source.height;
        final scale = widget.fit == BoxFit.contain
            ? math.min(sx, sy)
            : math.max(sx, sy);
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final wanted = source.width * scale * dpr;
        final width = math.min(
          source.width.round(),
          math.max(256, (wanted / 256).ceil() * 256),
        );
        final full = width >= source.width;
        if (!_decided) {
          _decided = true;
          _width = full ? null : width;
        } else if (_width != null && (full || width > _width!)) {
          _width = full ? null : width;
        }
        return widget.builder(_width);
      },
    );
  }
}
