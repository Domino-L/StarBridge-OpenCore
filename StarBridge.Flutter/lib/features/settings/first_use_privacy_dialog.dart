import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'local_privacy_settings.dart';

/// First-use notice, not a second privacy editor. Only explicit actions save.
class FirstUsePrivacyDialog extends StatefulWidget {
  const FirstUsePrivacyDialog({
    required this.initial,
    required this.onSave,
    this.organizationsPending = false,
    super.key,
  });
  final LocalPrivacySettings initial;
  final bool organizationsPending;
  final Future<bool> Function(LocalPrivacySettings choice) onSave;

  @override
  State<FirstUsePrivacyDialog> createState() => _FirstUsePrivacyDialogState();
}

class _FirstUsePrivacyDialogState extends State<FirstUsePrivacyDialog> {
  bool _saving = false;
  bool _failed = false;

  Future<void> _save(bool enabled) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    var saved = false;
    try {
      saved = await widget.onSave(
        widget.initial.copyWith(publicationEnabled: enabled),
      );
    } catch (_) {
      // A failed response must not be presented as a recorded choice.
    }
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _saving = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('first-privacy-choice-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: Text(s.text('privacy.first.title')),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.text('privacy.first.body')),
                const SizedBox(height: 20),
                Text(
                  s.text('privacy.first.scope'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.organizationsPending
                      ? s.text('privacy.first.organizationsPending')
                      : _scope(s, true),
                  key: const Key('first-privacy-fleet-summary'),
                ),
                const SizedBox(height: 8),
                Text(
                  _scope(s, false),
                  key: const Key('first-privacy-room-summary'),
                ),
                const SizedBox(height: 12),
                Text(
                  s.text('privacy.first.excluded'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Divider(height: 28),
                Text(s.text('privacy.first.remember')),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('first-privacy-adjust'),
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(true),
                  child: Text(s.text('privacy.first.adjust')),
                ),
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      s.text('privacy.first.failed'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('first-privacy-decline'),
            onPressed: _saving ? null : () => _save(false),
            child: Text(s.text('privacy.first.decline')),
          ),
          FilledButton(
            key: const Key('first-privacy-accept'),
            onPressed: _saving ? null : () => _save(true),
            child: Text(
              s.text(_saving ? 'privacy.local.saving' : 'privacy.first.accept'),
            ),
          ),
        ],
      ),
    );
  }

  String _scope(AppStrings s, bool fleet) {
    final choice = widget.initial;
    final fields = fleet ? choice.fleetFields : choice.roomFields;
    final audiences = <String>[];
    if (fleet ? choice.fleetAllMembersCanView : choice.roomAllMembersCanView) {
      audiences.add(s.text('privacy.local.allMembers'));
    } else if (fleet) {
      if (choice.fleetAdministratorsCanView) {
        audiences.add(s.text('privacy.local.administrators'));
      }
      if (choice.fleetVisibilityGroupIds.isNotEmpty) {
        audiences.add(
          s
              .text('privacy.first.selectedGroups')
              .replaceAll(
                '{count}',
                '${choice.fleetVisibilityGroupIds.length}',
              ),
        );
      }
    }
    final selected = [
      for (final entry in const {
        1: 'presence',
        2: 'ship',
        4: 'location',
        8: 'server',
      }.entries)
        if (fields & entry.key != 0) s.text('privacy.local.${entry.value}'),
    ];
    final scope = audiences.isEmpty || selected.isEmpty
        ? s.text('privacy.first.none')
        : '${audiences.join(s.text('privacy.first.separator'))} · ${selected.join(s.text('privacy.first.separator'))}';
    return s
        .text('privacy.first.scopeLine')
        .replaceAll(
          '{audience}',
          s.text(fleet ? 'privacy.first.organizations' : 'privacy.local.room'),
        )
        .replaceAll('{scope}', scope);
  }
}
