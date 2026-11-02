import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../settings/help_support_waiting.dart';
import 'personal_profile_models.dart';
import 'personal_profile_visibility.dart';

class ProfileVisibilityDialog extends StatefulWidget {
  const ProfileVisibilityDialog({required this.access, super.key});
  final ProfileVisibilityAccess access;
  @override
  State<ProfileVisibilityDialog> createState() =>
      _ProfileVisibilityDialogState();
}

class _ProfileVisibilityDialogState extends State<ProfileVisibilityDialog> {
  ProfileVisibilityState? _state;
  PersonalProfileVisibility? _selection;
  bool _busy = true;
  bool _failed = false;
  InteractionSource _waitSource = InteractionSource.programmatic;
  bool _savingPhase = false;
  int _waitPhase = 0;
  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final state = await widget.access.readVisibility();
      if (mounted) {
        setState(() {
          _state = state;
          _selection = state.visibility;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _state = null;
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final expected = _state;
    final selected = _selection;
    if (_busy || expected == null || selected == null) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.access.saveVisibility(expected, selected);
      if (mounted) {
        setState(() => _busy = false);
        dismissStarBridgeDialog(context, source: _waitSource);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
          _state = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(s.text('profile.visibility.title')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.text('profile.visibility.scopeNote')),
                const SizedBox(height: 12),
                if (_busy)
                  HelpSupportWaiting(
                    key: ValueKey(('profile-visibility-wait', _waitPhase)),
                    source: _waitSource,
                    label: s.text(
                      _savingPhase
                          ? 'settings.general.saving'
                          : 'settings.general.loading',
                    ),
                  ),
                if (_failed)
                  Semantics(
                    liveRegion: true,
                    child: Text(s.text('profile.visibility.failed')),
                  ),
                if (_state != null)
                  for (final value in _state!.availableVisibilities)
                    StarBridgeCheckboxTile(
                      controlKey: Key(
                        'profile-visibility-${value.bridgeValue}',
                      ),
                      label: s.text(value.labelKey),
                      dense: false,
                      trailingControl: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      value: _selection == value,
                      onChanged: _busy
                          ? null
                          : (_) => setState(() => _selection = value),
                    ),
              ],
            ),
          ),
        ),
        actions: [
          StarBridgeActionButton(
            controlKey: const Key('profile-visibility-cancel'),
            kind: StarBridgeActionKind.quiet,
            onActivate: _busy
                ? null
                : (source) => dismissStarBridgeDialog(context, source: source),
            child: Text(s.text('profile.visibility.cancel')),
          ),
          if (_failed)
            StarBridgeActionButton(
              controlKey: const Key('profile-visibility-reload'),
              onActivate: _busy
                  ? null
                  : (source) {
                      _waitSource = source;
                      _savingPhase = false;
                      _waitPhase++;
                      _read();
                    },
              child: Text(s.text('profile.refresh')),
            ),
          StarBridgeActionButton(
            controlKey: const Key('profile-visibility-save'),
            kind: StarBridgeActionKind.primary,
            onActivate: _busy || _state == null
                ? null
                : (source) {
                    _waitSource = source;
                    _savingPhase = true;
                    _waitPhase++;
                    _save();
                  },
            child: Text(s.text('profile.visibility.save')),
          ),
        ],
      ),
    );
  }
}
