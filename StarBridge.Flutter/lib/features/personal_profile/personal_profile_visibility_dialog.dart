import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
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
        Navigator.of(context).pop();
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
                if (_busy) const LinearProgressIndicator(),
                if (_failed) Text(s.text('profile.visibility.failed')),
                if (_state != null)
                  for (final value in const [
                    PersonalProfileVisibility.everyone,
                    PersonalProfileVisibility.friendsFleetAndOrganizations,
                    PersonalProfileVisibility.friendsOnly,
                    PersonalProfileVisibility.onlyMe,
                  ])
                    CheckboxListTile(
                      key: Key('profile-visibility-${value.bridgeValue}'),
                      title: Text(s.text(value.labelKey)),
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
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(s.text('profile.visibility.cancel')),
          ),
          if (_failed)
            OutlinedButton(
              onPressed: _busy ? null : _read,
              child: Text(s.text('profile.refresh')),
            ),
          FilledButton(
            onPressed: _busy || _state == null ? null : _save,
            child: Text(s.text('profile.visibility.save')),
          ),
        ],
      ),
    );
  }
}
