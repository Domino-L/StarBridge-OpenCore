import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_select_field.dart';
import '../../design_system/interaction/starbridge_slider.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_models.dart';

/// The opacities calm display actually uses; mirrors OverlayCalmDisplayLevels.
/// An unset (0) idle or lit level follows the overlay opacity: resting never
/// darkens a module below what the user already set, and lighting lifts a low
/// setting to a readable 85%. Nothing goes below 15%; idle never exceeds lit.
final class OverlayCalmLevels {
  const OverlayCalmLevels._(
    this.enabled,
    this.idle,
    this.lit,
    this.idleSet,
    this.litSet,
  );

  static const minimum = 0.15;
  static const defaultIdleCeiling = 0.35;
  static const defaultLitFloor = 0.85;

  factory OverlayCalmLevels.of(OverlayWorkspaceSettings settings) {
    double read(String field) => (settings[field] as num?)?.toDouble() ?? 0;
    final base = read('opacity').clamp(minimum, 1.0);
    final idleSetting = read('calmIdleOpacity');
    final litSetting = read('calmLitOpacity');
    final idle = idleSetting > 0
        ? idleSetting.clamp(minimum, 1.0)
        : (base < defaultIdleCeiling ? base : defaultIdleCeiling).clamp(
            minimum,
            1.0,
          );
    final lit = litSetting > 0
        ? litSetting.clamp(minimum, 1.0)
        : (base > defaultLitFloor ? base : defaultLitFloor);
    return OverlayCalmLevels._(
      settings['calmDisplay'] == 'On',
      idle < lit ? idle : lit,
      lit,
      idleSetting > 0,
      litSetting > 0,
    );
  }

  final bool enabled;
  final double idle;
  final double lit;
  final bool idleSet;
  final bool litSet;
}

/// Calm display settings, shown under the opacity controls of the overview,
/// members and chat modules. The values are shared by those three modules.
class OverlayCalmDisplayControls extends StatelessWidget {
  const OverlayCalmDisplayControls({
    required this.settings,
    required this.onSettingChanged,
    this.chatBarrage = false,
    super.key,
  });

  final OverlayWorkspaceSettings settings;
  final void Function(String field, Object? value) onSettingChanged;

  /// Barrage chat has no resting box, so it does not take part.
  final bool chatBarrage;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final copy = AppStrings.of(context).text;
    final levels = OverlayCalmLevels.of(settings);
    final enabled = levels.enabled;
    final wait = (settings['calmWaitSeconds'] as num?)?.toInt() ?? 10;
    final lightWhen = settings['calmLightWhen'] as String? ?? 'Relevant';

    void setIdle(double value) {
      if (value > levels.lit) onSettingChanged('calmLitOpacity', value);
      onSettingChanged('calmIdleOpacity', value);
    }

    void setLit(double value) {
      if (value < levels.idle) onSettingChanged('calmIdleOpacity', value);
      onSettingChanged('calmLitOpacity', value);
    }

    return Padding(
      key: const Key('overlay-calm-display'),
      padding: EdgeInsets.only(top: tokens.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StarBridgeSwitch.tile(
            controlKey: const Key('overlay-calm-enabled'),
            preserveNativeTile: true,
            label: copy('overlay.calm.title'),
            subtitle: copy(
              chatBarrage
                  ? 'overlay.calm.barrageNote'
                  : 'overlay.calm.subtitle',
            ),
            value: enabled,
            onChanged: (value) =>
                onSettingChanged('calmDisplay', value ? 'On' : 'Off'),
          ),
          if (!enabled)
            Padding(
              padding: EdgeInsets.only(top: tokens.space.xs),
              child: Text(
                copy('overlay.calm.offHint'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
            ),
          _LevelSlider(
            key: const Key('overlay-calm-idle'),
            label: copy('overlay.calm.idle'),
            value: levels.idle,
            following: !levels.idleSet,
            enabled: enabled,
            onChanged: setIdle,
            onFollow: () => onSettingChanged('calmIdleOpacity', 0.0),
          ),
          _LevelSlider(
            key: const Key('overlay-calm-lit'),
            label: copy('overlay.calm.lit'),
            value: levels.lit,
            following: !levels.litSet,
            enabled: enabled,
            onChanged: setLit,
            onFollow: () => onSettingChanged('calmLitOpacity', 0.0),
          ),
          SizedBox(height: tokens.space.sm),
          _Preview(idle: levels.idle, lit: levels.lit, enabled: enabled),
          SizedBox(height: tokens.space.md),
          StarBridgeSelectField<num>(
            key: const Key('overlay-calm-wait'),
            identity: 'overlay-calm-wait',
            value: const [5, 10, 20, 30].contains(wait) ? wait : 10,
            decoration: InputDecoration(labelText: copy('overlay.calm.wait')),
            options: [
              for (final seconds in const [5, 10, 20, 30])
                StarBridgeSelectOption<num>(
                  value: seconds,
                  label: copy('overlay.calm.waitSeconds')
                      .replaceAll('{seconds}', '$seconds'),
                ),
            ],
            onSelected: enabled
                ? (next, _) => onSettingChanged('calmWaitSeconds', next.toInt())
                : null,
          ),
          SizedBox(height: tokens.space.md),
          StarBridgeSelectField<String>(
            key: const Key('overlay-calm-light-when'),
            identity: 'overlay-calm-light-when',
            value: lightWhen == 'Any' ? 'Any' : 'Relevant',
            decoration: InputDecoration(
              labelText: copy('overlay.calm.lightWhen'),
              helperText: copy('overlay.calm.lightWhenHelp'),
              helperMaxLines: 3,
            ),
            options: [
              StarBridgeSelectOption(
                value: 'Relevant',
                label: copy('overlay.calm.lightWhen.Relevant'),
              ),
              StarBridgeSelectOption(
                value: 'Any',
                label: copy('overlay.calm.lightWhen.Any'),
              ),
            ],
            onSelected: enabled
                ? (next, _) => onSettingChanged('calmLightWhen', next)
                : null,
          ),
          SizedBox(height: tokens.space.md),
          _PeekKey(
            binding: settings['calmPeekHotkey'] as String? ?? '',
            enabled: enabled,
            onChanged: (value) => onSettingChanged('calmPeekHotkey', value),
          ),
        ],
      ),
    );
  }
}

/// One-time introduction for settings saved before calm display existed. A
/// single slim line on the page; the explanation and the choice open in a
/// dialog, so narrow or large-text layouts keep their room.
class OverlayCalmDisplayIntro extends StatelessWidget {
  const OverlayCalmDisplayIntro({required this.onChoose, super.key});

  /// 'On' or 'Off'.
  final ValueChanged<String> onChoose;

  Future<void> _open(BuildContext context, InteractionSource source) async {
    final copy = AppStrings.of(context).text;
    final choice = await showStarBridgeDialog<String>(
      context,
      source: source,
      builder: (context) => AlertDialog(
        key: const Key('overlay-calm-intro-dialog'),
        title: Text(copy('overlay.calm.introTitle')),
        content: Text(copy('overlay.calm.introBody')),
        actions: [
          StarBridgeActionButton(
            controlKey: const Key('overlay-calm-intro-off'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) =>
                dismissStarBridgeDialog(context, source: source, result: 'Off'),
            child: Text(copy('overlay.calm.introLater')),
          ),
          StarBridgeActionButton(
            controlKey: const Key('overlay-calm-intro-on'),
            onActivate: (source) =>
                dismissStarBridgeDialog(context, source: source, result: 'On'),
            child: Text(copy('overlay.calm.introOn')),
          ),
        ],
      ),
    );
    if (choice != null) onChoose(choice);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final copy = AppStrings.of(context).text;
    return Padding(
      key: const Key('overlay-calm-intro'),
      padding: EdgeInsets.only(top: tokens.space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${copy('overlay.calm.introTitle')} · ${copy('overlay.calm.introShort')}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.colors.accent),
            ),
          ),
          StarBridgeActionButton(
            controlKey: const Key('overlay-calm-intro-open'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) => _open(context, source),
            child: Text(copy('overlay.calm.introOpen')),
          ),
        ],
      ),
    );
  }
}

class _LevelSlider extends StatelessWidget {
  const _LevelSlider({
    required this.label,
    required this.value,
    required this.following,
    required this.enabled,
    required this.onChanged,
    required this.onFollow,
    super.key,
  });

  final String label;
  final double value;
  final bool following;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final copy = AppStrings.of(context).text;
    final secondary = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: tokens.colors.textSecondary);
    return Padding(
      padding: EdgeInsets.only(top: tokens.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                '${(value * 100).round()}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tokens.colors.textSecondary,
                  fontFamily: tokens.typography.monoFamily,
                ),
              ),
            ],
          ),
          StarBridgeSlider(
            semanticLabel: label,
            value: value.clamp(OverlayCalmLevels.minimum, 1.0),
            min: OverlayCalmLevels.minimum,
            max: 1,
            divisions: 17,
            valueLabel: (value) => '${(value * 100).round()}%',
            onChanged: enabled ? onChanged : null,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  copy(
                    following
                        ? 'overlay.calm.following'
                        : 'overlay.calm.custom',
                  ),
                  style: secondary,
                ),
              ),
              if (!following)
                StarBridgeActionButton(
                  controlKey: Key('${(key as ValueKey<String>).value}-follow'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: enabled ? (_) => onFollow() : null,
                  child: Text(copy('overlay.calm.follow')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What a module looks like resting and lit, at the real opacities.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.idle,
    required this.lit,
    required this.enabled,
  });

  final double idle;
  final double lit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final copy = AppStrings.of(context).text;
    Widget swatch(String key, String label, double opacity) {
      final tokens = context.tokens;
      return Expanded(
        child: Opacity(
          key: Key(key),
          opacity: enabled ? opacity : 1,
          child: Container(
            padding: EdgeInsets.all(tokens.space.sm),
            decoration: BoxDecoration(
              color: tokens.surfaces.ground.fill,
              border: Border.all(color: tokens.colors.accent),
              borderRadius: tokens.shape.small,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy('overlay.calm.previewModule'),
                  style: TextStyle(
                    color: tokens.colors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label.replaceAll('{percent}', '${(opacity * 100).round()}'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        swatch(
          'overlay-calm-preview-idle',
          copy('overlay.calm.previewIdle'),
          idle,
        ),
        SizedBox(width: context.tokens.space.sm),
        swatch(
          'overlay-calm-preview-lit',
          copy('overlay.calm.previewLit'),
          lit,
        ),
      ],
    );
  }
}

/// Records the key that shows every module lit while held. Same rules as the
/// overlay hotkey: a modifier with a letter or digit, or an F key alone.
class _PeekKey extends StatefulWidget {
  const _PeekKey({
    required this.binding,
    required this.enabled,
    required this.onChanged,
  });

  final String binding;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_PeekKey> createState() => _PeekKeyState();
}

class _PeekKeyState extends State<_PeekKey> {
  static final _modifiers = <LogicalKeyboardKey>{
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };
  final _focus = FocusNode(debugLabel: 'overlay-calm-peek');
  bool _capturing = false;
  bool _invalid = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!_capturing || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _capturing = false);
      return KeyEventResult.handled;
    }

    if (_modifiers.contains(event.logicalKey)) return KeyEventResult.handled;
    final keyboard = HardwareKeyboard.instance;
    final binding = [
      if (keyboard.isControlPressed) 'Ctrl',
      if (keyboard.isAltPressed) 'Alt',
      if (keyboard.isShiftPressed) 'Shift',
      if (keyboard.isMetaPressed) 'Win',
      event.logicalKey.keyLabel.trim().toUpperCase(),
    ].join('+');
    final functionKey = RegExp(r'^F(?:[1-9]|1[0-2])$')
        .hasMatch(event.logicalKey.keyLabel.trim().toUpperCase());
    if (!OverlayWorkspaceSettings.peekHotkeyPattern.hasMatch(binding) ||
        (!functionKey && !binding.contains('+'))) {
      setState(() => _invalid = true);
      return KeyEventResult.handled;
    }
    widget.onChanged(binding);
    setState(() {
      _capturing = false;
      _invalid = false;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final copy = AppStrings.of(context).text;
    final secondary = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: tokens.colors.textSecondary);
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Column(
        key: const Key('overlay-calm-peek'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(copy('overlay.calm.peek'))),
              Text(
                _capturing
                    ? copy('overlay.calm.peekCapturing')
                    : widget.binding.isEmpty
                    ? copy('overlay.calm.peekUnbound')
                    : widget.binding,
                key: const Key('overlay-calm-peek-binding'),
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: _capturing ? tokens.colors.accent : null),
              ),
            ],
          ),
          if (_invalid)
            Text(
              copy('overlay.workspace.hotkeyCaptureInvalid'),
              style: TextStyle(color: tokens.colors.danger),
            ),
          Text(copy('overlay.calm.peekHelp'), style: secondary),
          Wrap(
            spacing: tokens.space.sm,
            children: [
              StarBridgeActionButton(
                controlKey: const Key('overlay-calm-peek-record'),
                onActivate: widget.enabled && !_capturing
                    ? (_) {
                        setState(() {
                          _capturing = true;
                          _invalid = false;
                        });
                        _focus.requestFocus();
                      }
                    : null,
                child: Text(copy('overlay.calm.peekRecord')),
              ),
              StarBridgeActionButton(
                controlKey: const Key('overlay-calm-peek-clear'),
                kind: StarBridgeActionKind.quiet,
                onActivate: widget.enabled && widget.binding.isNotEmpty
                    ? (_) => widget.onChanged('')
                    : null,
                child: Text(copy('overlay.calm.peekClear')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
