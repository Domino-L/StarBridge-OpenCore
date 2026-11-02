import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_activation_origin.dart';
import 'starbridge_interaction_theme.dart';

/// Observes admitted busy edges only. It never starts, completes or cancels a
/// request, notifies the owner, or disposes a borrowed controller.
final class SocialReadActivityBinding {
  SocialReadActivityBinding(
    this.owner,
    this.isBusy, {
    required this.initialRead,
    this.phaseIdentity,
  }) {
    owner.addListener(_observe);
    _observe();
  }
  final Listenable owner;
  final bool Function() isBusy;
  final bool initialRead;

  /// Optional read-only identity of an admitted operation. A replacement read
  /// can begin without a false busy edge; unrelated notifications keep it.
  final Object? Function()? phaseIdentity;
  Object? _phase;
  bool _busy = false, _first = true;
  int revision = 0;
  InteractionSource source = InteractionSource.programmatic;
  bool opening = false;

  void _observe() {
    final next = isBusy();
    final phase = phaseIdentity?.call();
    if (next && (!_busy || phaseIdentity != null && phase != _phase)) {
      revision++;
      source = captureStarBridgeActivationSource()();
      opening = initialRead && _first;
      _first = false;
    }
    _busy = next;
    _phase = phase;
  }

  void dispose() => owner.removeListener(_observe);
}

/// Thin, nonblocking read/update marker using the approved busy-frame recipe.
/// The static half-track is hidden from numeric progress semantics: it is not
/// 50% completed. Only the caller's actual busy state controls its presence.
class SocialReadActivity extends StatefulWidget {
  const SocialReadActivity({
    required this.source,
    required this.opening,
    required this.label,
    this.height = 2,
    this.circularStandard = false,
    this.circularSize = 36,
    this.circularStrokeWidth = 4,
    super.key,
  });
  final InteractionSource source;
  final bool opening;
  final String label;
  final double height;

  /// Preserve a caller's existing central Standard spinner. Other suites keep
  /// the approved thin wait recipe; this never exposes numeric progress.
  final bool circularStandard;
  final double circularSize, circularStrokeWidth;
  @override
  State<SocialReadActivity> createState() => _ReadActivityState();
}

class _ReadActivityState extends State<SocialReadActivity> {
  InteractionSource? _source;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _source ??= widget.opening
        ? resolveStarBridgeInitialReadSource(context, widget.source)
        : widget.source;
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        final animate =
            !data.reduceMotion &&
            _source != InteractionSource.keyboard &&
            (widget.opening || _source == InteractionSource.pointer);
        return InteractionScope(
          data: data.copyWith(reduceMotion: !animate),
          child: Semantics(
            liveRegion: true,
            label: widget.label,
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: SuiteBusyFrame(
                  busy: true,
                  radius: 0,
                  child:
                      widget.circularStandard &&
                          data.suite == InteractionSuite.standard
                      ? SizedBox.square(
                          dimension: widget.circularSize,
                          child: CircularProgressIndicator(
                            strokeWidth: widget.circularStrokeWidth,
                            value: animate ? null : .5,
                          ),
                        )
                      : LinearProgressIndicator(
                          minHeight: widget.height,
                          value:
                              animate &&
                                  (data.suite == InteractionSuite.standard ||
                                      data.suite == InteractionSuite.glow)
                              ? null
                              : .5,
                        ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
