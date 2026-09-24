import 'package:flutter/material.dart';

import 'inline_image_cache.dart';

/// Bounded inline avatar from Host, never a file path or an external URL.
class EmbeddedAvatar extends StatefulWidget {
  const EmbeddedAvatar({
    required this.source,
    required this.fallback,
    super.key,
  });
  final String? source;
  final Widget fallback;

  @override
  State<EmbeddedAvatar> createState() => _EmbeddedAvatarState();
}

class _EmbeddedAvatarState extends State<EmbeddedAvatar> {
  MemoryImage? _image;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _decode();
  }

  @override
  void didUpdateWidget(EmbeddedAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _decode();
  }

  void _decode() {
    _image = null;
    final value = widget.source;
    if (value == null ||
        value.length > ((512 * 1024 + 2) ~/ 3 * 4) + 24 ||
        !(value.startsWith('data:image/png;base64,') ||
            value.startsWith('data:image/jpeg;base64,'))) {
      return;
    }
    _image = InlineImageCacheScope.resolve(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return widget.fallback;
    return Image(
      image: ResizeImage.resizeIfNeeded(
        InlineImageCache.decodeWidth,
        null,
        image,
      ),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: false,
      frameBuilder: (_, child, frame, synchronous) =>
          synchronous || frame != null ? child : widget.fallback,
      errorBuilder: (_, _, _) => widget.fallback,
    );
  }
}
