import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'community_creation_copy.dart';
import 'community_logo_port.dart';
import 'community_wide_image_port.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../common/social_read_activity.dart';

/// Fixed-ratio crop for banners (4:1) and backgrounds (16:9).
class CommunityWideImageCrop extends StatefulWidget {
  const CommunityWideImageCrop({
    required this.port,
    required this.source,
    required this.kind,
    required this.title,
    super.key,
  });
  final CommunityWideImagePort port;
  final CommunityLogoSource source;
  final String kind, title;
  @override
  State<CommunityWideImageCrop> createState() => _CommunityWideImageCropState();
}

class _CommunityWideImageCropState extends State<CommunityWideImageCrop> {
  late final aspect = communityWideImageAspect[widget.kind]!;
  late final bytes = base64Decode(
    widget.source.previewImageData.split(',').last,
  );

  /// Widest crop that still fits the source height at this ratio.
  late final double maxSize = math.min(
    1,
    widget.source.height * aspect / widget.source.width,
  );
  late double size = maxSize;
  double horizontal = .5, vertical = .5;
  bool busy = false, failed = false;
  InteractionSource _activitySource = InteractionSource.programmatic;
  int _activityRevision = 0;

  bool get usable => maxSize >= .2;
  double get _cropHeight => widget.source.width * size / aspect;

  Future<void> apply() async {
    if (!mounted || busy || !usable) return;
    final finishSource = captureStarBridgeActivationCompletion();
    final sourceOfAction = currentStarBridgeActivationSource;
    setState(() {
      _activitySource = sourceOfAction;
      _activityRevision++;
      busy = true;
      failed = false;
    });
    final source = widget.source;
    // Rounding must never push the frame past an edge the Host rejects.
    final yRange = math.max(0.0, (source.height - _cropHeight) / source.height);
    try {
      final result = await widget.port.cropWideImage(
        source.sourceRef,
        widget.kind,
        (horizontal * (1 - size)).clamp(0.0, 1 - size),
        (vertical * yRange).clamp(0.0, yRange),
        size,
      );
      if (mounted) {
        finishSource(sourceOfAction);
        dismissStarBridgeDialog(
          context,
          source: sourceOfAction,
          result: result,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          failed = true;
        });
      }
    }
  }

  void _drag(DragUpdateDetails details, double width, double height) {
    if (busy) return;
    final frameWidth = width * size, frameHeight = frameWidth / aspect;
    setState(() {
      if (width > frameWidth) {
        horizontal = (horizontal + details.delta.dx / (width - frameWidth))
            .clamp(0, 1);
      }
      if (height > frameHeight) {
        vertical = (vertical + details.delta.dy / (height - frameHeight)).clamp(
          0,
          1,
        );
      }
    });
  }

  Widget _preview() => LayoutBuilder(
    builder: (context, constraints) {
      final source = widget.source;
      final scale = math.min(
        constraints.maxWidth / source.width,
        constraints.maxHeight / source.height,
      );
      final width = source.width * scale, height = source.height * scale;
      final frameWidth = width * size, frameHeight = frameWidth / aspect;
      return Center(
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                ),
              ),
              if (usable)
                Positioned(
                  left: horizontal * (width - frameWidth),
                  top: vertical * (height - frameHeight),
                  width: frameWidth,
                  height: frameHeight,
                  child: GestureDetector(
                    key: const Key('community-wide-crop-drag'),
                    onPanUpdate: busy
                        ? null
                        : (details) => _drag(details, width, height),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        color: Colors.white.withValues(alpha: .08),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _slider(String key, double value, double min, double max) => Row(
    children: [
      SizedBox(width: 125, child: Text(creationText(context, key))),
      Expanded(
        child: StarBridgeFieldFrame(
          enabled: !busy,
          cursor: SystemMouseCursors.click,
          builder: (_, focus) => Semantics(
            key: ValueKey('wide-crop-$key-semantics'),
            container: true,
            label: creationText(context, key),
            child: KeyedSubtree(
              key: ValueKey(('wide-crop-slider', key, busy)),
              child: Slider(
                focusNode: focus,
                key: ValueKey('wide-crop-$key'),
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: busy || max <= min
                    ? null
                    : (next) => setState(() {
                        if (busy) return;
                        switch (key) {
                          case 'size':
                            size = next;
                          case 'horizontal':
                            horizontal = next;
                          case 'vertical':
                            vertical = next;
                        }
                      }),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 880, maxHeight: 760),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            Text(creationText(context, 'cropHint')),
            const SizedBox(height: 12),
            Expanded(child: _preview()),
            if (usable) ...[
              _slider('size', size, .2, maxSize),
              _slider('horizontal', horizontal, 0, 1),
              _slider('vertical', vertical, 0, 1),
            ],
            if (failed || !usable)
              Text(
                creationText(context, 'imageFailed'),
                key: const Key('community-wide-crop-failed'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            SizedBox(
              height: 4,
              child: busy
                  ? KeyedSubtree(
                      key: ValueKey(('wide-crop', _activityRevision)),
                      child: SocialReadActivity(
                        key: const ValueKey('wide-crop-activity'),
                        source: _activitySource,
                        opening: false,
                        label: creationText(context, 'cropping'),
                        height: 4,
                      ),
                    )
                  : null,
            ),
            OverflowBar(
              spacing: 8,
              children: [
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: const Key('community-wide-crop-cancel'),
                  onActivate: busy
                      ? null
                      : (source) =>
                            dismissStarBridgeDialog(context, source: source),
                  child: Text(creationText(context, 'cancel')),
                ),
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.primary,
                  controlKey: const Key('community-wide-crop-apply'),
                  onActivate: busy || !usable ? null : (_) => apply(),
                  child: Text(creationText(context, 'useImage')),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
