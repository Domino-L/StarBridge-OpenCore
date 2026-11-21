import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import 'notification_organization_options.dart';

/// Always expanded. The parent owns the draft and persistence transaction.
class NotificationOrganizationControls extends StatefulWidget {
  const NotificationOrganizationControls({
    required this.sourceRef,
    required this.official,
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });
  final String sourceRef;
  final bool official, enabled;
  final NotificationOrganizationOptions value;
  final ValueChanged<NotificationOrganizationOptions> onChanged;
  @override
  State<NotificationOrganizationControls> createState() => _State();
}

class _State extends State<NotificationOrganizationControls> {
  late final _start = TextEditingController(
    text: _format(widget.value.startMinute),
  );
  late final _end = TextEditingController(
    text: _format(widget.value.endMinute),
  );
  String _format(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  int _parse(String value) {
    if (!RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value)) {
      return -1;
    }
    final pieces = value.split(':');
    return int.parse(pieces[0]) * 60 + int.parse(pieces[1]);
  }

  @override
  void didUpdateWidget(NotificationOrganizationControls old) {
    super.didUpdateWidget(old);
    if (old.sourceRef != widget.sourceRef || old.value != widget.value) {
      if (_parse(_start.text) != widget.value.startMinute) {
        _start.text = _format(widget.value.startMinute);
      }
      if (_parse(_end.text) != widget.value.endMinute) {
        _end.text = _format(widget.value.endMinute);
      }
    }
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String t(String key) =>
        strings.text('settings.notification.organization.$key');
    return Column(
      key: ValueKey('organization-options-${widget.sourceRef}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        StarBridgeSelectFormField<NotificationChatMode>(
          identity: ('organization-chat', widget.sourceRef, widget.value.chat),
          controlKey: ValueKey('organization-chat-${widget.sourceRef}'),
          key: ValueKey((widget.sourceRef, widget.value.chat)),
          initialValue: widget.value.chat,
          decoration: InputDecoration(labelText: t('chat')),
          items: [
            for (final mode in NotificationChatMode.values)
              DropdownMenuItem(
                value: mode,
                child: Text(
                  t(
                    mode == NotificationChatMode.inherit
                        ? widget.official
                              ? 'inheritFleet'
                              : 'inheritOrganization'
                        : mode.name,
                  ),
                ),
              ),
          ],
          onChanged: widget.enabled
              ? (mode) {
                  if (mode != null) {
                    widget.onChanged(widget.value.copyWith(chat: mode));
                  }
                }
              : null,
        ),
        const SizedBox(height: 8),
        Text(t('chatHint')),
        const SizedBox(height: 16),
        StarBridgeSelectFormField<NotificationChatMode>(
          identity: (
            'organization-announcement',
            widget.sourceRef,
            widget.value.announcement,
          ),
          controlKey: ValueKey('organization-announcement-${widget.sourceRef}'),
          key: ValueKey((
            'announcement',
            widget.sourceRef,
            widget.value.announcement,
          )),
          initialValue: widget.value.announcement,
          decoration: InputDecoration(labelText: t('announcement')),
          items: [
            for (final mode in NotificationChatMode.values)
              DropdownMenuItem(
                value: mode,
                child: Text(
                  t(
                    mode == NotificationChatMode.inherit
                        ? widget.official
                              ? 'inheritFleet'
                              : 'inheritOrganization'
                        : mode.name,
                  ),
                ),
              ),
          ],
          onChanged: widget.enabled
              ? (mode) {
                  if (mode != null) {
                    widget.onChanged(widget.value.copyWith(announcement: mode));
                  }
                }
              : null,
        ),
        const SizedBox(height: 8),
        Text(t('announcementHint')),
        const SizedBox(height: 8),
        Text(t('unavailableEvents')),
        const SizedBox(height: 16),
        StarBridgeSwitch.tile(
          controlKey: ValueKey('organization-quiet-${widget.sourceRef}'),
          label: t('quiet'),
          value: widget.value.quietEnabled,
          onChanged: widget.enabled
              ? (enabled) => widget.onChanged(
                  widget.value.copyWith(quietEnabled: enabled),
                )
              : null,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 180,
              child: TextField(
                key: ValueKey('organization-quiet-start-${widget.sourceRef}'),
                controller: _start,
                enabled: widget.enabled,
                decoration: InputDecoration(
                  labelText: t('start'),
                  hintText: '22:00',
                ),
                onChanged: (text) => widget.onChanged(
                  widget.value.copyWith(startMinute: _parse(text)),
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                key: ValueKey('organization-quiet-end-${widget.sourceRef}'),
                controller: _end,
                enabled: widget.enabled,
                decoration: InputDecoration(
                  labelText: t('end'),
                  hintText: '08:00',
                ),
                onChanged: (text) => widget.onChanged(
                  widget.value.copyWith(endMinute: _parse(text)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(t('localClock')),
        Text(t('quietHint')),
        if (!widget.value.valid)
          Text(
            t('invalidTime'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (widget.official) ...[
          const SizedBox(height: 8),
          Text(t('rallyIndependent')),
        ],
      ],
    );
  }
}
