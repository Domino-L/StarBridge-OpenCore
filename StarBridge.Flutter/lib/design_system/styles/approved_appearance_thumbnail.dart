import '../icons/standard_icon.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Samples the approved artwork without resizing the complete atlas to 34px.
/// AssetImage uses Flutter's shared decoded-image cache across all entries.
class ApprovedAppearanceThumbnail extends StatefulWidget {
  const ApprovedAppearanceThumbnail({
    required this.skinId,
    this.imageProvider = const AssetImage(assetPath),
    super.key,
  });

  static const assetPath = 'assets/overlay-appearances/approved-board.png';
  final String skinId;
  final ImageProvider imageProvider;

  @override
  State<ApprovedAppearanceThumbnail> createState() =>
      _ApprovedAppearanceThumbnailState();
}

class _ApprovedAppearanceThumbnailState
    extends State<ApprovedAppearanceThumbnail> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ApprovedAppearanceThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) _resolve();
  }

  void _resolve() {
    final next = widget.imageProvider.resolve(
      createLocalImageConfiguration(context),
    );
    if (_stream?.key == next.key) return;
    _detach();
    _info?.dispose();
    _info = null;
    _failed = false;
    _stream = next;
    _listener = ImageStreamListener(
      (info, synchronous) {
        _info?.dispose();
        _info = info;
        _failed = false;
        if (!synchronous && mounted) setState(() {});
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (mounted) setState(() => _failed = true);
      },
    );
    next.addListener(_listener!);
  }

  void _detach() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _listener = null;
    _stream = null;
  }

  @override
  void dispose() {
    _detach();
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = ApprovedAppearancePainter.regions[widget.skinId];
    final image = _info?.image;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 34,
        child: source == null || _failed
            ? const StandardIcon(StandardIconSemantic.layers, size: 22)
            : image == null
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : CustomPaint(
                painter: ApprovedAppearancePainter(
                  atlas: image,
                  skinId: widget.skinId,
                ),
              ),
      ),
    );
  }
}

class ApprovedAppearancePainter extends CustomPainter {
  const ApprovedAppearancePainter({required this.atlas, required this.skinId});

  final ui.Image atlas;
  final String skinId;
  static const regions = <String, Rect>{
    'Default': Rect.fromLTWH(106, 128, 464, 464),
    'NightShadow': Rect.fromLTWH(652, 128, 464, 464),
    'Verdict': Rect.fromLTWH(1203, 128, 464, 464),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final source = regions[skinId];
    if (source == null || size.isEmpty) return;
    final side = size.shortestSide;
    canvas.drawImageRect(
      atlas,
      source,
      Rect.fromLTWH(
        (size.width - side) / 2,
        (size.height - side) / 2,
        side,
        side,
      ),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(covariant ApprovedAppearancePainter oldDelegate) =>
      oldDelegate.atlas != atlas || oldDelegate.skinId != skinId;
}
