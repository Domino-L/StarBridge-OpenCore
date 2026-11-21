import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_dialog_owner.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'bridge_notification_sources.dart';
import 'help_support_action.dart';
import 'notification_settings_models.dart';
import 'notification_settings_sources.dart';
import 'notification_organization_options.dart';
import 'notification_organization_controls.dart';
import 'organization_notification_leave_guard.dart';

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
  bool _failed = false, _saving = false, _saveFailed = false;
  int _epoch = 0;
  NotificationOrganizationOptions? _draftOptions;
  Future<NotificationSourcesValue> Function()? _pendingWrite;
  bool _pendingClearsOptions = false;
  late final VoidCallback _removeLeaveGuard;
  Future<bool>? _pendingLeave;
  StarBridgeDialogRoute<String>? _leaveRoute;

  bool get _frozen => _saving || _pendingWrite != null;

  @override
  void initState() {
    super.initState();
    _removeLeaveGuard = registerOrganizationNotificationLeaveGuard(
      _confirmLeave,
    );
    _invalidations = _port.invalidations.listen((_) => unawaited(_read()));
    unawaited(_read());
  }

  @override
  void didUpdateWidget(OrganizationNotificationPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.communityCode != widget.communityCode) unawaited(_read());
  }

  @override
  void dispose() {
    _epoch++;
    _removeLeaveGuard();
    retireStarBridgeDialog(_leaveRoute);
    unawaited(_invalidations.cancel());
    _port.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final epoch = ++_epoch;
    retireStarBridgeDialog(_leaveRoute);
    _leaveRoute = null;
    _pendingLeave = null;
    setState(() {
      _failed = false;
      _saveFailed = false;
      _saving = false;
      _value = null;
      _draftOptions = null;
      _pendingWrite = null;
    });
    try {
      final value = await _port.read();
      if (mounted && epoch == _epoch) setState(() => _value = value);
    } on Object {
      if (mounted && epoch == _epoch) setState(() => _failed = true);
    }
  }

  Future<void> _saveOptions(
    NotificationSourcesValue value,
    NotificationSourceRule rule,
  ) async {
    if (_frozen || !identical(value, _value)) return;
    final port = _port, options = _draftOptions;
    if (port is! OrganizationNotificationSourcesPort ||
        options == null ||
        !options.valid) {
      return;
    }
    await _submit(
      () => port.saveOrganizationOptions(value, value.modes, {
        rule.sourceRef: options,
      }),
      clearOptions: true,
    );
  }

  Future<bool> _save(
    NotificationSourcesValue value,
    NotificationSourceRule rule,
    NotificationSourceMode mode,
  ) async {
    if (_frozen || !identical(value, _value)) return false;
    return _submit(
      () => _port.save(value, {...value.modes, rule.sourceRef: mode}),
    );
  }

  Future<bool> _submit(
    Future<NotificationSourcesValue> Function() write, {
    bool clearOptions = false,
  }) async {
    if (_saving) return false;
    final epoch = ++_epoch;
    setState(() {
      _saving = true;
      _pendingWrite = write;
      _pendingClearsOptions = clearOptions;
    });
    try {
      // Retain the original lease and payload. The Bridge's signature cache
      // then reuses the original operationId on an explicit retry.
      final saved = await write();
      if (!mounted || epoch != _epoch) return false;
      setState(() {
        _value = saved;
        _saving = false;
        _saveFailed = false;
        _pendingWrite = null;
        if (clearOptions) _draftOptions = null;
      });
      return true;
    } catch (error) {
      if (!mounted || epoch != _epoch) return false;
      setState(() {
        _saving = false;
        _saveFailed = true;
        // Only a definite non-write permits a new edit/operation. Missing or
        // malformed receipts and transport failures remain unresolved.
        if (error is BridgeRemoteException &&
            error.code == 'notificationPolicies.save_failed') {
          _pendingWrite = null;
        }
      });
      return false;
    }
  }

  Future<bool> _retryWrite() {
    final write = _pendingWrite;
    if (write == null || _saving) return Future.value(false);
    return _submit(write, clearOptions: _pendingClearsOptions);
  }

  Future<bool> _confirmLeave() {
    final pending = _pendingLeave;
    if (pending != null) return pending;
    late final Future<bool> request;
    request = _askLeave().whenComplete(() {
      if (identical(_pendingLeave, request)) _pendingLeave = null;
    });
    _pendingLeave = request;
    return request;
  }

  String _copy(String cn, String tw, String en) {
    final locale = AppStrings.of(context).locale;
    if (locale.languageCode != 'zh') return en;
    return locale.scriptCode == 'Hant' ||
            locale.countryCode == 'TW' ||
            locale.countryCode == 'HK'
        ? tw
        : cn;
  }

  Future<bool> _askLeave() async {
    if (!mounted || _saving) return false;
    if (_pendingWrite == null) return true;
    final epoch = _epoch;
    StarBridgeDialogRoute<String>? route;
    bool current() => mounted && epoch == _epoch && _pendingWrite != null;
    final choice = await showStarBridgeDialog<String>(
      context,
      barrierDismissible: false,
      onRouteCreated: (value) {
        route = value;
        _leaveRoute = value;
      },
      builder: (dialogContext) => StarBridgeDialogOwnerGuard(
        isCurrent: current,
        child: AlertDialog(
          key: const Key('organization-notification-leave-dialog'),
          title: Text(_copy('保存结果尚未确认', '儲存結果尚未確認', 'Save result unconfirmed')),
          content: Text(
            _copy(
              '请重试原操作，或放弃本次更改后离开。放弃不会撤销可能已保存的设置。',
              '請重試原操作，或放棄本次變更後離開。放棄不會撤銷可能已儲存的設定。',
              'Retry the original operation, or discard these changes to leave. Discarding will not undo settings that may already have been saved.',
            ),
          ),
          actions: [
            for (final action in ['stay', 'discard', 'retry'])
              HelpSupportAction(
                controlKey: Key('organization-notification-leave-$action'),
                onActivate: (source) {
                  if (!current()) return;
                  dismissStarBridgeDialog(
                    dialogContext,
                    source: source,
                    result: action,
                  );
                },
                child: Text(
                  action == 'stay'
                      ? _copy('留在此页', '留在此頁', 'Stay on this page')
                      : AppStrings.of(context).text('privacy.local.$action'),
                ),
              ),
          ],
        ),
      ),
    );
    if (identical(_leaveRoute, route)) _leaveRoute = null;
    if (!current()) return false;
    if (choice == 'retry') return _retryWrite();
    if (choice == 'discard') {
      await _read();
      return mounted;
    }
    return false;
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
          else ...[
            NotificationSourceRuleRow(
              rule: rule,
              enabled: !_frozen,
              onChanged: (mode) => _save(value, rule, mode),
            ),
            if (value.supportsOrganizationOptions &&
                _port is OrganizationNotificationSourcesPort) ...[
              NotificationOrganizationControls(
                key: ValueKey(rule.sourceRef),
                sourceRef: rule.sourceRef,
                official: widget.communityCode == null,
                value: _draftOptions ?? rule.organizationOptions,
                enabled: !_frozen,
                onChanged: (next) {
                  if (!_frozen && identical(value, _value)) {
                    setState(() => _draftOptions = next);
                  }
                },
              ),
              const SizedBox(height: 16),
              HelpSupportAction(
                controlKey: const Key('organization-notification-save-options'),
                kind: StarBridgeActionKind.primary,
                onActivate:
                    !_frozen &&
                        _draftOptions?.valid == true &&
                        _draftOptions != rule.organizationOptions
                    ? (_) => _saveOptions(value, rule)
                    : null,
                child: Text(
                  strings.text('settings.notification.organization.save'),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(strings.text('settings.notification.organization.upgrade')),
            ],
          ],
          if (_saveFailed) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _pendingWrite == null
                    ? strings.text('settings.notification.error.writeFailed')
                    : _copy(
                        '保存结果尚未确认。请重试原操作或放弃本次更改。',
                        '儲存結果尚未確認。請重試原操作或放棄本次變更。',
                        'The save result is unconfirmed. Retry the original operation or discard these changes.',
                      ),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            if (_pendingWrite != null) ...[
              HelpSupportAction(
                controlKey: const Key('organization-notification-retry-write'),
                onActivate: !_saving ? (_) => _retryWrite() : null,
                child: Text(strings.text('privacy.local.retry')),
              ),
              HelpSupportAction(
                controlKey: const Key(
                  'organization-notification-discard-write',
                ),
                onActivate: !_saving ? (_) => _read() : null,
                child: Text(strings.text('privacy.local.discard')),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
