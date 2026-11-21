import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_select_field.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import 'overlay_workspace_number_field.dart';

import '../../app/localization/app_strings.dart';
import '../../app/routing/open_destination_intent.dart';
import '../../app/routing/screen_reading_route.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_rules.dart';
import 'overlay_workspace_schema.dart';
import 'overlay_workspace_value_format.dart';
import 'overlay_color_picker.dart';
import 'overlay_settings_help.dart';
import 'overlay_appearance_qualification.dart';

export 'overlay_workspace_hotkey_card.dart';

class OverlayWorkspaceSettingsGroup extends StatelessWidget {
  const OverlayWorkspaceSettingsGroup({
    required this.group,
    required this.fields,
    required this.settings,
    required this.onChanged,
    this.appearances = const [],
    this.appearanceRule,
    this.onExperiencePreset,
    this.footer,
    this.header,
    this.editOwner,
    this.currentEditOwner,
    super.key,
  });

  final String group;
  final List<OverlayWorkspaceFieldSpec> fields;
  final OverlayWorkspaceSettings settings;
  final void Function(String field, Object? value) onChanged;
  final List<OverlayWorkspaceAppearance> appearances;
  // Preview supplies metadata without altering the normal saved skin enum.
  final OverlayWorkspaceAppearanceRule? appearanceRule;
  final ValueChanged<String>? onExperiencePreset;
  final Widget? footer;
  final Widget? header;
  final Object? editOwner;
  final Object? Function()? currentEditOwner;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final profile = appearanceRule ?? overlayWorkspaceAppearanceRule(settings);
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      key: Key('overlay-group-$group'),
      padding: EdgeInsets.all(tokens.space.md),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              overlayWorkspaceGroupName(context, group),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (header != null) ...[SizedBox(height: tokens.space.md), header!],
            if (group == 'appearance' && profile.locksTheme) ...[
              SizedBox(height: tokens.space.sm),
              OverlaySettingsHelp(
                _copy(context, 'overlay.workspace.fixedPalette'),
                key: const Key('overlay-appearance-fixed-palette'),
              ),
            ],
            SizedBox(height: tokens.space.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 900
                    ? (constraints.maxWidth - tokens.space.md) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: tokens.space.md,
                  runSpacing: tokens.space.sm,
                  children: fields
                      .where(
                        (field) =>
                            field.userVisible &&
                            overlayWorkspaceFieldVisible(
                              field.field,
                              settings,
                              appearanceRule: profile,
                            ),
                      )
                      .map(
                        (field) => SizedBox(
                          width:
                              field.kind ==
                                      OverlayWorkspaceFieldKind
                                          .eventDurations ||
                                  field.kind ==
                                      OverlayWorkspaceFieldKind.eventTypes
                              ? constraints.maxWidth
                              : width,
                          child: OverlayWorkspaceField(
                            spec: field,
                            labelKey: overlayWorkspaceFieldLabelKey(
                              field.field,
                              settings,
                            ),
                            editOwner: editOwner,
                            currentEditOwner: currentEditOwner,
                            value: field.field == 'startupTransitionStyle'
                                ? profile.startupTransition
                                : settings[field.field],
                            appearances: appearances,
                            enabled: overlayWorkspaceFieldEnabled(
                              field.field,
                              settings,
                              appearanceRule: profile,
                            ),
                            disabledReason: overlayWorkspaceFieldDisabledReason(
                              field.field,
                              settings,
                              appearanceRule: profile,
                            ),
                            onChanged: (value) => onChanged(field.field, value),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
            if (group == 'members') const _HealthRingNote(),
            if (footer != null) ...[
              SizedBox(height: tokens.space.md),
              Divider(color: tokens.surfaces.panel.border),
              SizedBox(height: tokens.space.sm),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Smooth / balanced / reduced motion: sets the open and close animation and
/// the overlay's frame rate together (in the global group since 11-11).
class OverlayExperiencePresetPicker extends StatelessWidget {
  const OverlayExperiencePresetPicker({
    required this.settings,
    required this.onSelected,
    super.key,
  });

  final OverlayWorkspaceSettings settings;
  final ValueChanged<String> onSelected;

  String get _selected {
    final enabled = settings['enableStartupTransition'] == true;
    final startup = settings['startupTransitionFrameRate'];
    final animation = settings['animationFrameRate'];
    if (!enabled) return 'ReducedMotion';
    if (startup == 'Fps120' && animation == 'Fps120') return 'Smooth';
    if (startup == 'Fps60' && animation == 'Fps60') return 'Balanced';
    return 'Custom';
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final tokens = context.tokens;
    return Column(
      key: const Key('overlay-experience-presets'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _copy(context, 'overlay.workspace.experience.title'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: tokens.space.xs),
        OverlaySettingsHelp(
          _copy(context, 'overlay.workspace.experience.$selected'),
        ),
        SizedBox(height: tokens.space.sm),
        Wrap(
          spacing: tokens.space.xs,
          runSpacing: tokens.space.xs,
          children: const ['Smooth', 'Balanced', 'ReducedMotion']
              .map(
                (preset) => StarBridgeChoiceChip(
                  controlKey: Key('overlay-experience-$preset'),
                  label: _copy(context, 'overlay.workspace.experience.$preset'),
                  selected: preset == selected,
                  onSelected: (_) => onSelected(preset),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class OverlayWorkspaceField extends StatelessWidget {
  const OverlayWorkspaceField({
    required this.spec,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.appearances = const [],
    this.disabledReason,
    this.editOwner,
    this.currentEditOwner,
    this.labelKey,
    this.onStep,
    super.key,
  });

  final OverlayWorkspaceFieldSpec spec;
  final Object? value;
  final bool enabled;
  final ValueChanged<Object?> onChanged;

  /// A label that depends on other settings (the members size: maximum or fixed).
  final String? labelKey;
  final ValueChanged<Object?>? onStep;
  final List<OverlayWorkspaceAppearance> appearances;
  final String? disabledReason;
  final Object? editOwner;
  final Object? Function()? currentEditOwner;

  @override
  Widget build(BuildContext context) {
    final label = labelKey == null
        ? _fieldName(context, spec)
        : _copy(context, labelKey!);
    final helper = disabledReason != null
        ? _copy(context, disabledReason!)
        // The visor, like every overlay, is covered by a game in exclusive
        // fullscreen; borderless window mode keeps it visible.
        : spec.field == 'visorSize'
        ? _copy(context, 'overlay.workspace.hint.visorBorderless')
        : spec.field == 'visorTilt'
        ? _copy(context, 'overlay.workspace.hint.visorTilt')
        : spec.field == 'visorViewingDistance'
        ? _copy(context, 'overlay.workspace.hint.visorViewingDistance')
        : spec.field == 'visorChatPlate'
        ? _copy(context, 'overlay.workspace.hint.visorChatPlate')
        // 11-10 user (settings comparison): say what these do on the visor
        : const {
            'eventNotificationSide',
            'eventNotificationMaxVisibleCount',
            'eventNotificationAnimationSpeed',
            'enableStartupTransition',
            'hideSelfMember',
            'animationFrameRate',
            // 11-12: the colour changes only the decoration
            'theme',
          }.contains(spec.field)
        ? _copy(context, 'overlay.workspace.hint.${spec.field}')
        : const {
            'visorMembersAutoWidth',
            'visorMembersAutoHeight',
            'visorMembersWidth',
            'visorMembersHeight',
            'visorEventsAutoWidth',
            'visorEventsWidth',
            'visorChatAutoWidth',
            'visorChatWidth',
          }.contains(spec.field)
        ? _copy(context, 'overlay.workspace.hint.${spec.field}')
        : null;
    final numberValue = value is num ? (value! as num).toDouble() : null;
    return switch (spec.kind) {
      OverlayWorkspaceFieldKind.choice
          when spec.field == 'skin' && appearances.isNotEmpty =>
        _AppearanceSelector(
          appearances: appearances,
          value: value?.toString(),
          enabled: enabled,
          onChanged: onChanged,
        ),
      OverlayWorkspaceFieldKind.toggle => StarBridgeSwitch.tile(
        key: Key('overlay-field-${spec.field}'),
        label: label,
        subtitle: helper,
        value: value == true,
        onChanged: enabled ? (next) => onChanged(next) : null,
      ),
      OverlayWorkspaceFieldKind.choice => StarBridgeSelectField<String>(
        key: Key('overlay-field-${spec.field}'),
        identity: 'overlay-field-${spec.field}',
        value: spec.options.contains(value) ? value as String : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
        ),
        options: _choiceOptions(context, spec, value),
        onSelected: enabled ? (next, _) => onChanged(next) : null,
      ),
      OverlayWorkspaceFieldKind.readOnlyChoice => InputDecorator(
        key: Key('overlay-field-${spec.field}'),
        decoration: InputDecoration(
          labelText: label,
          helperText: _copy(context, 'overlay.workspace.appearanceBoundValue'),
        ),
        child: Text(_optionName(context, value?.toString() ?? '')),
      ),
      OverlayWorkspaceFieldKind.numberChoice => StarBridgeSelectField<num>(
        key: Key('overlay-field-${spec.field}'),
        identity: 'overlay-field-${spec.field}',
        value: numberValue != null
            ? spec.numberOptions.cast<num?>().firstWhere(
                (option) => option?.toDouble() == numberValue,
                orElse: () => null,
              )
            : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
        ),
        options: spec.numberOptions
            .map(
              (option) => StarBridgeSelectOption<num>(
                value: option,
                label: _numberOptionName(context, spec, option),
              ),
            )
            .toList(growable: false),
        onSelected: enabled ? (next, _) => onChanged(next) : null,
      ),
      OverlayWorkspaceFieldKind.number => OverlayWorkspaceNumberField(
        onStep: enabled ? onStep : null,
        spec: spec,
        label: label,
        value: value,
        helperText: helper,
        onChanged: enabled ? onChanged : null,
      ),
      OverlayWorkspaceFieldKind.color => OverlayColorField(
        key: ValueKey('overlay-field-${spec.field}'),
        value: value?.toString() ?? '#FFFFFF',
        label: label,
        helperText: helper,
        editOwner: editOwner,
        currentEditOwner: currentEditOwner,
        onChanged: enabled ? onChanged : null,
      ),
      OverlayWorkspaceFieldKind.eventTypes => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
        ),
        child: _EventTypeField(
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      ),
      OverlayWorkspaceFieldKind.hotkey => InputDecorator(
        key: ValueKey('overlay-field-${spec.field}'),
        decoration: InputDecoration(labelText: label, helperText: helper),
        child: Text(switch (value) {
          String text when text.isNotEmpty => text,
          _ => '—',
        }),
      ),
      OverlayWorkspaceFieldKind.eventDurations => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
        ),
        child: _EventDurationField(
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    };
  }
}

List<StarBridgeSelectOption<String>> _choiceOptions(
  BuildContext context,
  OverlayWorkspaceFieldSpec spec,
  Object? current,
) {
  final selectable = spec.selectableOptions.isEmpty
      ? spec.options
      : spec.selectableOptions;
  return [
    // Legacy known values remain visible, without reopening retired choices.
    if (current is String &&
        spec.options.contains(current) &&
        !selectable.contains(current))
      StarBridgeSelectOption(
        value: current,
        label: _optionName(context, current),
        enabled: false,
      ),
    for (final option in selectable)
      StarBridgeSelectOption(
        value: option,
        label: _optionName(context, option),
      ),
  ];
}

class _AppearanceSelector extends StatelessWidget {
  const _AppearanceSelector({
    required this.appearances,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final List<OverlayWorkspaceAppearance> appearances;
  final String? value;
  final bool enabled;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    final traditional =
        Localizations.localeOf(context).scriptCode == 'Hant' ||
        Localizations.localeOf(context).countryCode == 'TW' ||
        Localizations.localeOf(context).countryCode == 'HK';
    final selected =
        appearances.any(
          (appearance) => appearance.id == value && appearance.isAvailable,
        )
        ? value
        : appearances.firstWhere((appearance) => appearance.isAvailable).id;
    final qualificationUnknown = OverlayAppearanceQualification.unknownOf(
      context,
    );
    return StarBridgeSelectField<String>(
      key: const Key('overlay-field-skin'),
      identity: 'overlay-field-skin',
      value: selected,
      decoration: InputDecoration(
        labelText: _fieldName(
          context,
          overlayWorkspaceFieldSpecs.singleWhere(
            (field) => field.field == 'skin',
          ),
        ),
      ),
      options: appearances
          .map(
            (appearance) => StarBridgeSelectOption<String>(
              value: appearance.id,
              enabled: appearance.isAvailable,
              label:
                  '${english ? appearance.displayNameEn : appearance.displayNameZh}'
                  '${appearance.isAvailable
                      ? ''
                      : qualificationUnknown && appearance.isReleased
                      ? traditional
                            ? '（離線時暫不可切換）'
                            : english
                            ? ' (unavailable while offline)'
                            : '（离线时暂不可切换）'
                      : traditional
                      ? '（未解鎖）'
                      : english
                      ? ' (locked)'
                      : '（未解锁）'}',
            ),
          )
          .toList(growable: false),
      onSelected: enabled ? (next, _) => onChanged(next) : null,
    );
  }
}

class _EventTypeField extends StatelessWidget {
  const _EventTypeField({required this.value, required this.onChanged});

  final Object? value;
  final ValueChanged<Object?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value is int ? value! as int : 0;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: overlayEventTypes
          .map((entry) {
            final enabled = selected & entry.$1 != 0;
            return StarBridgeChoiceChip.filter(
              controlKey: Key('overlay-event-type-${entry.$1}'),
              label: _copy(context, 'overlay.workspace.event.${entry.$1}'),
              selected: enabled,
              onSelected: onChanged == null
                  ? null
                  : (_) => onChanged!(
                      enabled ? selected & ~entry.$1 : selected | entry.$1,
                    ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _EventDurationField extends StatelessWidget {
  const _EventDurationField({required this.value, required this.onChanged});

  final Object? value;
  final ValueChanged<Object?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final durations = value is Map
        ? Map<String, Object?>.from(value! as Map)
        : <String, Object?>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: overlayDurationFields
          .map((entry) {
            final number = durations[entry.$1];
            final seconds = number is num
                ? number.toDouble().clamp(0, 30).toDouble()
                : 0.0;
            return _EventDurationEntry(
              key: ValueKey('overlay-duration-${entry.$1}'),
              field: entry.$1,
              label: _copy(context, 'overlay.workspace.duration.${entry.$1}'),
              seconds: seconds,
              enabled: onChanged != null,
              onCommitted: (next) => onChanged?.call(
                Map<String, Object?>.from(durations)..[entry.$1] = next,
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _EventDurationEntry extends StatefulWidget {
  const _EventDurationEntry({
    required this.field,
    required this.label,
    required this.seconds,
    required this.enabled,
    required this.onCommitted,
    super.key,
  });

  final String field;
  final String label;
  final double seconds;
  final bool enabled;
  final ValueChanged<double> onCommitted;

  @override
  State<_EventDurationEntry> createState() => _EventDurationEntryState();
}

class _EventDurationEntryState extends State<_EventDurationEntry> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.seconds));
    _focus = FocusNode()..addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant _EventDurationEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.seconds != widget.seconds) {
      _controller.text = _format(widget.seconds);
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_handleFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final raw = _controller.text.trim();
    final parsed = raw.isEmpty ? 0.0 : double.tryParse(raw);
    if (parsed == null) {
      _controller.text = _format(widget.seconds);
      return;
    }
    final normalized = parsed <= 0 ? 0.0 : parsed.clamp(1, 30).toDouble();
    _controller.text = _format(normalized);
    if (normalized != widget.seconds) widget.onCommitted(normalized);
  }

  static String _format(double seconds) => seconds <= 0
      ? ''
      : seconds == seconds.roundToDouble()
      ? seconds.toInt().toString()
      : seconds.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: StarBridgeFieldFrame(
      focusNode: _focus,
      enabled: widget.enabled,
      builder: (_, focus) => TextField(
        key: Key('overlay-duration-${widget.field}-input'),
        controller: _controller,
        focusNode: focus,
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: _copy(context, 'overlay.workspace.durationDefault'),
          suffixText: _copy(context, 'overlay.workspace.durationSecondsSuffix'),
        ),
        onSubmitted: (_) => _commit(),
      ),
    ),
  );
}

String overlayWorkspaceGroupName(BuildContext context, String group) =>
    _copy(context, 'overlay.workspace.group.$group');

String _optionName(BuildContext context, String value) {
  final key = 'overlay.workspace.option.$value';
  final translated = _copy(context, key);
  return translated == key ? value : translated;
}

String _numberOptionName(
  BuildContext context,
  OverlayWorkspaceFieldSpec spec,
  num value,
) {
  final normalized = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
  final key = 'overlay.workspace.option.${spec.field}.$normalized';
  final translated = _copy(context, key);
  return translated == key
      ? overlayWorkspaceFormatValue(spec, value, AppStrings.of(context))
      : translated;
}

String _fieldName(BuildContext context, OverlayWorkspaceFieldSpec spec) {
  final key = 'overlay.workspace.field.${spec.field}';
  final translated = _copy(context, key);
  return translated == key ? spec.labelZh : translated;
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);

/// The health ring (user, 11-10): only someone who reads their own health has
/// one, and that switch is a local setting in the client's own settings
/// ("读血不应该放在这里吧，这是一个本机设置"), in the screen reading section.
/// The link shows only once that section exists, so it never leads nowhere.
class _HealthRingNote extends StatelessWidget {
  const _HealthRingNote();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      key: const Key('overlay-members-health-ring-note'),
      padding: EdgeInsets.only(top: tokens.space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: OverlaySettingsHelp(
              _copy(context, 'overlay.workspace.hint.healthRing'),
            ),
          ),
          if (screenReadingSettingsAvailable)
            TextButton(
              key: const Key('overlay-members-open-screen-reading'),
              onPressed: () => Actions.maybeInvoke(
                context,
                const OpenDestinationIntent(screenReadingSettingsRoute),
              ),
              child: Text(_copy(context, 'overlay.workspace.healthRing.open')),
            ),
        ],
      ),
    );
  }
}
