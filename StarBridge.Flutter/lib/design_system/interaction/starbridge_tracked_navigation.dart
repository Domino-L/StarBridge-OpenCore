import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_interaction_theme.dart';
import 'starbridge_activation_origin.dart';

typedef StarBridgeNavigationTargetBuilder = Widget Function(
  BuildContext context,
  TrackItem item,
  bool selected,
  FocusNode focusNode,
  ValueChanged<InteractionSource> activate,
);

/// Presentation-only navigation over the host's intrinsic target geometry.
/// The host owns selection/leave guards; a requested id is never optimistic.
/// Stable ids preserve focus and indicator geometry through reorder/removal.
class StarBridgeTrackedNavigation extends StatefulWidget {
  const StarBridgeTrackedNavigation({
    required this.items,
    required this.selected,
    required this.onSelected,
    required this.targetBuilder,
    this.spacing = 0,
    this.separator,
    this.changeSource,
    this.plainTrack = false,
    super.key,
  });
  final List<TrackItem> items;
  final String selected;
  final ValueChanged<String> onSelected;
  final StarBridgeNavigationTargetBuilder targetBuilder;
  final double spacing;

  /// Drawn between targets, outside them, so the selection indicator frames
  /// the target alone (a divider inside a target shifts the frame).
  final Widget? separator;
  final InteractionSource? changeSource;

  /// No suite indicator, for targets that show selection on their own face.
  final bool plainTrack;

  @override
  State<StarBridgeTrackedNavigation> createState() => _TrackedNavigationState();
}

class _TrackedNavigationState extends State<StarBridgeTrackedNavigation> {
  String? _pendingTarget;
  InteractionSource _pendingSource = InteractionSource.programmatic;
  InteractionSource _confirmedSource = InteractionSource.programmatic;

  @override
  void didUpdateWidget(StarBridgeTrackedNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      _confirmedSource =
          widget.changeSource ??
          (_pendingTarget == widget.selected
              ? _pendingSource
              : InteractionSource.programmatic);
      _pendingTarget = null;
    }
  }

  void _request(int index, InteractionSource source) {
    _pendingTarget = widget.items[index].id;
    _pendingSource = source;
    unawaited(
      runStarBridgeActivation<void>(
        source,
        () => widget.onSelected(_pendingTarget!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _track(context),
      ),
    ),
  );

  Widget _track(BuildContext context) {
    final track = SuiteSelectionTrack(
      style: TrackStyle.tabs,
      items: widget.items,
      selected: widget.items.indexWhere((item) => item.id == widget.selected),
      changeSource: _confirmedSource,
      onChanged: _request,
      layoutBuilder: (context, layout) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in widget.items) ...[
            if (widget.separator != null && item != widget.items.first)
              widget.separator!,
            Padding(
              padding: EdgeInsetsDirectional.only(end: widget.spacing),
              child: layout.anchor(
                item.id!,
                widget.targetBuilder(
                  context,
                  item,
                  item.id == widget.selected,
                  layout.focusNode(item.id!),
                  (source) => layout.activate(item.id!, source),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (!widget.plainTrack) return track;
    final data = InteractionScope.of(context);
    return InteractionScope(
      data: InteractionData(
        suite: InteractionSuite.standard,
        palette: data.palette,
        reduceMotion: data.reduceMotion,
      ),
      child: track,
    );
  }
}
