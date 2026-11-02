import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import 'application_support_copy.dart';
import 'application_support_module.dart';

/// Read-only presentation provenance. The original module owns inspection,
/// its one queued recheck, all results and the Host directory action.
class ApplicationSupportMotion extends StatefulWidget {
  const ApplicationSupportMotion({
    required this.module,
    required this.builder,
    super.key,
  });
  final ApplicationSupportModule module;
  final Widget Function(BuildContext, ApplicationSupportMotionState) builder;
  @override
  State<ApplicationSupportMotion> createState() =>
      ApplicationSupportMotionState();
}

class ApplicationSupportMotionState extends State<ApplicationSupportMotion> {
  late var _projection = widget.module.projection;
  bool _dispatching = false;
  Object? _active;
  InteractionSource source = InteractionSource.programmatic;
  bool staticWait = true;

  @override
  void initState() {
    super.initState();
    _projection.addListener(_observe);
  }

  @override
  void didUpdateWidget(ApplicationSupportMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.module.projection;
    if (!identical(oldWidget.module, widget.module) ||
        !identical(next, _projection)) {
      _projection.removeListener(_observe);
      _projection = next;
      _projection.addListener(_observe);
      _retire();
    }
  }

  void _retire() {
    _active = null;
    source = InteractionSource.programmatic;
    staticWait = true;
  }

  void _observe() {
    if (!_dispatching && mounted) setState(_retire);
  }

  Future<void> refresh() async {
    final projection = _projection;
    final before = projection.value;
    final origin = captureStarBridgeActivationSource()();
    final token = Object();
    late Future<void> work;
    _dispatching = true;
    try {
      work = widget.module.refresh(); // Original call, exactly once.
    } catch (_) {
      if (mounted &&
          identical(projection, _projection) &&
          !identical(before, projection.value)) {
        setState(_retire);
      }
      rethrow;
    } finally {
      _dispatching = false;
    }
    // Initial const loading and refresh-while-reading publish no new value.
    // They do NOT prove admission of a new request; never steal provenance.
    if (mounted &&
        identical(projection, _projection) &&
        !identical(before, projection.value)) {
      setState(() {
        _active = projection.value.loading ? token : null;
        source = projection.value.loading
            ? origin
            : InteractionSource.programmatic;
        staticWait = !projection.value.loading;
      });
    }
    try {
      await work;
    } finally {
      if (mounted &&
          identical(projection, _projection) &&
          identical(_active, token)) {
        setState(_retire);
      }
    }
  }

  @override
  void dispose() {
    _projection.removeListener(_observe);
    _active = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, this);
}

class ApplicationSupportWaiting extends StatelessWidget {
  const ApplicationSupportWaiting({
    required this.source,
    required this.staticWait,
    super.key,
  });
  final InteractionSource source;
  final bool staticWait;
  @override
  Widget build(BuildContext context) => StarBridgeSurface(
    key: const Key('application-support-loading'),
    role: SurfaceRole.panel,
    child: StarBridgeInteractionRegion(
      child: Builder(
        builder: (context) {
          final data = InteractionScope.of(context);
          final label = applicationSupportCopy(context, 'checking');
          if (staticWait ||
              data.reduceMotion ||
              source == InteractionSource.keyboard) {
            return Semantics(
              liveRegion: true,
              child: Center(child: Text(label)),
            );
          }
          return Semantics(
            liveRegion: true,
            label: label,
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(label, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const SuiteProgressBar(
                    value: null,
                    phase: ProgressPhase.running,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
