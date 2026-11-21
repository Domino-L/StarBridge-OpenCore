import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_slider.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import 'menu_hud_quick_view.dart';

/// Alt+M → 信息浮层 → 全局 (11-11 user chose: calm display and the visor's
/// depth here; the overall opacity was retired 11-12; the rest of the global
/// group stays in the client). Each control sends an intent; the primary engine saves it.
class MenuHudQuickGlobalControls extends StatelessWidget {
  const MenuHudQuickGlobalControls({
    required this.global,
    required this.enabled,
    required this.text,
    required this.onAction,
    this.more,
    super.key,
  });

  final MenuHudQuickGlobal global;
  final bool enabled;
  final String Function(String key) text;
  final void Function(String key, String value) onAction;

  /// The link to the client's global settings, when there is one.
  final Widget? more;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StarBridgeSwitch.tile(
        key: const ValueKey('menu-hud-quick-calm'),
        value: global.calm,
        label: text('menu.hudQuick.calm'),
        titleWidget: Text(text('menu.hudQuick.calm')),
        onChanged: enabled ? (_) => onAction('calm', '') : null,
      ),
      if (global.tilt case final tilt?)
        _GlobalSlider(
          key: const ValueKey('menu-hud-quick-tilt'),
          label: text('menu.hudQuick.tilt'),
          value: tilt,
          min: 0,
          max: MenuHudQuickGlobal.maxTilt,
          divisions: 40,
          shown: (v) => '${v.round()}°',
          onDone: enabled ? (v) => onAction('tilt', '${v.round()}') : null,
        ),
      if (more != null) Align(alignment: Alignment.centerLeft, child: more),
    ],
  );
}

/// Follows the drag on screen and sends once, when it is let go: one save per
/// adjustment, not one per pixel.
class _GlobalSlider extends StatefulWidget {
  const _GlobalSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.shown,
    required this.onDone,
    super.key,
  });

  final String label;
  final double value, min, max;
  final int divisions;
  final String Function(double) shown;
  final ValueChanged<double>? onDone;

  @override
  State<_GlobalSlider> createState() => _GlobalSliderState();
}

class _GlobalSliderState extends State<_GlobalSlider> {
  double? _dragging;

  // the value let go of stays shown until the saved one comes back, or the
  // save is over either way (the control is enabled again)
  @override
  void didUpdateWidget(_GlobalSlider old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value ||
        (old.onDone == null && widget.onDone != null)) {
      _dragging = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.value).clamp(widget.min, widget.max);
    final done = widget.onDone;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${widget.label}  ${widget.shown(value)}'),
          StarBridgeSlider(
            semanticLabel: widget.label,
            value: value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            valueLabel: widget.shown,
            onChanged: done == null
                ? null
                : (v) => setState(() => _dragging = v),
            onChangeEnd: done == null
                ? null
                : (v) {
                    if (v == widget.value) {
                      setState(() => _dragging = null);
                    } else {
                      done(v);
                    }
                  },
            onChangeCancel: () => setState(() => _dragging = null),
          ),
        ],
      ),
    );
  }
}
