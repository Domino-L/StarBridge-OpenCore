import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import 'bridge_notification_sources.dart';
import 'help_support_action.dart';
import 'notification_settings_models.dart';
import 'notification_settings_sources.dart';

/// Which notification source is this organization's. A community is matched
/// by the code the Host reports, never by its name: two can share a name.
NotificationSourceRule? organizationNotificationRule(
  NotificationSourcesValue value,
  String? communityCode,
) {
  for (final rule in value.sources) {
    if (communityCode == null
        ? rule.kind == NotificationSourceKind.officialFleet
        : rule.kind == NotificationSourceKind.community &&
              rule.organizationCode?.toLowerCase() ==
                  communityCode.toLowerCase()) {
      return rule;
    }
  }
  return null;
}

/// One organization's notification choice on its own settings page, through
/// the same Host editor as the notification settings page. A save holds every
/// other source's mode as read. [communityCode] is null for the main fleet. The
/// page around it scrolls.
class OrganizationNotificationPane extends StatefulWidget {
  const OrganizationNotificationPane({
    required this.create,
    this.communityCode,
    super.key,
  });

  final NotificationSourcesPort Function() create;
  final String? communityCode;

  @override
  State<OrganizationNotificationPane> createState() =>
      _OrganizationNotificationPaneState();
}

class _OrganizationNotificationPaneState
    extends State<OrganizationNotificationPane> {
  late final NotificationSourcesPort _port = widget.create();
  late final StreamSubscription<void> _invalidations;
  NotificationSourcesValue? _value;
  bool _failed = false, _saving = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _invalidations = _port.invalidations.listen((_) => unawaited(_read()));
    unawaited(_read());
  }

  @override
  void dispose() {
    _epoch++;
    unawaited(_invalidations.cancel());
    _port.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final epoch = ++_epoch;
    setState(() {
      _failed = false;
      _saving = false;
      _value = null;
    });
    try {
      final value = await _port.read();
      if (mounted && epoch == _epoch) setState(() => _value = value);
    } on Object {
      if (mounted && epoch == _epoch) setState(() => _failed = true);
    }
  }

  Future<bool> _save(
    NotificationSourcesValue value,
    NotificationSourceRule rule,
    NotificationSourceMode mode,
  ) async {
    final epoch = ++_epoch;
    setState(() => _saving = true);
    try {
      final saved = await _port.save(value, {...value.modes, rule.sourceRef: mode});
      if (!mounted || epoch != _epoch) return false;
      setState(() {
        _value = saved;
        _saving = false;
      });
      return true;
    } on Object {
      if (!mounted || epoch != _epoch) return false;
      setState(() {
        _saving = false;
        _failed = true;
        _value = null;
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final value = _value;
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.text('settings.notification.sources.title')),
            const SizedBox(height: 12),
            HelpSupportAction(
              controlKey: const Key('organization-notification-retry'),
              kind: StarBridgeActionKind.secondary,
              onActivate: (_) => _read(),
              child: Text(strings.text('privacy.local.retry')),
            ),
          ],
        ),
      );
    }
    if (value == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final rule = organizationNotificationRule(value, widget.communityCode);
    return Padding(
      key: const Key('organization-notification-pane'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.text('settings.notification.organization.description'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (rule == null)
            Text(strings.text('settings.notification.sources.empty.title'))
          else
            NotificationSourceRuleRow(
              rule: rule,
              enabled: !_saving,
              onChanged: (mode) => _save(value, rule, mode),
            ),
        ],
      ),
    );
  }
}
