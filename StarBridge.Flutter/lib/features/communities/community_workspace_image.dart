import '../../design_system/icons/standard_icon.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_workspace_copy.dart';
import 'community_image_decoder.dart';

String _imageText(BuildContext context, String key) {
  final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
  final copy = communityWorkspaceCopy[key]!;
  if (locale.languageCode != 'zh') return copy.$3;
  return locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? copy.$2
      : copy.$1;
}

/// Decode a bounded first frame without Flutter's global ImageCache. The widget
/// owns its image handle; an optional conversation decoder can retain the frame.
class CommunityWorkspaceImage extends StatefulWidget {
  const CommunityWorkspaceImage({
    required this.bytes,
    required this.icon,
    this.maxWidth = 256,
    this.fit = BoxFit.cover,
    this.failureMessage,
    this.loading = false,
    this.loadFailed = false,
    this.decoder = decodeCommunityImage,
    super.key,
  });
  final Uint8List? bytes;
  final StandardIconSemantic icon;
  final int maxWidth;
  final BoxFit fit;
  final String? failureMessage;
  final bool loading, loadFailed;
  final CommunityImageDecoder decoder;
  @override
  State<CommunityWorkspaceImage> createState() =>
      _CommunityWorkspaceImageState();
}

class _CommunityWorkspaceImageState extends State<CommunityWorkspaceImage> {
  ui.Image? image;
  bool failed = false;
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_decode());
  }

  @override
  void didUpdateWidget(covariant CommunityWorkspaceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.maxWidth != widget.maxWidth ||
        oldWidget.decoder != widget.decoder) {
      image?.dispose();
      image = null;
      failed = false;
      unawaited(_decode());
    }
  }

  Future<void> _decode() async {
    final current = ++epoch, bytes = widget.bytes;
    if (bytes == null) return;
    try {
      final decoded = await widget.decoder(bytes, widget.maxWidth);
      if (!mounted || current != epoch) {
        decoded.dispose();
        return;
      }
      setState(() => image = decoded);
    } catch (_) {
      // Invalid/unsupported media uses a semantic fallback, never the app logo.
    } finally {
      if (mounted && current == epoch && image == null) {
        setState(() => failed = true);
      }
    }
  }

  @override
  void dispose() {
    epoch++;
    image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: image == null
        ? ColoredBox(
            color: context.tokens.surfaces.raised.fill,
            child: Center(
              child: widget.loading || (widget.bytes != null && !failed)
                  ? const CommunityImageLoading()
                  : (failed || widget.loadFailed) &&
                        widget.failureMessage != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        widget.failureMessage!,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Tooltip(
                      message: failed || widget.loadFailed
                          ? _imageText(context, 'imageFailed')
                          : '',
                      child: StandardIcon(
                        failed || widget.loadFailed
                            ? StandardIconSemantic.brokenImage
                            : widget.icon,
                        color: context.tokens.colors.textSecondary,
                      ),
                    ),
            ),
          )
        : RawImage(image: image, fit: widget.fit),
  );
}

/// Functional progress only: no layout animation and no motion when disabled.
class CommunityImageLoading extends StatelessWidget {
  const CommunityImageLoading({super.key});
  @override
  Widget build(BuildContext context) {
    final label = _imageText(context, 'imageLoading');
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.biggest.shortestSide;
            final size = available.isFinite
                ? (available * .45).clamp(10.0, 24.0)
                : 24.0;
            return Center(
              child: SizedBox.square(
                dimension: size,
                child: MediaQuery.disableAnimationsOf(context)
                    ? StandardIcon(
                        StandardIconSemantic.hourglassTop,
                        size: size,
                        color: context.tokens.colors.textSecondary,
                      )
                    : const RepaintBoundary(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}
