import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'community_sharing.dart';
import 'event_scope_editor.dart';

class CommunitySharingDialog extends StatefulWidget {
  const CommunitySharingDialog({
    required this.target,
    required this.onSave,
    this.onSaveHangar,
    this.onSaveEvents,
    this.initialEvents = const EventSharingChoice(
      enabled: true,
      selectedTypes: EventSharingChoice.allTypes,
    ),
    this.legacyTransition = false,
    this.sharingEnabled = true,
    super.key,
  });
  final CommunitySharingTarget target;
  final Future<bool> Function(CommunitySharingScope) onSave;
  final Future<bool> Function(bool)? onSaveHangar;
  final Future<bool> Function(EventSharingChoice)? onSaveEvents;
  final EventSharingChoice initialEvents;
  final bool legacyTransition, sharingEnabled;
  @override
  State<CommunitySharingDialog> createState() => _CommunitySharingDialogState();
}

class _CommunitySharingDialogState extends State<CommunitySharingDialog> {
  // Preselection is only a draft; opening the dialog never saves consent.
  int _fields = 15;
  bool _busy = false, _shareHangar = true;
  late EventSharingChoice _events = widget.initialEvents;
  String? _error;
  Future<void> _save(
    int fields, {
    bool? shareHangar,
    bool noEvents = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _fields = fields;
      _shareHangar = shareHangar ?? _shareHangar;
      if (noEvents) _events = _events.copyWith(enabled: false);
    });
    var saved = true;
    var failure = 'privacy.community.hangarFailed';
    // Keep discovery pending until all available choices are confirmed. Each
    // retry rereads independent consent instead of replaying uncertain writes.
    if (widget.onSaveHangar != null) {
      try {
        saved = await widget.onSaveHangar!(_shareHangar);
      } on Object {
        saved = false;
      }
      if (!mounted) return;
    }
    if (saved && widget.onSaveEvents != null) {
      failure = 'privacy.community.eventsFailed';
      try {
        saved = await widget.onSaveEvents!(_events);
      } on Object {
        saved = false;
      }
      if (!mounted) return;
    }
    if (saved) {
      failure = widget.onSaveEvents != null
          ? 'privacy.community.partialFailed'
          : widget.onSaveHangar == null
          ? 'privacy.community.failed'
          : 'privacy.community.statusFailed';
      try {
        saved = await widget.onSave(widget.target.choice(fields: fields));
      } on Object {
        saved = false;
      }
      if (!mounted) return;
    }
    if (saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('community-sharing-dialog'),
        title: Text(s.text('privacy.community.title')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.target.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(s.text('privacy.community.body')),
                if (widget.legacyTransition) ...[
                  const SizedBox(height: 8),
                  Text(s.text('privacy.community.legacy')),
                ],
                if (!widget.sharingEnabled) ...[
                  const SizedBox(height: 8),
                  Text(s.text('privacy.community.disabled')),
                ],
                const SizedBox(height: 12),
                for (final entry in const {
                  1: 'presence',
                  2: 'ship',
                  4: 'location',
                  8: 'server',
                }.entries)
                  CheckboxListTile(
                    key: Key('community-sharing-${entry.key}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(s.text('privacy.local.${entry.value}')),
                    value: _fields & entry.key != 0,
                    onChanged: _busy
                        ? null
                        : (checked) => setState(
                            () => _fields = checked == true
                                ? _fields | entry.key
                                : _fields & ~entry.key,
                          ),
                  ),
                CheckboxListTile(
                  key: const Key('community-sharing-hangar'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(s.text('privacy.local.hangar')),
                  subtitle: Text(
                    s.text(
                      widget.onSaveHangar == null
                          ? 'privacy.community.hangarUnavailable'
                          : 'privacy.community.hangarHint',
                    ),
                  ),
                  value: widget.onSaveHangar != null && _shareHangar,
                  onChanged: _busy || widget.onSaveHangar == null
                      ? null
                      : (checked) =>
                            setState(() => _shareHangar = checked == true),
                ),
                const Divider(),
                CheckboxListTile(
                  key: const Key('community-sharing-events'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(s.text('settings.privacy.events.title')),
                  subtitle: Text(
                    s.text(
                      widget.onSaveEvents == null
                          ? 'privacy.community.eventsUnavailable'
                          : 'privacy.community.eventsHint',
                    ),
                  ),
                  value: widget.onSaveEvents != null && _events.enabled,
                  onChanged: _busy || widget.onSaveEvents == null
                      ? null
                      : (checked) => setState(
                          () => _events = _events.copyWith(
                            enabled: checked == true,
                          ),
                        ),
                ),
                for (final entry in const {
                  'presence': 1,
                  'server': 2,
                  'ship': 4,
                  'location': 8,
                  'life': 32,
                }.entries)
                  CheckboxListTile(
                    key: Key('community-sharing-event-${entry.key}'),
                    contentPadding: const EdgeInsets.only(left: 16),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(s.text('settings.privacy.events.${entry.key}')),
                    value:
                        widget.onSaveEvents != null &&
                        _events.selectedTypes & entry.value != 0,
                    onChanged:
                        _busy || widget.onSaveEvents == null || !_events.enabled
                        ? null
                        : (checked) => setState(
                            () => _events = _events.copyWith(
                              selectedTypes: checked == true
                                  ? _events.selectedTypes | entry.value
                                  : _events.selectedTypes & ~entry.value,
                            ),
                          ),
                  ),
                if (_error != null) Text(s.text(_error!)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('community-sharing-none'),
            onPressed: _busy
                ? null
                : () => _save(0, shareHangar: false, noEvents: true),
            child: Text(s.text('privacy.community.none')),
          ),
          FilledButton(
            key: const Key('community-sharing-confirm'),
            onPressed:
                _busy ||
                    _fields == 0 &&
                        (widget.onSaveHangar == null || !_shareHangar) &&
                        (widget.onSaveEvents == null ||
                            _events.effectiveTypes == 0)
                ? null
                : () => _save(_fields),
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    s.text(
                      widget.sharingEnabled ||
                              widget.onSaveHangar != null && _shareHangar
                          ? 'privacy.community.confirm'
                          : 'privacy.community.save',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
