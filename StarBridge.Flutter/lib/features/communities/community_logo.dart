import 'package:flutter/material.dart';

import 'dart:typed_data';

import '../../shared/diagnostics/loading_metrics.dart';
import '../../shared/inline_image_cache.dart';
import 'community_image_regressions.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

class CommunityLogo extends StatefulWidget {
  const CommunityLogo({
    this.data,
    this.size = 40,
    this.framed = true,
    this.downloadedBy,
    super.key,
  });
  final String? data;
  final double size;
  final bool framed;

  /// Immutable source snapshot. Omit for originals or unclassified sources.
  final Object? downloadedBy;
  @override
  State<CommunityLogo> createState() => _CommunityLogoState();
}

class _CommunityLogoState extends State<CommunityLogo> {
  final _local = InlineImageCache();
  InlineImageCache? _scope;
  Uint8List? _bytes;

  /// A logo already painted stays visible while a re-resolved copy decodes
  /// (cache eviction, new row snapshot): no loading flash (2026-10-20 report).
  bool _shown = false;
  bool _regressionRecorded = false;
  void _resolve() {
    _bytes = (_scope ?? _local)
        .resolve(widget.data, downloadedBy: widget.downloadedBy)
        ?.bytes;
    if (_bytes == null) {
      if (_shown) {
        recordCommunityImageRegression(
          LoadingImageRegression.cleared,
          surface: LoadingImageSurface.communityLogo,
        );
      }
      _shown = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = InlineImageCacheScope.maybeOf(context);
    if (!identical(scope, _scope)) {
      _local.clear();
    }
    _scope = scope;
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CommunityLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        !identical(oldWidget.downloadedBy, widget.downloadedBy)) {
      if (_scope == null && oldWidget.data != widget.data) {
        _local.clear();
      }
      _resolve();
    }
  }

  @override
  void dispose() {
    _local.dispose();
    _bytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size, framed = widget.framed;
    final fallback = StarBridgeIcon(
      StarBridgeIconSemantic.community,
      size: size * .65,
    );
    Widget child = fallback;
    final bytes = _bytes;
    if (bytes != null) {
      child = Image.memory(
        bytes,
        fit: BoxFit.contain,
        cacheWidth: 128,
        gaplessPlayback: true,
        frameBuilder: (_, child, frame, synchronouslyLoaded) {
          if (synchronouslyLoaded || frame != null) {
            _shown = true;
            markCommunityImageShown(bytes);
          } else if (!_regressionRecorded && communityImageWasShown(bytes)) {
            _regressionRecorded = true;
            recordCommunityImageRegression(
              LoadingImageRegression.redecode,
              surface: LoadingImageSurface.communityLogo,
            );
          }
          // These bytes are already in memory: a local decode takes a frame or
          // two, so keep the slot quiet instead of a loading spinner (the
          // spinner means network waiting; 2026-10-21 "V 部分还会出现加载").
          return _shown ? child : const SizedBox.expand();
        },
        errorBuilder: (_, _, _) => fallback,
      );
    }
    if (!framed) {
      return SizedBox.square(
        dimension: size,
        child: ClipRRect(borderRadius: BorderRadius.circular(4), child: child),
      );
    }
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.tokens.surfaces.panel.fill,
        border: Border.all(color: context.tokens.surfaces.panel.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}
