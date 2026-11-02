import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import 'help_support_waiting.dart';

/// An existing controller's wait decoration, not another request owner.
/// Read and save slots can observe distinct predicates on the same owner.
class SharingSettingsWaiting extends StatefulWidget {
  const SharingSettingsWaiting({
    required this.owner,
    required this.pending,
    required this.titleKey,
    required this.labelKey,
    super.key,
  });

  final Listenable owner;
  final ValueGetter<bool> pending;
  final String titleKey;
  final String labelKey;

  @override
  State<SharingSettingsWaiting> createState() => _SharingSettingsWaitingState();
}

class _SharingSettingsWaitingState extends State<SharingSettingsWaiting> {
  bool _wasPending = false;
  int _phase = 0;
  InteractionSource _source = InteractionSource.programmatic;

  void _observe() {
    final pending = widget.pending();
    if (pending && !_wasPending) {
      _phase++;
      _source = captureStarBridgeActivationSource()();
    }
    _wasPending = pending;
    // The original ListenableBuilder schedules the render. Never trigger a
    // request/rebuild here or infer business success from a pending edge.
  }

  @override
  void initState() {
    super.initState();
    widget.owner.addListener(_observe);
    _observe();
  }

  @override
  void didUpdateWidget(SharingSettingsWaiting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.owner, widget.owner)) {
      oldWidget.owner.removeListener(_observe);
      widget.owner.addListener(_observe);
      _wasPending = false;
      _source = InteractionSource.programmatic;
      _phase++;
      _observe();
    }
  }

  @override
  void dispose() {
    widget.owner.removeListener(_observe);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pending()) return const SizedBox.shrink();
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: HelpSupportWaiting(
        key: ValueKey((widget.owner, _phase)),
        source: _source,
        label:
            '${strings.text(widget.titleKey)} · ${strings.text(widget.labelKey)}',
      ),
    );
  }
}
