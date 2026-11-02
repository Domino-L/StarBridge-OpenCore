import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../common/social_read_activity.dart';

/// Captures the admitted read's origin once. The original directory and workspace
/// retain their different Standard static indicators and sizing.
class CommunityInitialReadWait extends StatefulWidget {
  const CommunityInitialReadWait.directory({
    required this.source,
    required this.opening,
    required this.label,
    super.key,
  }) : _workspace = false;
  const CommunityInitialReadWait.workspace({
    required this.source,
    required this.opening,
    required this.label,
    super.key,
  }) : _workspace = true;

  final InteractionSource source;
  final bool opening;
  final String label;
  final bool _workspace;
  @override
  State<CommunityInitialReadWait> createState() =>
      _CommunityInitialReadWaitState();
}

class _CommunityInitialReadWaitState extends State<CommunityInitialReadWait> {
  InteractionSource? _source;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _source ??= widget.opening
        ? resolveStarBridgeInitialReadSource(context, widget.source)
        : widget.source;
  }

  @override
  Widget build(BuildContext context) {
    final data = resolveStarBridgeInteraction(context);
    final animated =
        !data.reduceMotion &&
        _source != InteractionSource.keyboard &&
        (widget.opening || _source == InteractionSource.pointer);
    if (widget._workspace && data.suite == InteractionSuite.standard) {
      return Semantics(
        liveRegion: true,
        label: widget.label,
        child: ExcludeSemantics(
          child: animated
              ? const CircularProgressIndicator()
              : const StandardIcon(StandardIconSemantic.hourglassTop),
        ),
      );
    }
    return SizedBox(
      width: 160,
      height: 40,
      child: Center(
        child: data.suite == InteractionSuite.standard
            ? Semantics(
                liveRegion: true,
                label: widget.label,
                child: ExcludeSemantics(
                  child: CircularProgressIndicator(value: animated ? null : .5),
                ),
              )
            : SocialReadActivity(
                source: _source!,
                opening: widget.opening,
                label: widget.label,
                height: 4,
              ),
      ),
    );
  }
}
