import '../../design_system/icons/standard_icon.dart';

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

import 'community_workspace_copy.dart';
import 'community_image_decoder.dart';
import 'community_image_regressions.dart';
import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';

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
    this.waiting,
    this.decoder = decodeCommunityImage,
    this.peek,
    this.crop,
    super.key,
  });

  /// An already decoded frame for these bytes, used before decoding so a
  /// recycled list row or a refreshed row shows a seen image in the same frame.
  final CommunityImagePeek? peek;
  final Uint8List? bytes;
  final StandardIconSemantic icon;
  final int maxWidth;
  final BoxFit fit;
  final String? failureMessage;
  final bool loading, loadFailed;

  /// Optional presentation in the existing loading slot. Does not own decoding,
  /// requests or image handles; consumers without it keep their original view.
  final Widget? waiting;
  final CommunityImageDecoder decoder;
  final ({double focusX, double focusY, double zoom})? crop;
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
    if (!_adoptPeeked()) unawaited(_decode());
  }

  /// Takes an already decoded frame for the current bytes, if any.
  bool _adoptPeeked() {
    final bytes = widget.bytes;
    if (bytes == null) return false;
    final peeked = widget.peek?.call(bytes, widget.maxWidth);
    if (peeked == null) return false;
    epoch++;
    final previous = image;
    image = peeked;
    failed = false;
    previous?.dispose();
    markCommunityImageShown(bytes);
    return true;
  }

  @override
  void didUpdateWidget(covariant CommunityWorkspaceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sameContent =
        identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.bytes != null &&
            widget.bytes != null &&
            listEquals(oldWidget.bytes, widget.bytes);
    if (!sameContent ||
        oldWidget.maxWidth != widget.maxWidth ||
        oldWidget.decoder != widget.decoder) {
      if (widget.bytes == null) {
        // Confirmed absence: clear now.
        if (image != null) {
          recordCommunityImageRegression(LoadingImageRegression.cleared);
        }
        image?.dispose();
        image = null;
      }
      // Otherwise keep showing the current image until the new one decodes,
      // so a refresh never flashes the loading state (2026-10-20 report).
      failed = false;
      if (!_adoptPeeked()) unawaited(_decode());
    }
  }

  Future<void> _decode() async {
    final current = ++epoch, bytes = widget.bytes;
    if (bytes == null) return;
    var replaced = false;
    try {
      final decoded = await widget.decoder(bytes, widget.maxWidth);
      if (!mounted || current != epoch) {
        decoded.dispose();
        return;
      }
      final previous = image;
      setState(() => image = decoded);
      previous?.dispose();
      replaced = true;
      markCommunityImageShown(bytes);
    } catch (_) {
      // Invalid/unsupported media uses a semantic fallback, never the app logo.
    } finally {
      if (mounted && current == epoch && !replaced) {
        final previous = image;
        setState(() {
          image = null;
          failed = true;
        });
        previous?.dispose();
      }
    }
  }

  @override
  void dispose() {
    epoch++;
    image?.dispose();
    super.dispose();
  }

  bool _regressionRecorded = false;

  Widget _measured(Widget child) {
    final metrics = LoadingMetrics.current;
    if (metrics == null || metrics.stopped) return child;
    // Seen bytes waiting on a local decode again (recycled row, refresh):
    // the "shown, then loading" case, distinct from a first network load.
    final bytes = widget.bytes;
    if (image == null &&
        bytes != null &&
        !failed &&
        !_regressionRecorded &&
        communityImageWasShown(bytes)) {
      _regressionRecorded = true;
      recordCommunityImageRegression(LoadingImageRegression.redecode);
    }
    if (image != null) _regressionRecorded = false;
    return LoadingContentProbe(
      route: '/communities',
      visualPart: LoadingVisualPart.communityImage,
      status: image != null
          ? LoadingContentStatus.data
          : widget.loading || (widget.bytes != null && !failed)
          ? LoadingContentStatus.waiting
          : failed || widget.loadFailed
          ? LoadingContentStatus.failed
          : LoadingContentStatus.unavailable,
      items: image != null ? 1 : 0,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) => _measured(
    ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: image == null
          ? ColoredBox(
              color: context.tokens.surfaces.raised.fill,
              child: Center(
                child: widget.loading || (widget.bytes != null && !failed)
                    ? widget.waiting ?? const CommunityImageLoading()
                    : (failed || widget.loadFailed) &&
                          widget.failureMessage != null
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          widget.failureMessage!,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : StarBridgeTooltip(
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
          : widget.crop == null
          ? RawImage(image: image, fit: widget.fit)
          : LayoutBuilder(
              builder: (context, box) {
                final frame = widget.crop!;
                final source = image!;
                // Same cover/focus geometry as the existing WPF ShipImageCropView.
                final scale =
                    (box.maxWidth / source.width > box.maxHeight / source.height
                        ? box.maxWidth / source.width
                        : box.maxHeight / source.height) *
                    frame.zoom;
                final width = source.width * scale,
                    height = source.height * scale;
                return ClipRect(
                  child: Stack(
                    children: [
                      Positioned(
                        left:
                            -(width - box.maxWidth).clamp(0, double.infinity) *
                            frame.focusX,
                        top:
                            -(height - box.maxHeight).clamp(
                              0,
                              double.infinity,
                            ) *
                            frame.focusY,
                        width: width,
                        height: height,
                        child: RawImage(image: source, fit: BoxFit.fill),
                      ),
                    ],
                  ),
                );
              },
            ),
    ),
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
      child: StarBridgeTooltip(
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
                child: resolveStarBridgeInteraction(context).reduceMotion
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
