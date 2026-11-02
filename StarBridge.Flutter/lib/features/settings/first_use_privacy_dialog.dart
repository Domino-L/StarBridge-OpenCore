import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'help_support_action.dart';
import 'help_support_waiting.dart';
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
  InteractionSource _waitSource = InteractionSource.programmatic;
  int _waitPhase = 0;

  Future<void> _save(bool enabled, InteractionSource source) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _waitSource = source;
      _waitPhase++;
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
      dismissStarBridgeDialog<bool>(
        context,
        source: _waitSource,
        result: false,
      );
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_saving)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: HelpSupportWaiting(
                    key: ValueKey(('first-privacy-wait', _waitPhase)),
                    label: s.text('privacy.local.saving'),
                    source: _waitSource,
                  ),
                ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      s.text('privacy.first.failed'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              Flexible(
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
                      HelpSupportAction(
                        controlKey: const Key('first-privacy-adjust'),
                        onActivate: _saving
                            ? null
                            : (source) => dismissStarBridgeDialog<bool>(
                                context,
                                source: source,
                                result: true,
                              ),
                        child: Text(s.text('privacy.first.adjust')),
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
            controlKey: const Key('first-privacy-decline'),
            onActivate: _saving ? null : (source) => _save(false, source),
            child: Text(s.text('privacy.first.decline')),
          ),
          HelpSupportAction(
            controlKey: const Key('first-privacy-accept'),
            kind: StarBridgeActionKind.primary,
            onActivate: _saving ? null : (source) => _save(true, source),
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
