import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_interaction_theme.dart';
import 'starbridge_activation_origin.dart';

@immutable
class StarBridgeSegment<T> {
  const StarBridgeSegment({
    required this.value,
    required this.label,
    this.icon,
  });
  final T value;
  final String label;
  final Widget? icon;
}

/// Single-choice presentation. The preferences owner supplies its projection
/// and all enabled/busy rules; this widget never commits a selection itself.
class StarBridgeSegmentedControl<T> extends StatefulWidget {
  const StarBridgeSegmentedControl({
    required this.segments,
    required this.value,
    this.onChanged,
    this.onActivate,
    this.controlKey,
    this.nativeStyle,
    this.showSelectedIcon = false,
    super.key,
  });

  final List<StarBridgeSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  /// Source-aware delegate. When supplied it takes precedence over [onChanged].
  final void Function(T value, InteractionSource source)? onActivate;
  final Key? controlKey;

  /// The consumer's original [SegmentedButton] style (density, shape…), kept
  /// for the standard suite so adopting this control never changes the
  /// native geometry. Suite feedback overrides only its own properties.
  final ButtonStyle? nativeStyle;

  /// Standard suite only: keep the native selected checkmark for consumers
  /// whose original [SegmentedButton] showed it (its width is part of the
  /// equal segment widths). Suites keep their approved segment face.
  final bool showSelectedIcon;

  @override
  State<StarBridgeSegmentedControl<T>> createState() =>
      _StarBridgeSegmentedControlState<T>();
}

class _StarBridgeSegmentedControlState<T>
    extends State<StarBridgeSegmentedControl<T>> {
  final _labels = <T, GlobalKey>{};
  bool _hadNativeFocus = false;
  InteractionSource _nativeSource = InteractionSource.keyboard;
  bool get _enabled => widget.onActivate != null || widget.onChanged != null;

  void _activate(T value, InteractionSource source, {bool native = false}) {
    if (!_enabled || value == widget.value) return;
    void invoke() {
      if (widget.onActivate case final onActivate?) {
        onActivate(value, source);
      } else {
        widget.onChanged!(value);
      }
    }

    if (native) {
      runStarBridgeSynchronousActivation(source, invoke);
    } else {
      unawaited(runStarBridgeActivation(source, invoke));
    }
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_updateNativeFocus);
  }

  bool _isFocused(T value) {
    final context = _labels[value]?.currentContext;
    return context != null && (Focus.maybeOf(context)?.hasFocus ?? false);
  }

  void _updateNativeFocus() {
    final focused = widget.segments.any((e) => _isFocused(e.value));
    if (mounted && (focused || _hadNativeFocus)) {
      setState(() => _hadNativeFocus = focused);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_updateNativeFocus);
    super.dispose();
  }

  void _activateFocused() {
    if (!_enabled) return;
    _nativeSource = InteractionSource.keyboard;
    for (final segment in widget.segments) {
      final context = _labels[segment.value]?.currentContext;
      if (context != null && (Focus.maybeOf(context)?.hasFocus ?? false)) {
        if (segment.value != widget.value) {
          _activate(segment.value, InteractionSource.keyboard, native: true);
        }
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      StarBridgeInteractionRegion(child: Builder(builder: _buildControl));

  Widget _buildControl(BuildContext context) {
    assert(widget.segments.length >= 2);
    assert(
      widget.segments.map((e) => e.value).toSet().length ==
          widget.segments.length,
    );
    final selected = widget.segments.indexWhere((e) => e.value == widget.value);
    assert(selected >= 0, 'The owner must supply a valid projected value.');
    _labels.removeWhere(
      (value, _) => !widget.segments.any((segment) => segment.value == value),
    );
    final data = InteractionScope.of(context);
    if (data.suite == InteractionSuite.standard) {
      return CallbackShortcuts(
        bindings: {
          for (final key in [
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.numpadEnter,
            LogicalKeyboardKey.space,
          ])
            SingleActivator(key): _activateFocused,
        },
        child: Stack(
          children: [
            Listener(
              onPointerDown: (_) => _nativeSource = InteractionSource.pointer,
              child: ExcludeSemantics(
                child: SegmentedButton<T>(
                  key: widget.controlKey,
                  showSelectedIcon: widget.showSelectedIcon,
                  segments: [
                    for (final segment in widget.segments)
                      ButtonSegment<T>(
                        value: segment.value,
                        icon: segment.icon,
                        label: Text(
                          segment.label,
                          key: _labels.putIfAbsent(
                            segment.value,
                            GlobalKey.new,
                          ),
                        ),
                      ),
                  ],
                  selected: {widget.value},
                  onSelectionChanged: !_enabled
                      ? null
                      : (selection) {
                          final source = _nativeSource;
                          _nativeSource = InteractionSource.keyboard;
                          _activate(selection.single, source, native: true);
                        },
                  style: (widget.nativeStyle ?? const ButtonStyle()).copyWith(
                    animationDuration: Duration.zero,
                    splashFactory: data.reduceMotion
                        ? NoSplash.splashFactory
                        : null,
                  ),
                ),
              ),
            ),
            // Flutter lays out these native horizontal segments at equal widths.
            // Mirror their full hit rectangles for one accessible action each,
            // bypassing InkWell's semantic tap (which starts a splash).
            Positioned.fill(
              child: Row(
                children: [
                  for (final segment in widget.segments)
                    Expanded(
                      child: Semantics(
                        button: true,
                        enabled: _enabled,
                        selected: segment.value == widget.value,
                        focusable: _enabled,
                        focused: _isFocused(segment.value),
                        inMutuallyExclusiveGroup: true,
                        label: segment.label,
                        onTap: !_enabled
                            ? null
                            : () {
                                _activate(
                                  segment.value,
                                  InteractionSource.keyboard,
                                  native: true,
                                );
                              },
                        child: const IgnorePointer(child: SizedBox.expand()),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final control = SuiteSelectionTrack(
      key: widget.controlKey,
      style: TrackStyle.segmented,
      items: [
        for (var i = 0; i < widget.segments.length; i++)
          TrackItem(
            id: 'segment-$i',
            label: widget.segments[i].label,
            enabled: _enabled,
          ),
      ],
      selected: selected,
      onChanged: (index, source) =>
          _activate(widget.segments[index].value, source),
      // Keep the package's default geometry for existing text-only consumers.
      // Widget icons use the same track anchors and pressables, not a second
      // gesture layer or a locally owned selection.
      layoutBuilder: widget.segments.any((segment) => segment.icon != null)
          ? (context, layout) => LayoutBuilder(
              builder: (context, constraints) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.segments.length; i++)
                    if (constraints.hasBoundedWidth)
                      Expanded(child: _iconTarget(context, data, layout, i))
                    else
                      _iconTarget(context, data, layout, i),
                ],
              ),
            )
          : null,
    );
    final decorated = widget.segments.any((segment) => segment.icon != null)
        ? Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: data.palette.surface,
              border: Border.all(color: data.palette.border),
              borderRadius: suiteRadius(data.suite, 7),
            ),
            child: control,
          )
        : control;
    return !_enabled
        ? IgnorePointer(child: ExcludeFocus(child: decorated))
        : decorated;
  }

  Widget _iconTarget(
    BuildContext context,
    InteractionData data,
    SelectionTrackLayout layout,
    int index,
  ) {
    final segment = widget.segments[index];
    final id = 'segment-$index';
    final selected = segment.value == widget.value;
    return layout.anchor(
      id,
      SuitePressable(
        kind: PressableKind.tab,
        selected: selected,
        semanticSelected: selected,
        semanticLabel: segment.label,
        excludeChildSemantics: true,
        focusNode: layout.focusNode(id),
        minHeight: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        baseRadius: 5,
        onActivate: _enabled ? (source) => layout.activate(id, source) : null,
        builder: (context, visual) => Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (segment.icon case final icon?) ...[
              ExcludeSemantics(
                child: IconTheme(
                  data: IconThemeData(color: visual.foreground, size: 18),
                  child: icon,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                segment.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: visual.foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
