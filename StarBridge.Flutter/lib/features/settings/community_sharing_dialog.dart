import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'community_sharing.dart';
import 'event_scope_editor.dart';
import 'help_support_action.dart';
import 'help_support_waiting.dart';

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
  InteractionSource _waitSource = InteractionSource.programmatic;
  int _waitPhase = 0;
  Future<void> _save(
    int fields, {
    bool? shareHangar,
    bool noEvents = false,
    required InteractionSource source,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _waitSource = source;
      _waitPhase++;
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
      dismissStarBridgeDialog<void>(context, source: _waitSource);
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: HelpSupportWaiting(
                    key: ValueKey(('community-sharing-wait', _waitPhase)),
                    label: s.text('privacy.local.saving'),
                    source: _waitSource,
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(s.text(_error!)),
                  ),
                ),
              Flexible(
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
                        _checkbox(
                          key: Key('community-sharing-${entry.key}'),
                          contentPadding: EdgeInsets.zero,
                          dense: false,
                          label: s.text('privacy.local.${entry.value}'),
                          value: _fields & entry.key != 0,
                          onChanged: _busy
                              ? null
                              : (checked) => setState(
                                  () => _fields = checked == true
                                      ? _fields | entry.key
                                      : _fields & ~entry.key,
                                ),
                        ),
                      _checkbox(
                        key: const Key('community-sharing-hangar'),
                        contentPadding: EdgeInsets.zero,
                        dense: false,
                        label: s.text('privacy.local.hangar'),
                        subtitle: s.text(
                          widget.onSaveHangar == null
                              ? 'privacy.community.hangarUnavailable'
                              : 'privacy.community.hangarHint',
                        ),
                        value: widget.onSaveHangar != null && _shareHangar,
                        onChanged: _busy || widget.onSaveHangar == null
                            ? null
                            : (checked) => setState(
                                () => _shareHangar = checked == true,
                              ),
                      ),
                      const Divider(),
                      _checkbox(
                        key: const Key('community-sharing-events'),
                        contentPadding: EdgeInsets.zero,
                        dense: false,
                        label: s.text('settings.privacy.events.title'),
                        subtitle: s.text(
                          widget.onSaveEvents == null
                              ? 'privacy.community.eventsUnavailable'
                              : 'privacy.community.eventsHint',
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
                        _checkbox(
                          key: Key('community-sharing-event-${entry.key}'),
                          contentPadding: const EdgeInsets.only(left: 16),
                          dense: false,
                          label: s.text('settings.privacy.events.${entry.key}'),
                          value:
                              widget.onSaveEvents != null &&
                              _events.selectedTypes & entry.value != 0,
                          onChanged:
                              _busy ||
                                  widget.onSaveEvents == null ||
                                  !_events.enabled
                              ? null
                              : (checked) => setState(
                                  () => _events = _events.copyWith(
                                    selectedTypes: checked == true
                                        ? _events.selectedTypes | entry.value
                                        : _events.selectedTypes & ~entry.value,
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          HelpSupportAction(
            controlKey: const Key('community-sharing-none'),
            onActivate: _busy
                ? null
                : (source) => _save(
                    0,
                    shareHangar: false,
                    noEvents: true,
                    source: source,
                  ),
            child: Text(s.text('privacy.community.none')),
          ),
          HelpSupportAction(
            controlKey: const Key('community-sharing-confirm'),
            kind: StarBridgeActionKind.primary,
            onActivate:
                _busy ||
                    _fields == 0 &&
                        (widget.onSaveHangar == null || !_shareHangar) &&
                        (widget.onSaveEvents == null ||
                            _events.effectiveTypes == 0)
                ? null
                : (source) => _save(_fields, source: source),
            child: Text(
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

  Widget _checkbox({
    required Key key,
    required String label,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required EdgeInsetsGeometry contentPadding,
    required bool dense,
    String? subtitle,
  }) {
    // CheckboxListTile uses a shrink-wrapped native checkbox. Keep its public
    // leading geometry in every suite, without changing the shared adapter.
    final adjustment =
        (CheckboxTheme.of(context).visualDensity ??
                Theme.of(context).visualDensity)
            .baseSizeAdjustment;
    return StarBridgeCheckboxTile(
      key: key,
      label: label,
      value: value,
      onChanged: onChanged,
      subtitle: subtitle,
      contentPadding: contentPadding,
      dense: dense,
      rowBuilder: (control) => ListTile(
        dense: dense,
        contentPadding: contentPadding,
        enabled: onChanged != null,
        leading: SizedBox(
          width: 40 + adjustment.dx,
          height: 40 + adjustment.dy,
          child: control,
        ),
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle),
      ),
    );
  }
}
