import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../shared/clock_field.dart';
import 'exec_hangar_motion_controls.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'exec_hangar_port.dart';

/// Lead-time presets for open and close reminders, in minutes (1–120).
const execHangarLeadMinutes = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120];

final class ExecHangarReminderEditor extends StatelessWidget {
  const ExecHangarReminderEditor({
    super.key,
    required this.t,
    required this.form,
    required this.draft,
    required this.beforeOpen,
    required this.beforeClose,
    required this.busy,
    required this.dirty,
    required this.conflict,
    required this.onToggle,
    required this.onEdited,
    required this.onSave,
    required this.onReset,
    required this.deliveryState,
    this.showActions = true,
  });
  final String Function(String) t;
  final GlobalKey<FormState> form;
  final ExecHangarReminders draft;
  final TextEditingController beforeOpen, beforeClose;
  final bool busy, dirty, conflict;
  final void Function({
    bool? onOpen,
    bool? beforeOpen,
    bool? beforeClose,
    bool? onClose,
    bool? leaveWarning,
    bool? autoDuringGame,
  })
  onToggle;
  final VoidCallback onEdited, onSave, onReset;
  final String? deliveryState;
  final bool showActions;
  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: context.tokens.space.md,
          runSpacing: context.tokens.space.sm,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('reminders'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  t(dirty ? 'draftChanged' : 'rulesSaved'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: dirty
                        ? context.tokens.colors.warning
                        : context.tokens.colors.textSecondary,
                  ),
                ),
              ],
            ),
            if (showActions)
              Wrap(
                spacing: context.tokens.space.xs,
                children: [
                  ExecHangarMotionButton(
                    FilledButton.tonal(
                      key: const Key('exec-save'),
                      onPressed: busy || !dirty || conflict ? null : onSave,
                      child: Text(t('save')),
                    ),
                  ),
                  ExecHangarMotionButton(
                    TextButton(
                      onPressed: busy || !dirty ? null : onReset,
                      child: Text(t('reset')),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (!draft.onOpen &&
            !draft.beforeOpen &&
            !draft.beforeClose &&
            !draft.onClose &&
            !draft.leaveWarning)
          Text(t('noRules')),
        SizedBox(height: context.tokens.space.md),
        execHangarSwitch(
          SwitchListTile(
            key: const Key('exec-auto-game'),
            contentPadding: EdgeInsets.zero,
            title: Text(t('autoGame')),
            subtitle: Text(t('autoGameHint')),
            value: draft.autoDuringGame,
            onChanged: busy ? null : (v) => onToggle(autoDuringGame: v),
          ),
        ),
        SizedBox(height: context.tokens.space.md),
        LayoutBuilder(
          builder: (context, constraints) {
            Widget rules(bool opening) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(opening ? 'openingRules' : 'closingRules'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                _lead(
                  context,
                  opening
                      ? 'exec-before-open-minutes'
                      : 'exec-before-close-minutes',
                  t(opening ? 'beforeOpen' : 'beforeClose'),
                  opening ? beforeOpen : beforeClose,
                  opening ? draft.beforeOpen : draft.beforeClose,
                  (v) => opening
                      ? onToggle(beforeOpen: v)
                      : onToggle(beforeClose: v),
                ),
                execHangarCheckbox(
                  CheckboxListTile(
                    key: Key(opening ? 'exec-on-open' : 'exec-on-close'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: Text(t(opening ? 'onOpen' : 'onClose')),
                    value: opening ? draft.onOpen : draft.onClose,
                    onChanged: busy
                        ? null
                        : (v) => opening
                              ? onToggle(onOpen: v)
                              : onToggle(onClose: v),
                  ),
                ),
              ],
            );
            if (constraints.maxWidth < 520) {
              return Column(
                children: [
                  rules(true),
                  SizedBox(height: context.tokens.space.md),
                  rules(false),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: rules(true)),
                SizedBox(width: context.tokens.space.xl),
                Expanded(child: rules(false)),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        execHangarCheckbox(
          CheckboxListTile(
            key: const Key('exec-leave-rule'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(t('leaveRule')),
            subtitle: Text(t('leaveRuleHint')),
            value: draft.leaveWarning,
            onChanged: busy ? null : (v) => onToggle(leaveWarning: v),
          ),
        ),
        Text(
          t(draft.autoDuringGame ? 'autoGameSave' : 'saveOnly'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          t('channels'),
          style: TextStyle(color: context.tokens.colors.textSecondary),
        ),
        if (deliveryState == 'windowsDisabled') Text(t('windowsDisabled')),
        if (deliveryState == 'failed') Text(t('deliveryFailed')),
        if (conflict) Text(t('changedElsewhere')),
      ],
    ),
  );
  Widget _lead(
    BuildContext context,
    String id,
    String label,
    TextEditingController controller,
    bool enabled,
    ValueChanged<bool?> change,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: execHangarCheckbox(
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            value: enabled,
            onChanged: busy ? null : change,
          ),
        ),
      ),
      SizedBox(width: context.tokens.space.sm),
      // Presets, not typing (user decision 2026-10-22); a saved value off
      // the presets stays listed so it is kept as is.
      SizedBox(
        width: 150,
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, text, _) {
            final current = int.tryParse(text.text);
            final values = [
              ...execHangarLeadMinutes,
              if (current != null &&
                  current >= 1 &&
                  current <= 120 &&
                  !execHangarLeadMinutes.contains(current))
                current,
            ]..sort();
            return StarBridgeSelectFormField<int>(
              identity: id,
              controlKey: Key(id),
              initialValue: values.contains(current) ? current : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: t('minutes'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final v in values)
                  DropdownMenuItem(
                    value: v,
                    child: Text(clockDuration(context, v)),
                  ),
              ],
              validator: (v) => v == null ? t('range') : null,
              onChanged: busy
                  ? null
                  : (v) {
                      if (v == null) return;
                      controller.text = '$v';
                      onEdited();
                    },
            );
          },
        ),
      ),
    ],
  );
}
