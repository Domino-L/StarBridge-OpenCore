import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_rules.dart';
import 'overlay_workspace_schema.dart';

export 'overlay_workspace_hotkey_card.dart';

class OverlayWorkspaceSettingsGroup extends StatelessWidget {
  const OverlayWorkspaceSettingsGroup({
    required this.group,
    required this.fields,
    required this.settings,
    required this.onChanged,
    this.appearances = const [],
    this.onExperiencePreset,
    this.footer,
    super.key,
  });

  final String group;
  final List<OverlayWorkspaceFieldSpec> fields;
  final OverlayWorkspaceSettings settings;
  final void Function(String field, Object? value) onChanged;
  final List<OverlayWorkspaceAppearance> appearances;
  final ValueChanged<String>? onExperiencePreset;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
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
            if (group == 'appearance' &&
                overlayWorkspaceAppearanceRule(settings).locksTheme) ...[
              SizedBox(height: tokens.space.sm),
              Text(
                _copy(context, 'overlay.workspace.fixedPalette'),
                key: const Key('overlay-appearance-fixed-palette'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
            ],
            if (group == 'startup' && onExperiencePreset != null) ...[
              SizedBox(height: tokens.space.sm),
              _ExperiencePresetPicker(
                settings: settings,
                onSelected: onExperiencePreset!,
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
                            overlayWorkspaceFieldVisible(field.field, settings),
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
                          child: _Field(
                            spec: field,
                            value: field.field == 'startupTransitionStyle'
                                ? overlayWorkspaceAppearanceRule(settings)
                                      .startupTransition
                                : settings[field.field],
                            appearances: appearances,
                            enabled: overlayWorkspaceFieldEnabled(
                              field.field,
                              settings,
                            ),
                            onChanged: (value) => onChanged(field.field, value),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
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

class _ExperiencePresetPicker extends StatelessWidget {
  const _ExperiencePresetPicker({
    required this.settings,
    required this.onSelected,
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
        Text(
          _copy(context, 'overlay.workspace.experience.$selected'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
        SizedBox(height: tokens.space.sm),
        Wrap(
          spacing: tokens.space.xs,
          runSpacing: tokens.space.xs,
          children: const ['Smooth', 'Balanced', 'ReducedMotion']
              .map(
                (preset) => ChoiceChip(
                  key: Key('overlay-experience-$preset'),
                  label: Text(
                    _copy(context, 'overlay.workspace.experience.$preset'),
                  ),
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

class _Field extends StatelessWidget {
  const _Field({
    required this.spec,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.appearances = const [],
  });

  final OverlayWorkspaceFieldSpec spec;
  final Object? value;
  final bool enabled;
  final ValueChanged<Object?> onChanged;
  final List<OverlayWorkspaceAppearance> appearances;

  @override
  Widget build(BuildContext context) {
    final label = _fieldName(context, spec);
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
      OverlayWorkspaceFieldKind.toggle => SwitchListTile(
        key: Key('overlay-field-${spec.field}'),
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value == true,
        onChanged: enabled ? (next) => onChanged(next) : null,
      ),
      OverlayWorkspaceFieldKind.choice => DropdownButtonFormField<String>(
        key: Key('overlay-field-${spec.field}'),
        initialValue: spec.options.contains(value) ? value as String : null,
        decoration: InputDecoration(labelText: label),
        items:
            (spec.selectableOptions.isEmpty
                    ? spec.options
                    : spec.selectableOptions)
                .map(
                  (option) => DropdownMenuItem(
                    value: option,
                    child: Text(_optionName(context, option)),
                  ),
                )
                .toList(growable: false),
        onChanged: enabled
            ? (next) {
                if (next != null) onChanged(next);
              }
            : null,
      ),
      OverlayWorkspaceFieldKind.readOnlyChoice => InputDecorator(
        key: Key('overlay-field-${spec.field}'),
        decoration: InputDecoration(
          labelText: label,
          helperText: _copy(context, 'overlay.workspace.appearanceBoundValue'),
        ),
        child: Text(_optionName(context, value?.toString() ?? '')),
      ),
      OverlayWorkspaceFieldKind.numberChoice => DropdownButtonFormField<num>(
        key: Key('overlay-field-${spec.field}'),
        initialValue: numberValue != null
            ? spec.numberOptions.cast<num?>().firstWhere(
                (option) => option?.toDouble() == numberValue,
                orElse: () => null,
              )
            : null,
        decoration: InputDecoration(labelText: label),
        items: spec.numberOptions
            .map(
              (option) => DropdownMenuItem<num>(
                value: option,
                child: Text(_numberOptionName(context, spec, option)),
              ),
            )
            .toList(growable: false),
        onChanged: enabled
            ? (next) {
                if (next != null) onChanged(next);
              }
            : null,
      ),
      OverlayWorkspaceFieldKind.number => _NumberField(
        spec: spec,
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
      OverlayWorkspaceFieldKind.color => TextFormField(
        key: ValueKey('overlay-field-${spec.field}-$value'),
        initialValue: value?.toString() ?? '',
        enabled: enabled,
        decoration: InputDecoration(
          labelText: label,
          helperText: _copy(context, 'overlay.workspace.colorHelp'),
        ),
        onChanged: enabled
            ? (next) {
                if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(next)) {
                  onChanged(next.toUpperCase());
                }
              }
            : null,
      ),
      OverlayWorkspaceFieldKind.eventTypes => _EventTypeField(
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
      OverlayWorkspaceFieldKind.eventDurations => _EventDurationField(
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
    };
  }
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
    return DropdownButtonFormField<String>(
      key: const Key('overlay-field-skin'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _fieldName(
          context,
          overlayWorkspaceFieldSpecs.singleWhere(
            (field) => field.field == 'skin',
          ),
        ),
      ),
      items: appearances
          .map(
            (appearance) => DropdownMenuItem<String>(
              key: Key('overlay-appearance-option-${appearance.id}'),
              value: appearance.id,
              enabled: appearance.isAvailable,
              child: Text(
                '${english ? appearance.displayNameEn : appearance.displayNameZh}'
                '${appearance.isAvailable
                    ? ''
                    : traditional
                    ? '（未解鎖）'
                    : english
                    ? ' (locked)'
                    : '（未解锁）'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(growable: false),
      onChanged: enabled
          ? (next) {
              if (next != null) onChanged(next);
            }
          : null,
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.spec,
    required this.value,
    required this.onChanged,
  });

  final OverlayWorkspaceFieldSpec spec;
  final Object? value;
  final ValueChanged<Object?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final number = value is num ? (value as num).toDouble() : spec.minimum;
    final clamped = number.clamp(spec.minimum, spec.maximum).toDouble();
    final integral = value is int;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_fieldName(context, spec)}  ${integral ? clamped.round() : clamped.toStringAsFixed(2)}',
        ),
        Slider(
          key: Key('overlay-field-${spec.field}'),
          value: clamped,
          min: spec.minimum,
          max: spec.maximum,
          divisions: spec.divisions,
          onChanged: onChanged == null
              ? null
              : (next) => onChanged!(integral ? next.round() : next),
        ),
      ],
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
            return FilterChip(
              label: Text(
                _copy(context, 'overlay.workspace.event.${entry.$1}'),
              ),
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
    child: TextField(
      key: Key('overlay-duration-${widget.field}-input'),
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: _copy(context, 'overlay.workspace.durationDefault'),
        suffixText: _copy(context, 'overlay.workspace.durationSecondsSuffix'),
      ),
      onSubmitted: (_) => _commit(),
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
  return translated == key ? normalized : translated;
}

String _fieldName(BuildContext context, OverlayWorkspaceFieldSpec spec) {
  final key = 'overlay.workspace.field.${spec.field}';
  final translated = _copy(context, key);
  return translated == key ? spec.labelZh : translated;
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
