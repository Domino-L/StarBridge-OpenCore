import 'package:flutter/material.dart';

import 'dart:typed_data';

import '../../shared/inline_image_cache.dart';
import 'community_workspace_image.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

class CommunityLogo extends StatefulWidget {
  const CommunityLogo({
    this.data,
    this.size = 40,
    this.framed = true,
    super.key,
  });
  final String? data;
  final double size;
  final bool framed;
  @override
  State<CommunityLogo> createState() => _CommunityLogoState();
}

class _CommunityLogoState extends State<CommunityLogo> {
  Uint8List? _bytes;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes = InlineImageCacheScope.resolve(context, widget.data)?.bytes;
  }

  @override
  void didUpdateWidget(covariant CommunityLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _bytes = InlineImageCacheScope.resolve(context, widget.data)?.bytes;
    }
  }

  @override
  void dispose() {
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
        frameBuilder: (_, child, frame, synchronouslyLoaded) =>
            synchronouslyLoaded || frame != null
            ? child
            : const CommunityImageLoading(),
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
