import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/color_choice_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/styles/overlay_preview_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text('overlay.color.$key');

Color? _parse(String value) => parseOverlayPickerColor(value);

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Edits a local draft only. Opening or dismissing the dialog never changes it.
class OverlayColorField extends StatefulWidget {
  const OverlayColorField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.helperText,
    super.key,
  });

  final String label;
  final String value;
  final String? helperText;
  final ValueChanged<String>? onChanged;

  @override
  State<OverlayColorField> createState() => _OverlayColorFieldState();
}

class _OverlayColorFieldState extends State<OverlayColorField> {
  bool _open = false;

  Future<void> _pick() async {
    if (_open || widget.onChanged == null) return;
    _open = true;
    final original = widget.value;
    final result = await showDialog<String>(
      context: context,
      builder: (_) =>
          OverlayColorPickerDialog(label: widget.label, initialValue: original),
    );
    _open = false;
    // A refresh, preset switch or theme toggle must not receive a stale edit.
    if (!mounted || widget.value != original || result == null) return;
    if (result != original.toUpperCase()) widget.onChanged?.call(result);
  }

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helperText,
      helperMaxLines: 3,
      enabled: widget.onChanged != null,
      border: InputBorder.none,
      contentPadding: const EdgeInsets.only(top: 8, bottom: 4),
    ),
    child: OutlinedButton(
      onPressed: widget.onChanged == null ? null : _pick,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _Swatch(color: _parse(widget.value) ?? Colors.white, size: 24),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.value)),
            Text(_copy(context, 'choose')),
            const SizedBox(width: 6),
            const ColorChoiceIcon.palette(),
          ],
        ),
      ),
    ),
  );
}

class OverlayColorPickerDialog extends StatefulWidget {
  const OverlayColorPickerDialog({
    required this.label,
    required this.initialValue,
    super.key,
  });

  final String label;
  final String initialValue;

  @override
  State<OverlayColorPickerDialog> createState() =>
      _OverlayColorPickerDialogState();
}

class _OverlayColorPickerDialogState extends State<OverlayColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _text;
  bool _valid = true;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(_parse(widget.initialValue) ?? Colors.white);
    _text = TextEditingController(text: _hex(_hsv.toColor()));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _set(HSVColor color) => setState(() {
    _hsv = color;
    _valid = true;
    _text.text = _hex(color.toColor());
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AlertDialog(
      title: Text(widget.label),
      insetPadding: const EdgeInsets.all(16),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _Swatch(color: _parse(widget.initialValue) ?? Colors.white),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: StarBridgeIcon(
                      StarBridgeIconSemantic.forward,
                      size: 18,
                    ),
                  ),
                  _Swatch(color: _hsv.toColor()),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_copy(context, 'preview'))),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  const height = 150.0;
                  void select(Offset point) => _set(
                    _hsv
                        .withSaturation(
                          (point.dx / constraints.maxWidth).clamp(0, 1),
                        )
                        .withValue((1 - point.dy / height).clamp(0, 1)),
                  );
                  return Semantics(
                    label: _copy(context, 'palette'),
                    child: GestureDetector(
                      key: const Key('overlay-color-palette'),
                      onTapDown: (event) => select(event.localPosition),
                      onPanStart: (event) => select(event.localPosition),
                      onPanUpdate: (event) => select(event.localPosition),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          height: height,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white,
                                      HSVColor.fromAHSV(
                                        1,
                                        _hsv.hue,
                                        1,
                                        1,
                                      ).toColor(),
                                    ],
                                  ),
                                ),
                              ),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Colors.black],
                                  ),
                                ),
                              ),
                              Positioned(
                                left:
                                    (_hsv.saturation * constraints.maxWidth - 7)
                                        .clamp(0, constraints.maxWidth - 14),
                                top: ((1 - _hsv.value) * height - 7).clamp(
                                  0,
                                  height - 14,
                                ),
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black,
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              // All three axes are keyboard accessible, not just the pointer pad.
              for (final axis in ['hue', 'saturation', 'brightness']) ...[
                Text(
                  _copy(context, axis),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                _ColorAxis(
                  hue: axis == 'hue',
                  child: Slider(
                    key: Key('overlay-color-$axis'),
                    value: switch (axis) {
                      'hue' => _hsv.hue / 360,
                      'saturation' => _hsv.saturation,
                      _ => _hsv.value,
                    },
                    semanticFormatterCallback: (value) =>
                        '${_copy(context, axis)} ${(value * (axis == 'hue' ? 360 : 100)).round()}${axis == 'hue' ? '°' : '%'}',
                    onChanged: (value) => _set(switch (axis) {
                      'hue' => _hsv.withHue(value * 360),
                      'saturation' => _hsv.withSaturation(value),
                      _ => _hsv.withValue(value),
                    }),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                key: const Key('overlay-color-hex'),
                controller: _text,
                maxLength: 7,
                decoration: InputDecoration(
                  labelText: _copy(context, 'hex'),
                  hintText: '#RRGGBB',
                  counterText: '',
                  errorText: _valid ? null : _copy(context, 'invalid'),
                ),
                onChanged: (value) => setState(() {
                  final color = _parse(value);
                  _valid = color != null;
                  if (color != null) _hsv = HSVColor.fromColor(color);
                }),
              ),
              const SizedBox(height: 8),
              Text(
                _copy(context, 'draftHint'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.of(context).text('common.cancel')),
        ),
        FilledButton(
          key: const Key('overlay-color-apply'),
          onPressed: _valid
              ? () => Navigator.of(context).pop(_hex(_hsv.toColor()))
              : null,
          child: Text(_copy(context, 'apply')),
        ),
      ],
    );
  }
}

class _ColorAxis extends StatelessWidget {
  const _ColorAxis({required this.hue, required this.child});
  final bool hue;
  final Widget child;

  @override
  Widget build(BuildContext context) => !hue
      ? child
      : Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: const LinearGradient(
                    colors: overlayPickerHueColors,
                  ),
                ),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
              ),
              child: child,
            ),
          ],
        );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, this.size = 32});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: context.tokens.colors.textSecondary),
    ),
  );
}
