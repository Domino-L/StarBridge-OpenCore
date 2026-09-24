import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
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
  Future<void> _test() async {
    if (_busy || !widget.enabled) return;
    final attempt = ++_attempt;
    final strings = AppStrings.of(context);
    setState(() {
      _busy = true;
      _submitted = null;
      _reason = null;
    });
    final Object diagnostics = widget.port;
    final detailed = diagnostics is DesktopNotificationDiagnostics
        ? await diagnostics.testDesktop()
        : null;
    final result =
        detailed?.submitted ??
        await widget.port.show(
          strings.text('settings.notification.local.testTitle'),
          strings.text('settings.notification.local.desktopTestBody'),
          test: true,
        );
    if (mounted && attempt == _attempt) {
      setState(() {
        _busy = false;
        _submitted = result;
        _reason = detailed?.reason;
      });
    }
  }

  @override
  void didUpdateWidget(covariant DesktopNotificationTestButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _attempt++;
      _busy = false;
      _submitted = null;
      _reason = null;
      unawaited(widget.port.clear());
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton(
          key: const Key('notification-desktop-test'),
          onPressed: widget.enabled && !_busy ? _test : null,
          child: Text(strings.text('settings.notification.local.desktopTest')),
        ),
        if (_submitted != null)
          Text(
            strings.text(
              _submitted!
                  ? 'settings.notification.local.desktopSubmitted'
                  : _reason == null
                  ? 'settings.notification.local.desktopFailed'
                  : 'settings.notification.desktopReason.$_reason',
            ),
          ),
      ],
    );
  }
}
