import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'local_hangar_images.dart';
import 'local_hangar_presentation.dart';
import 'local_hangar_ship_image.dart';
import 'local_hangar_image_cache.dart';

/// Visible cards only. Owner/instance/content keys survive metadata revisions.
class LocalHangarCardImage extends StatefulWidget {
  const LocalHangarCardImage({
    required this.item,
    required this.width,
    this.imagePort,
    this.height = 108,
    this.cache,
    this.cacheKey = '',
    super.key,
  });
  final LocalHangarPresentation item;
  final double width;
  final double height;
  final LocalHangarImageCache? cache;
  final String cacheKey;
  final LocalHangarImagePort? imagePort;
  @override
  State<LocalHangarCardImage> createState() => _LocalHangarCardImageState();
}

class _LocalHangarCardImageState extends State<LocalHangarCardImage> {
  Uint8List? _custom;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void didUpdateWidget(LocalHangarCardImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.cache != widget.cache ||
        (widget.cache == null && oldWidget.imagePort != widget.imagePort)) {
      ++_epoch;
      _custom = null;
      unawaited(_read());
    }
  }

  Future<void> _read({bool retryCurrentPort = true}) async {
    final epoch = _epoch, port = widget.imagePort;
    if (port == null) return;
    try {
      final bytes = widget.cache == null
          ? LocalHangarImageCache.decode(await port.readImage())
          : await widget.cache!.read(widget.cacheKey, port);
      if (mounted && epoch == _epoch) setState(() => _custom = bytes);
    } catch (_) {
      // A bookmark may advance Host's conditional-read revision while the
      // image request is pending. Retry only with the replacement port.
      if (retryCurrentPort &&
          mounted &&
          epoch == _epoch &&
          port != widget.imagePort) {
        await _read(retryCurrentPort: false);
      }
      /* Bundled art remains available; detail exposes image retry. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = LocalHangarShipImage(
      item: widget.item,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.contain,
    );
    return _custom == null
        ? fallback
        : Image.memory(
            _custom!,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            cacheWidth: (widget.width * MediaQuery.devicePixelRatioOf(context))
                .ceil(),
            errorBuilder: (_, _, _) => fallback,
          );
  }
}
