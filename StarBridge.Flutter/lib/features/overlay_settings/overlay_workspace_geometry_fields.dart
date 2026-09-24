import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_workspace_layout_geometry.dart';
import 'overlay_workspace_models.dart';

/// Pixel inputs use the same reference surface and bounds as drag/resize.
class OverlayWorkspaceGeometryFields extends StatelessWidget {
  const OverlayWorkspaceGeometryFields({
    required this.item,
    required this.enabled,
    required this.onChanged,
    this.surfaceSize = OverlayWorkspaceLayoutGeometry.referenceSize,
    super.key,
  });
  final OverlayWorkspaceLayoutItem item;
  final bool enabled;
  final Size surfaceSize;
  final ValueChanged<OverlayWorkspaceLayoutItem> onChanged;

  @override
  Widget build(BuildContext context) {
    final rect = OverlayWorkspaceLayoutGeometry.resolve(
      item,
      surfaceSize: surfaceSize,
    );
    final values = {
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
    };
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final entry in values.entries)
            SizedBox(
              width: ((constraints.maxWidth - 12) / 2).clamp(
                0.0,
                double.infinity,
              ),
              child: _PixelInput(
                key: Key('overlay-pixels-${item.key}-${entry.key}'),
                label:
                    '${AppStrings.of(context).text('overlay.workspace.layout.${entry.key}')} (px)',
                value: entry.value,
                enabled: enabled,
                onCommitted: (value) => onChanged(
                  OverlayWorkspaceLayoutGeometry.nudge(
                    item,
                    entry.key,
                    value - entry.value,
                    surfaceSize: surfaceSize,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PixelInput extends StatefulWidget {
  const _PixelInput({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onCommitted,
    super.key,
  });
  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onCommitted;
  @override
  State<_PixelInput> createState() => _PixelInputState();
}

class _PixelInputState extends State<_PixelInput> {
  late final _text = TextEditingController(
    text: widget.value.toStringAsFixed(1),
  );
  final _focus = FocusNode();
  bool _invalid = false;
  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (!widget.enabled) return;
    final number = double.tryParse(_text.text.trim());
    if (number == null || !number.isFinite || number < 0) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    if (number != widget.value) widget.onCommitted(number);
    // The parent supplies the clamped result in didUpdateWidget.
    if (number == widget.value) _text.text = widget.value.toStringAsFixed(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _text.text = widget.value.toStringAsFixed(1);
    });
  }

  @override
  void didUpdateWidget(covariant _PixelInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value ||
        widget.enabled != oldWidget.enabled) {
      _text.text = widget.value.toStringAsFixed(1);
      _invalid = false;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    focusNode: _focus,
    enabled: widget.enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: widget.label,
      errorText: _invalid
          ? AppStrings.of(context).text('overlay.editor.numberInvalid')
          : null,
    ),
    onSubmitted: (_) => _commit(),
    onTapOutside: (_) => _focus.unfocus(),
  );
}
