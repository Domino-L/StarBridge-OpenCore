import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

/// Wait decoration only. The adjacent live status text owns announcements;
/// readers/save modules retain all request, progress and completion facts.
class HangarReaderWaiting extends StatefulWidget {
  const HangarReaderWaiting({
    required this.source,
    this.color,
    this.height = 3,
    this.inheritOpeningSource = false,
    super.key,
  });
  final InteractionSource source;
  final Color? color;
  final double height;
  final bool inheritOpeningSource;

  @override
  State<HangarReaderWaiting> createState() => _HangarReaderWaitingState();
}

class _HangarReaderWaitingState extends State<HangarReaderWaiting> {
  InteractionSource? _source;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _source ??= widget.inheritOpeningSource
        ? resolveStarBridgeInitialReadSource(context, widget.source)
        : widget.source;
  }

  @override
  Widget build(BuildContext context) {
    final data = resolveStarBridgeInteraction(context);
    final p = data.palette, color = widget.color ?? p.accent;
    Widget indicator;
    final instant = data.reduceMotion || _source == InteractionSource.keyboard;
    if (data.suite == InteractionSuite.standard) {
      // The existing half-track is a static wait mark, not a percentage;
      // the original adjacent status remains the sole semantic announcement.
      indicator = LinearProgressIndicator(
        value: instant ? .5 : null,
        color: widget.color,
      );
    } else if (instant) {
      indicator = DecoratedBox(
        decoration: BoxDecoration(color: color.withValues(alpha: .3)),
      );
    } else {
      indicator = InteractionScope(
        data: data.copyWith(
          palette: InteractionPalette(
            brightness: p.brightness,
            accent: color,
            accentBright: color,
            onAccent: p.onAccent,
            selectedFill: p.selectedFill,
            surface: p.surface,
            raised: p.raised,
            border: p.border,
            textPrimary: p.textPrimary,
            textSecondary: p.textSecondary,
            textDisabled: p.textDisabled,
            focusRing: p.focusRing,
            success: p.success,
            onSuccess: p.onSuccess,
            danger: p.danger,
            onDanger: p.onDanger,
            warning: p.warning,
          ),
        ),
        child: const SuiteProgressBar(
          value: null,
          phase: ProgressPhase.running,
        ),
      );
    }
    return SizedBox(
      height: widget.height,
      child: ExcludeSemantics(child: indicator),
    );
  }
}
