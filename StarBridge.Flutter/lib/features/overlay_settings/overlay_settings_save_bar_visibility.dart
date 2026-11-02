import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

/// Presentation lifetime only. The caller still owns the draft, visibility
/// policy, commands and persistence. One surface reverses from its current
/// position; a retiring child can never remove a newly revived bar.
class OverlaySettingsSaveBarVisibility extends StatefulWidget {
  const OverlaySettingsSaveBarVisibility({
    required this.owner,
    required this.isVisible,
    required this.builder,
    super.key,
  });

  final Listenable owner;
  final ValueGetter<bool> isVisible;
  final WidgetBuilder builder;

  @override
  State<OverlaySettingsSaveBarVisibility> createState() => _VisibilityState();
}

class _VisibilityState extends State<OverlaySettingsSaveBarVisibility>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this)
    ..addStatusListener(_status);
  late bool _shown;
  Widget? _retained;
  InteractionData? _data;
  InteractionSource _source = InteractionSource.programmatic;

  @override
  void initState() {
    super.initState();
    _shown = widget.isVisible();
    widget.owner.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data = resolveStarBridgeInteraction(context);
    _drive();
  }

  @override
  void didUpdateWidget(OverlaySettingsSaveBarVisibility old) {
    super.didUpdateWidget(old);
    if (!identical(old.owner, widget.owner)) {
      old.owner.removeListener(_changed);
      widget.owner.addListener(_changed);
      // Never carry an old owner's content, exit or input provenance into
      // the new workspace. Initial presentation uses its own opening fact.
      _controller.stop();
      _retained = null;
      _source = InteractionSource.programmatic;
      _shown = widget.isVisible();
      _controller.value = 0;
      _drive();
    }
  }

  void _changed() {
    final next = widget.isVisible();
    if (next != _shown) {
      _shown = next;
      // Notification is synchronous within the original command, including
      // awaited save confirmations. A later build is outside that input zone.
      _source = currentStarBridgeActivationSource;
      _drive();
    }
    if (mounted) setState(() {});
  }

  InteractionData get _surfaceData => _data!.copyWith(
    reduceMotion:
        _data!.reduceMotion ||
        resolveStarBridgeInitialReadSource(context, _source) ==
            InteractionSource.keyboard,
  );

  void _drive() {
    if (_data == null) return;
    final durations = surfaceDurations(_surfaceData, SurfaceKind.dialog);
    _controller
      ..duration = durations.enter
      ..reverseDuration = durations.exit;
    if (!_surfaceData.animates) {
      _controller.stop();
      _controller.value = _shown ? 1 : 0;
      if (!_shown) _retained = null;
    } else if (_shown) {
      if (!_controller.isAnimating ||
          _controller.status != AnimationStatus.forward) {
        _controller.forward();
      }
    } else if (_controller.value > 0) {
      if (!_controller.isAnimating ||
          _controller.status != AnimationStatus.reverse) {
        _controller.reverse();
      }
    } else {
      _retained = null;
    }
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_shown && mounted) {
      setState(() => _retained = null);
    }
  }

  @override
  void dispose() {
    widget.owner.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shown) _retained = widget.builder(context);
    if (_retained == null) return const SizedBox.shrink();
    return InteractionScope(
      data: _surfaceData,
      child: SuiteSurfaceTransition(
        animation: _controller,
        kind: SurfaceKind.dialog,
        alignment: Alignment.bottomCenter,
        child: IgnorePointer(
          ignoring: !_shown,
          child: ExcludeFocus(
            excluding: !_shown,
            child: ExcludeSemantics(
              excluding: !_shown,
              child: TickerMode(
                enabled: _shown,
                // Instant surface entry must not mute the next pointer action.
                child: KeyedSubtree(
                  key: ObjectKey(widget.owner),
                  child: InteractionScope(data: _data!, child: _retained!),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
