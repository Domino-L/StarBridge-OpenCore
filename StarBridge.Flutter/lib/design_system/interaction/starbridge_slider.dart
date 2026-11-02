import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_activation_origin.dart';
import 'starbridge_interaction_theme.dart';
import 'starbridge_native_slider_frame.dart';

/// Presentation of an owner's current value. No persistence or debounce.
/// Pointer changes follow directly; keyboard/reader actions have no FX tail.
class StarBridgeSlider extends StatefulWidget {
  const StarBridgeSlider({
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.onChangeCancel,
    this.controlKey,
    this.semanticLabel,
    this.valueLabel,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.keyboardStep,
    super.key,
  });
  final double value, min, max;
  final int? divisions;

  /// Optional value-unit step for keyboard and reader input. Does not add
  /// painted ticks or snap a pointer drag (unlike divisions).
  final double? keyboardStep;
  final ValueChanged<double>? onChanged, onChangeEnd;
  final VoidCallback? onChangeCancel;
  final Key? controlKey;
  final String? semanticLabel;
  final String Function(double)? valueLabel;
  @override
  State<StarBridgeSlider> createState() => _State();
}

class _State extends State<StarBridgeSlider> {
  late final _focus = FocusNode(onKeyEvent: _nativeKey);
  bool _native = false;
  bool _pointerActive = false, _hovered = false;
  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted && _native) {
      setState(() {
        if (!_focus.hasFocus && _source == InteractionSource.pointer) {
          _source = InteractionSource.programmatic;
        }
        if (_focus.hasFocus &&
            _source != InteractionSource.pointer &&
            !_pointerActive &&
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional) {
          _source = InteractionSource.keyboard;
        }
      });
    }
  }

  KeyEventResult _nativeKey(FocusNode node, KeyEvent event) {
    if (!_native ||
        !mounted ||
        !enabled ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      // Let traversal keep its authority; retire only the pointer decoration.
      setState(() => _source = InteractionSource.keyboard);
      return KeyEventResult.ignored;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final value = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowRight => next(rtl ? -1 : 1),
      LogicalKeyboardKey.arrowLeft => next(rtl ? 1 : -1),
      LogicalKeyboardKey.arrowUp => next(1),
      LogicalKeyboardKey.arrowDown => next(-1),
      LogicalKeyboardKey.home => widget.min,
      LogicalKeyboardKey.end => widget.max,
      _ => null,
    };
    if (value == null) return KeyEventResult.ignored;
    keyboard(value);
    return KeyEventResult.handled;
  }

  InteractionSource _source = InteractionSource.programmatic;
  bool _canceled = false;
  bool _nativePointerStarted = false, _nativeReaderActive = false;
  double? _nativeReaderValue;
  bool get enabled => widget.onChanged != null;
  String label(double value) =>
      widget.valueLabel?.call(value) ?? value.toStringAsFixed(2);
  double next(int dir) =>
      (widget.value +
              dir *
                  (widget.keyboardStep ??
                      (widget.max - widget.min) / (widget.divisions ?? 20)))
          .clamp(widget.min, widget.max);

  // The native semantics node owns its Portal linkage and accessibility focus.
  // Translate only its value command, leaving pointer snapping/geometry native.
  double get _nativeProjectedValue {
    final range = widget.max - widget.min;
    if (range == 0) return widget.min;
    var fraction = (widget.value - widget.min) / range;
    final divisions = widget.divisions;
    if (divisions != null && divisions > 0) {
      fraction = (fraction * divisions).round() / divisions;
    }
    return widget.min + fraction.clamp(0, 1) * range;
  }

  String _nativeSemanticValue(double candidate) {
    final current = _nativeProjectedValue;
    final epsilon = (widget.max - widget.min).abs() * 1e-9 + 1e-12;
    return label(
      candidate > current + epsilon
          ? next(1)
          : candidate < current - epsilon
          ? next(-1)
          : current,
    );
  }

  void _nativeStart(double _) {
    _canceled = false;
    _nativeReaderValue = null;
    // Native semantics also calls start/change/end. A second start while a
    // pointer drag is held is an assistive interruption, not another pointer.
    _nativeReaderActive = !_pointerActive || _nativePointerStarted;
    if (!_nativeReaderActive) {
      _nativePointerStarted = true;
    } else {
      setState(() => _source = InteractionSource.keyboard);
    }
  }

  void _nativeChange(double candidate) {
    if (!_nativeReaderActive) {
      change(candidate, InteractionSource.pointer);
      return;
    }
    final direction = candidate.compareTo(widget.value);
    if (direction == 0) return;
    final value = next(direction);
    if (value == widget.value) return;
    _nativeReaderValue = value;
    change(value, InteractionSource.keyboard);
  }

  void _nativeEnd(double value) {
    if (!_nativeReaderActive) {
      end(value, InteractionSource.pointer);
      return;
    }
    final actual = _nativeReaderValue;
    _nativeReaderValue = null;
    _nativeReaderActive = false;
    if (actual != null) end(actual, InteractionSource.keyboard);
  }

  void change(double value, InteractionSource source) {
    if (!mounted || !enabled) return;
    if (source == InteractionSource.keyboard) {
      setState(() {
        _source = source;
      });
    }
    runStarBridgeSynchronousActivation(source, () => widget.onChanged!(value));
  }

  void end(double value, InteractionSource source) {
    if (!mounted || !enabled || _canceled) return;
    runStarBridgeSynchronousActivation(
      source,
      () => widget.onChangeEnd?.call(value),
    );
  }

  void keyboard(double value) {
    if (!mounted || !enabled) return;
    // Cancellation belongs to the old pointer operation, not this new input.
    _canceled = false;
    if (value == widget.value) {
      setState(() {
        _source = InteractionSource.keyboard;
      });
      return;
    }
    change(value, InteractionSource.keyboard);
    end(value, InteractionSource.keyboard);
  }

  void cancel() {
    if (!mounted || !enabled) return;
    _canceled = true;
    runStarBridgeSynchronousActivation(
      InteractionSource.pointer,
      () => widget.onChangeCancel?.call(),
    );
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        _native = data.suite == InteractionSuite.standard;
        if (data.suite != InteractionSuite.standard) {
          return SuiteSlider(
            key: widget.controlKey,
            focusNode: _focus,
            value: widget.value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            keyboardStep: widget.keyboardStep,
            semanticLabel: widget.semanticLabel,
            valueLabel: widget.valueLabel,
            onInputSource: (source) {
              _source = source;
              _canceled = false;
            },
            onChanged: enabled ? (v) => change(v, _source) : null,
            onChangeEnd: enabled ? (v) => end(v, _source) : null,
            onChangeCancel: enabled ? cancel : null,
          );
        }
        final rtl = Directionality.of(context) == TextDirection.rtl;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                keyboard(next(rtl ? -1 : 1)),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                keyboard(next(rtl ? 1 : -1)),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                keyboard(next(1)),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                keyboard(next(-1)),
            const SingleActivator(LogicalKeyboardKey.home): () =>
                keyboard(widget.min),
            const SingleActivator(LogicalKeyboardKey.end): () =>
                keyboard(widget.max),
          },
          child: MouseRegion(
            onEnter: (_) {
              if (mounted) setState(() => _hovered = true);
            },
            onExit: (_) {
              if (mounted) setState(() => _hovered = false);
            },
            child: Listener(
              onPointerDown: (_) {
                if (mounted && enabled) {
                  setState(() {
                    _source = InteractionSource.pointer;
                    _canceled = false;
                    _pointerActive = true;
                    _nativePointerStarted = false;
                  });
                }
              },
              onPointerUp: (_) {
                if (mounted) {
                  setState(() {
                    _pointerActive = false;
                    _nativePointerStarted = false;
                  });
                }
              },
              onPointerCancel: (_) {
                if (!mounted) return;
                setState(() {
                  _pointerActive = false;
                  _nativePointerStarted = false;
                });
                cancel();
              },
              child: StarBridgeNativeSliderFrame(
                indicatorLabel: label(widget.value),
                instant:
                    !data.animates || _source == InteractionSource.keyboard,
                engaged:
                    enabled &&
                    (_pointerActive ||
                        _hovered ||
                        (_focus.hasFocus &&
                            FocusManager.instance.highlightMode ==
                                FocusHighlightMode.traditional)),
                child: Slider(
                  key: widget.controlKey,
                  focusNode: _focus,
                  value: widget.value,
                  min: widget.min,
                  max: widget.max,
                  divisions: widget.divisions,
                  // Name belongs to the one native AX node. The frame paints
                  // the original numeric bubble independently of this name.
                  label: widget.semanticLabel ?? '',
                  semanticFormatterCallback: _nativeSemanticValue,
                  onChangeStart: enabled ? _nativeStart : null,
                  onChanged: enabled ? _nativeChange : null,
                  onChangeEnd: enabled ? _nativeEnd : null,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
