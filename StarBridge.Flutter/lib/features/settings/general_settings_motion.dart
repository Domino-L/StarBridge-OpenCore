import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../app/preferences/app_preferences_port.dart';
import '../../app/preferences/app_preferences_projection.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

/// Page-local presentation provenance, not preferences or persistence ownership.
/// Foreign projections retire provenance; no result is inferred from a Future.
class GeneralSettingsMotion extends StatefulWidget {
  const GeneralSettingsMotion({
    required this.preferences,
    required this.builder,
    super.key,
  });
  final AppPreferencesPort preferences;
  final Widget Function(BuildContext, GeneralSettingsMotionState) builder;
  @override
  State<GeneralSettingsMotion> createState() => GeneralSettingsMotionState();
}

class GeneralSettingsMotionState extends State<GeneralSettingsMotion> {
  late var _projection = widget.preferences.projection;
  Object? _active;
  bool _dispatching = false;
  bool _openingRead = false;
  InteractionSource source = InteractionSource.programmatic;
  bool staticWait = false;
  bool get _pending =>
      _projection.value.phase == AppPreferencesPhase.loading ||
      _projection.value.operation == AppPreferencesOperation.saving;

  @override
  void initState() {
    super.initState();
    _projection.addListener(_observe);
    _openingRead = _projection.value.isInitialLoading;
    staticWait = _pending && !_openingRead;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_openingRead) {
      _openingRead = false;
      source = resolveStarBridgeInitialReadSource(
        context,
        InteractionSource.programmatic,
      );
    }
  }

  @override
  void didUpdateWidget(GeneralSettingsMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.preferences.projection;
    if (!identical(oldWidget.preferences, widget.preferences) ||
        !identical(next, _projection)) {
      _projection.removeListener(_observe);
      _projection = next;
      _projection.addListener(_observe);
      _active = null;
      _openingRead = false; // Never reuse the old page-opening source.
      source = InteractionSource.programmatic;
      staticWait = _pending;
    }
  }

  void _observe() {
    if (_dispatching || !mounted) return;
    // A new projection outside this synchronous admission includes receipts,
    // external store attach/detach, retry replacement and account-locale edits.
    // Unknown pending work stays visible but static, not relabelled as a click.
    setState(() {
      _active = null;
      _openingRead = false;
      source = InteractionSource.programmatic;
      staticWait = _pending;
    });
  }

  Future<bool> run(Future<bool> Function() command) async {
    final before = _projection.value;
    final projection = _projection;
    final token = Object();
    final origin = captureStarBridgeActivationSource()();
    late Future<bool> result;
    _dispatching = true;
    try {
      result = command(); // Exactly the original callback, synchronously.
    } catch (_) {
      if (mounted &&
          identical(projection, _projection) &&
          !identical(before, projection.value)) {
        setState(() {
          _active = null;
          _openingRead = false;
          source = InteractionSource.programmatic;
          staticWait = _pending;
        });
      }
      rethrow;
    } finally {
      _dispatching = false;
    }
    // A guarded/no-op or synchronously completed implementation must not
    // steal the existing request's provenance or invent a pending operation.
    if (mounted &&
        identical(projection, _projection) &&
        !identical(before, projection.value)) {
      setState(() {
        _active = _pending ? token : null;
        _openingRead = false;
        source = _pending ? origin : InteractionSource.programmatic;
        staticWait = false;
      });
    }
    try {
      return await result;
    } finally {
      if (mounted &&
          identical(_active, token) &&
          identical(projection, _projection)) {
        setState(() {
          _active = null;
          source = InteractionSource.programmatic;
          staticWait = _pending; // A Future alone is not a completion receipt.
        });
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

class GeneralSettingsWaiting extends StatelessWidget {
  const GeneralSettingsWaiting({
    required this.source,
    required this.staticWait,
    this.saving = false,
    super.key,
  });
  final InteractionSource source;
  final bool staticWait;
  final bool saving;
  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        final label = AppStrings.of(
          context,
        ).text(saving ? 'settings.general.saving' : 'settings.general.loading');
        final key = Key(
          saving ? 'general-settings-saving' : 'general-settings-loading',
        );
        if (staticWait ||
            data.reduceMotion ||
            source == InteractionSource.keyboard) {
          return Semantics(liveRegion: true, child: Text(label, key: key));
        }
        return Semantics(
          key: key,
          liveRegion: true,
          label: label,
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!saving) ...[
                  Text(label, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                ],
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
  );
}
