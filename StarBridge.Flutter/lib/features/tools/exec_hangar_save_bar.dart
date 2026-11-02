import 'exec_hangar_motion_controls.dart';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// Keeps a dirty draft's explicit actions available while scrolling the form.
final class ExecHangarSaveBar extends StatelessWidget {
  const ExecHangarSaveBar({
    super.key,
    required this.busy,
    required this.conflict,
    required this.onSave,
    required this.onReset,
  });
  final bool busy, conflict;
  final VoidCallback onSave, onReset;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    String t(String key) => AppStrings.of(context).text('execHangar.$key');
    return Material(
      color: tokens.surfaces.chrome.fill,
      child: SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.lg,
            vertical: tokens.space.sm,
          ),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: tokens.surfaces.chrome.border),
            ),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: tokens.space.md,
            runSpacing: tokens.space.xs,
            children: [
              Text(
                t('draftChanged'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.warning),
              ),
              Wrap(
                spacing: tokens.space.sm,
                children: [
                  ExecHangarMotionButton(
                    TextButton(
                      onPressed: busy ? null : onReset,
                      child: Text(t('reset')),
                    ),
                  ),
                  ExecHangarMotionButton(
                    FilledButton(
                      key: const Key('exec-save'),
                      onPressed: busy || conflict ? null : onSave,
                      child: Text(t('save')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
