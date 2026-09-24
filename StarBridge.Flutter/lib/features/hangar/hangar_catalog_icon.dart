import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/ships/catalog_vehicle_icon.dart';

/// One finite sequence per logical arrival. Arrival time belongs to the page /
/// scan, so virtualization cannot restart it. Ordinary catalog rows stay static.
class HangarCatalogIcon extends StatefulWidget {
  const HangarCatalogIcon({
    required this.iconKey,
    required this.elapsed,
    this.active = true,
    super.key,
  });
  final String iconKey;
  final Duration elapsed;
  final bool active;

  @override
  State<HangarCatalogIcon> createState() => _HangarCatalogIconState();
}

class _HangarCatalogIconState extends State<HangarCatalogIcon>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final duration = CatalogVehicleIcon.motionDuration(widget.iconKey)!;
    _motion = AnimationController(
      vsync: this,
      duration: duration,
      value: (widget.elapsed.inMicroseconds / duration.inMicroseconds).clamp(
        0.0,
        1.0,
      ),
    );
  }

  void _finish() {
    _motion.stop();
    _motion.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = WidgetsBinding.instance.lifecycleState;
    if (!widget.active ||
        !TickerMode.valuesOf(context).enabled ||
        MediaQuery.disableAnimationsOf(context) ||
        context.tokens.motion.surfaceEnter == Duration.zero ||
        (state != null && state != AppLifecycleState.resumed)) {
      _finish();
    } else if (!_started && _motion.value < 1) {
      _motion.forward();
    }
    _started = true;
  }

  @override
  void didUpdateWidget(covariant HangarCatalogIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active || oldWidget.iconKey != widget.iconKey) _finish();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _finish();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CatalogVehicleIcon.byKey(iconKey: widget.iconKey, motion: _motion);
}
