import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/host/desktop_notification_port.dart';

class DesktopNotificationTestButton extends StatefulWidget {
  const DesktopNotificationTestButton({
    required this.port,
    required this.enabled,
    super.key,
  });
  final DesktopNotificationPort port;
  final bool enabled;
  @override
  State<DesktopNotificationTestButton> createState() =>
      _DesktopNotificationTestButtonState();
}

class _DesktopNotificationTestButtonState
    extends State<DesktopNotificationTestButton> {
  bool _busy = false;
  bool? _submitted;
  String? _reason;
  int _attempt = 0;
  int _completed = 0;
  int _ownerEpoch = 0;
  InteractionSource _source = InteractionSource.programmatic;
  Future<void> _test(InteractionSource source) async {
    if (_busy || !widget.enabled) return;
    final attempt = ++_attempt;
    final strings = AppStrings.of(context);
    final port = widget.port;
    setState(() {
      _busy = true;
      _source = source;
      _submitted = null;
      _reason = null;
    });
    final Object diagnostics = port;
    DesktopNotificationTestResult? detailed;
    bool result;
    try {
      detailed = diagnostics is DesktopNotificationDiagnostics
          ? await diagnostics.testDesktop()
          : null;
      result =
          detailed?.submitted ??
          await port.show(
            strings.text('settings.notification.local.testTitle'),
            strings.text('settings.notification.local.desktopTestBody'),
            test: true,
          );
    } catch (_) {
      // A failed submission is not a success or proof of Windows display.
      // Keep this attempt retryable; never create a native fallback channel.
      result = false;
    }
    if (mounted && attempt == _attempt && identical(port, widget.port)) {
      setState(() {
        _busy = false;
        _completed++;
        _submitted = result;
        _reason = detailed?.reason;
      });
    }
  }

  @override
  void didUpdateWidget(covariant DesktopNotificationTestButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.port, widget.port) ||
        (oldWidget.enabled && !widget.enabled)) {
      _attempt++;
      _ownerEpoch++;
      _source = InteractionSource.programmatic;
      _busy = false;
      _submitted = null;
      _reason = null;
      unawaited(oldWidget.port.clear());
    }
  }

  @override
  void dispose() {
    _attempt++;
    unawaited(widget.port.clear());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return StarBridgeInteractionRegion(
      child: Builder(
        builder: (context) {
          final data = InteractionScope.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  StarBridgeActionButton(
                    controlKey: const Key('notification-desktop-test'),
                    semanticLabel: strings.text(
                      'settings.notification.local.desktopTest',
                    ),
                    onActivate: widget.enabled && !_busy
                        ? (source) {
                            unawaited(
                              runStarBridgeActivation<void>(
                                source,
                                () => _test(source),
                              ),
                            );
                          }
                        : null,
                    child: Text(
                      strings.text('settings.notification.local.desktopTest'),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: InteractionScope(
                          data: data.copyWith(
                            reduceMotion:
                                data.reduceMotion ||
                                _source == InteractionSource.keyboard,
                          ),
                          child: SuiteBusyFrame(
                            key: ValueKey(_ownerEpoch),
                            busy: _busy,
                            doneToken: _completed,
                            doneOutcome: _submitted == false
                                ? TaskOutcome.failure
                                : TaskOutcome.success,
                            radius: context.tokens.shape.radiusSmall,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_busy)
                Semantics(
                  liveRegion: true,
                  child: InteractionScope(
                    data: data.copyWith(
                      reduceMotion:
                          data.reduceMotion ||
                          _source == InteractionSource.keyboard,
                    ),
                    child: SuiteBusyLabel(
                      strings.text(
                        'settings.notification.local.desktopSubmitting',
                      ),
                    ),
                  ),
                ),
              if (_submitted != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    strings.text(
                      _submitted!
                          ? 'settings.notification.local.desktopSubmitted'
                          : _reason == null
                          ? 'settings.notification.local.desktopFailed'
                          : 'settings.notification.desktopReason.$_reason',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
