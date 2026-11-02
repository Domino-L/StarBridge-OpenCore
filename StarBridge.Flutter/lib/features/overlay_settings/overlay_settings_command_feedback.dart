import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

typedef OverlaySettingsCommandRunner = Future<void> Function(
  InteractionSource source,
  Future<void> Function() action,
);

/// An awaited UI source lease, not a settings/request/status owner. Consumers
/// keep their existing busy/result gates and decide where feedback is shown.
class OverlaySettingsCommandFeedback extends StatefulWidget {
  const OverlaySettingsCommandFeedback({
    required this.owner,
    required this.builder,
    super.key,
  });
  final Object owner;
  final Widget Function(
    BuildContext,
    OverlaySettingsCommandRunner,
    ValueGetter<InteractionSource>,
  )
  builder;
  @override
  State<OverlaySettingsCommandFeedback> createState() =>
      _CommandFeedbackState();
}

class _CommandFeedbackState extends State<OverlaySettingsCommandFeedback> {
  int _epoch = 0;
  bool _pending = false;
  ValueGetter<InteractionSource> _source = () => InteractionSource.programmatic;

  @override
  void didUpdateWidget(OverlaySettingsCommandFeedback old) {
    super.didUpdateWidget(old);
    if (!identical(old.owner, widget.owner)) {
      ++_epoch;
      _pending = false;
      _source = () => InteractionSource.programmatic;
    }
  }

  Future<void> _run(
    InteractionSource source,
    Future<void> Function() action,
  ) async {
    if (!mounted || _pending) return;
    final owner = widget.owner, epoch = ++_epoch;
    await runStarBridgeActivation(source, () async {
      setState(() {
        _pending = true;
        _source = captureStarBridgeActivationSource();
      });
      try {
        await action();
      } finally {
        if (mounted && epoch == _epoch && identical(owner, widget.owner)) {
          setState(() {
            _pending = false;
            _source = () => InteractionSource.programmatic;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    _run,
    () => resolveStarBridgeInitialReadSource(context, _source()),
  );
}

/// Only decorate a consumer's actual busy state, preserving its original label.
/// Keyboard/reader/initial keyboard viewport and live reduce all remain static.
class OverlaySettingsCommandWait extends StatelessWidget {
  const OverlaySettingsCommandWait({
    required this.label,
    required this.source,
    super.key,
  });
  final String label;
  final InteractionSource source;
  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        return InteractionScope(
          data: data.copyWith(
            reduceMotion:
                data.reduceMotion || source != InteractionSource.pointer,
          ),
          child: SuiteBusyFrame(busy: true, child: SuiteBusyLabel(label)),
        );
      },
    ),
  );
}
