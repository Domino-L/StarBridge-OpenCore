import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'community_logo_port.dart';
import 'community_creation_copy.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../common/social_read_activity.dart';

class CommunityLogoCrop extends StatefulWidget {
  const CommunityLogoCrop({
    required this.port,
    required this.source,
    this.title,
    super.key,
  });
  final CommunityLogoPort port;
  final CommunityLogoSource source;
  final String? title;
  @override
  State<CommunityLogoCrop> createState() => _CommunityLogoCropState();
}

class _CommunityLogoCropState extends State<CommunityLogoCrop> {
  double size = 1, horizontal = .5, vertical = .5;
  bool busy = false, failed = false;
  InteractionSource _activitySource = InteractionSource.programmatic;
  int _activityRevision = 0;
  late final bytes = base64Decode(
    widget.source.previewImageData.split(',').last,
  );
  Future<void> apply() async {
    if (!mounted || busy) return;
    final finishSource = captureStarBridgeActivationCompletion();
    final sourceOfAction = currentStarBridgeActivationSource;
    setState(() {
      _activitySource = sourceOfAction;
      _activityRevision++;
      busy = true;
      failed = false;
    });
    final source = widget.source;
    final side = math.min(source.width, source.height) * size;
    try {
      final result = await widget.port.cropLogo(
        source.sourceRef,
        horizontal * (source.width - side) / source.width,
        vertical * (source.height - side) / source.height,
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

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              widget.title ?? creationText(context, 'crop'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(creationText(context, 'cropHint')),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final source = widget.source;
                  final scale = math.min(
                    constraints.maxWidth / source.width,
                    constraints.maxHeight / source.height,
                  );
                  final width = source.width * scale,
                      height = source.height * scale;
                  final side = math.min(width, height) * size;
                  return Center(
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Image.memory(bytes, fit: BoxFit.fill),
                          ),
                          Positioned(
                            left: horizontal * (width - side),
                            top: vertical * (height - side),
                            width: side,
                            height: side,
                            child: GestureDetector(
                              key: const Key('community-crop-drag'),
                              onPanUpdate: busy
                                  ? null
                                  : (details) => setState(() {
                                      if (busy) return;
                                      if (width > side) {
                                        horizontal =
                                            (horizontal +
                                                    details.delta.dx /
                                                        (width - side))
                                                .clamp(0, 1);
                                      }
                                      if (height > side) {
                                        vertical =
                                            (vertical +
                                                    details.delta.dy /
                                                        (height - side))
                                                .clamp(0, 1);
                                      }
                                    }),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
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
              ),
            ),
            for (final entry in [
              ('size', size, .2),
              ('horizontal', horizontal, 0.0),
              ('vertical', vertical, 0.0),
            ])
              Row(
                children: [
                  SizedBox(
                    width: 125,
                    child: Text(creationText(context, entry.$1)),
                  ),
                  Expanded(
                    child: StarBridgeFieldFrame(
                      enabled: !busy,
                      cursor: SystemMouseCursors.click,
                      builder: (_, focus) => Semantics(
                        key: ValueKey('crop-${entry.$1}-semantics'),
                        container: true,
                        label: creationText(context, entry.$1),
                        child: KeyedSubtree(
                          key: ValueKey(('crop-slider', entry.$1, busy)),
                          child: Slider(
                            focusNode: focus,
                            key: ValueKey('crop-${entry.$1}'),
                            value: entry.$2,
                            min: entry.$3,
                            onChanged: busy
                                ? null
                                : (value) => setState(() {
                                    if (busy) return;
                                    switch (entry.$1) {
                                      case 'size':
                                        size = value;
                                      case 'horizontal':
                                        horizontal = value;
                                      case 'vertical':
                                        vertical = value;
                                    }
                                  }),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            if (failed)
              Text(
                creationText(context, 'imageFailed'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            SizedBox(
              height: 4,
              child: busy
                  ? KeyedSubtree(
                      key: ValueKey(('profile-crop', _activityRevision)),
                      child: SocialReadActivity(
                        key: const ValueKey('profile-crop-activity'),
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
                  controlKey: const Key('community-crop-cancel'),
                  onActivate: busy
                      ? null
                      : (source) =>
                            dismissStarBridgeDialog(context, source: source),
                  child: Text(creationText(context, 'cancel')),
                ),
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.primary,
                  controlKey: const Key('community-crop-apply'),
                  onActivate: busy ? null : (_) => apply(),
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
